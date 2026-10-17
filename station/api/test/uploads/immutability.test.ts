// F7 AC5: the originals container rejects overwrite and delete of a sealed file.
//
// Proven against Azurite through every path the station exposes:
// - upload targets (SAS URLs): create-only, one blob, so every overwrite, block commit, delete
//   or read of an existing blob is refused, and a target cannot be re-pointed to another blob;
// - station routes: no target is ever issued again for a verified file, file reports after
//   sealing are refused, and there is no route that overwrites or deletes a blob.
//
// What Azurite does not emulate (last test): container immutability policies. A client holding
// the account key can still overwrite a blob in Azurite. The station never holds such a client
// in Azure (managed identity, no account key) and the Azure container has a time-based
// immutability policy (infra) that blocks overwrite and delete for every identity.

import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";
import { BlobServiceClient } from "@azure/storage-blob";
import { BlobExistsError, firstBlobName, manifestBlobName } from "../../src/storage/originals.js";
import { makePackage, sha256, type TestPackage } from "./support/package.js";
import {
  putToTarget,
  startUploadStation,
  uploadVerifiedPackage,
  type UploadSessionView,
  type UploadStation,
  type UploadTargetView,
} from "./support/station.js";

const VERSION = "2025-01-05";

let station: UploadStation;
let pkg: TestPackage;
/** The targets handed out when the session opened (still within their 30 minutes). */
let original: UploadSessionView;

before(async () => {
  station = await startUploadStation();
  pkg = makePackage();
  original = await uploadVerifiedPackage(station, pkg);
  const sealed = await station.seal(pkg.packageId, pkg.manifestBytes);
  assert.equal(sealed.statusCode, 202, sealed.body);
});

after(async () => {
  await station?.close();
});

function targets(): [string, UploadTargetView][] {
  return original.files.map((file) => {
    assert.ok(file.upload, file.path);
    return [file.path, file.upload];
  });
}

async function assertUnchanged(path: string): Promise<void> {
  const digest = await station.storage.digest(firstBlobName(pkg.packageId, path));
  const declared = pkg.session.files.find((file) => file.path === path);
  assert.ok(digest, `${path} must still exist`);
  assert.equal(digest.sha256, declared?.sha256, `${path} must keep its verified bytes`);
  assert.equal(digest.bytes, declared?.bytes, path);
}

function withQuery(url: string, extra: string): string {
  return `${url}&${extra}`;
}

describe("upload targets of sealed files", () => {
  it("are create-only SAS URLs for one blob that expire within 30 minutes", () => {
    for (const [path, target] of targets()) {
      const url = new URL(target.url);
      assert.equal(url.searchParams.get("sp"), "c", path);
      assert.equal(url.searchParams.get("sr"), "b", path);
      const expires = Date.parse(url.searchParams.get("se") ?? "");
      assert.equal(expires, Date.parse(target.expiresAt), path);
      assert.ok(expires - Date.now() <= 30 * 60_000, path);
      assert.equal(target.method, "PUT");
      assert.deepEqual(target.headers, { "x-ms-blob-type": "BlockBlob" });
    }
  });

  it("refuse to overwrite a sealed file with Put Blob (403) and the bytes stay verified", async () => {
    for (const [path, target] of targets()) {
      const response = await putToTarget(target, Buffer.from(`overwritten ${path}`));
      assert.equal(response.status, 403, `${path}: ${await response.text()}`);
      await assertUnchanged(path);
    }
  });

  it("refuse Put Block and Put Block List on a sealed file (403)", async () => {
    const [path, target] = targets()[0] ?? [];
    assert.ok(path && target);
    const blockId = Buffer.from("block-000001").toString("base64");
    const block = await fetch(
      withQuery(target.url, `comp=block&blockid=${encodeURIComponent(blockId)}`),
      { method: "PUT", headers: { "x-ms-version": VERSION }, body: "replacement" },
    );
    assert.equal(block.status, 403, await block.text());
    const commit = await fetch(withQuery(target.url, "comp=blocklist"), {
      method: "PUT",
      headers: { "x-ms-version": VERSION, "content-type": "application/xml" },
      body: `<?xml version="1.0" encoding="utf-8"?><BlockList><Latest>${blockId}</Latest></BlockList>`,
    });
    assert.equal(commit.status, 403, await commit.text());
    await assertUnchanged(path);
  });

  it("refuse to delete a sealed file (403) and the blob still exists", async () => {
    for (const [path, target] of targets()) {
      const response = await fetch(target.url, {
        method: "DELETE",
        headers: { "x-ms-version": VERSION, "x-ms-delete-snapshots": "include" },
      });
      assert.equal(response.status, 403, `${path}: ${await response.text()}`);
      await assertUnchanged(path);
    }
  });

  it("refuse metadata and property changes and reads (write-only, 403)", async () => {
    const [path, target] = targets()[0] ?? [];
    assert.ok(path && target);
    const metadata = await fetch(withQuery(target.url, "comp=metadata"), {
      method: "PUT",
      headers: { "x-ms-version": VERSION, "x-ms-meta-tampered": "yes" },
    });
    assert.equal(metadata.status, 403);
    const properties = await fetch(withQuery(target.url, "comp=properties"), {
      method: "PUT",
      headers: { "x-ms-version": VERSION, "x-ms-blob-content-type": "text/plain" },
    });
    assert.equal(properties.status, 403);
    const read = await fetch(target.url, { headers: { "x-ms-version": VERSION } });
    assert.equal(read.status, 403);
    await assertUnchanged(path);
  });

  it("cannot be re-pointed at another blob of the package (signature binds the blob)", async () => {
    const [[fromPath, target], [toPath]] = targets() as [
      [string, UploadTargetView],
      [string, UploadTargetView],
    ];
    const url = new URL(target.url);
    const encodedFrom = firstBlobName(pkg.packageId, fromPath)
      .split("/")
      .map(encodeURIComponent)
      .join("/");
    const encodedTo = firstBlobName(pkg.packageId, toPath)
      .split("/")
      .map(encodeURIComponent)
      .join("/");
    assert.ok(url.pathname.endsWith(encodedFrom), url.pathname);
    url.pathname = url.pathname.slice(0, -encodedFrom.length) + encodedTo;
    const response = await putToTarget({ ...target, url: url.toString() }, Buffer.from("x"));
    assert.equal(response.status, 403);
    await assertUnchanged(toPath);
  });
});

describe("station routes after sealing", () => {
  it("issue no upload target for any sealed file when the session is reopened", async () => {
    const response = await station.openSession(pkg);
    assert.equal(response.statusCode, 200, response.body);
    const session = response.json() as UploadSessionView;
    assert.equal(session.status, "checks_queued");
    assert.equal(session.files.length, pkg.session.files.length);
    for (const file of session.files) {
      assert.equal(file.status, "verified", file.path);
      assert.equal(file.upload, undefined, `${file.path} must not get a target`);
    }
  });

  it("refuse file reports after sealing (409 package_sealed)", async () => {
    const path = pkg.session.files[0]?.path ?? "";
    const response = await station.complete(pkg.packageId, path);
    assert.equal(response.statusCode, 409, response.body);
    assert.equal((response.json() as { code: string }).code, "package_sealed");
  });

  it("expose no route that overwrites or deletes package files", async () => {
    const writes = station.app.routeAccess.filter(
      (access) =>
        access.url.startsWith("/v1/packages") && /\b(PUT|DELETE|PATCH)\b/.test(access.method),
    );
    assert.deepEqual(writes, []);
    const path = encodeURIComponent(pkg.session.files[0]?.path ?? "");
    for (const [method, url] of [
      ["DELETE", `/v1/packages/${pkg.packageId}`],
      ["PUT", `/v1/packages/${pkg.packageId}`],
      ["DELETE", `/v1/packages/${pkg.packageId}/files/${path}`],
      ["PUT", `/v1/packages/${pkg.packageId}/files/${path}`],
    ] as const) {
      const response = await station.inject(method, url, undefined, ["admin"]);
      assert.equal(response.statusCode, 404, `${method} ${url}`);
    }
    for (const file of pkg.session.files) {
      await assertUnchanged(file.path);
    }
  });

  it("never replaces the stored manifest", async () => {
    const name = manifestBlobName(pkg.packageId, pkg.visitId);
    await assert.rejects(
      station.storage.createOnce(name, Buffer.from("{}"), "application/json"),
      BlobExistsError,
    );
    assert.equal(
      await station.storage.createOnce(name, pkg.manifestBytes, "application/json"),
      "identical",
    );
    const stored = await station.storage.read(name, 1024 * 1024);
    assert.equal(stored?.sha256, sha256(pkg.manifestBytes));
  });

  it("keep the registry rows of verified files frozen (database trigger)", async () => {
    const path = pkg.session.files[0]?.path ?? "";
    await assert.rejects(
      station.db.query(
        "UPDATE package_files SET blob_name = 'elsewhere' WHERE package_id = $1 AND path = $2",
        [pkg.packageId, path],
      ),
      /verified and immutable/,
    );
  });
});

describe("a verified file before sealing", () => {
  it("gets no new target and its first target cannot overwrite it", async () => {
    const other = makePackage();
    const opened = await station.openSession(other);
    assert.equal(opened.statusCode, 201, opened.body);
    const session = opened.json() as UploadSessionView;
    const file = session.files[0];
    assert.ok(file?.upload);
    const bytes = other.files.get(file.path) ?? Buffer.alloc(0);
    assert.equal((await putToTarget(file.upload, bytes)).status, 201);
    const check = await station.complete(other.packageId, file.path);
    assert.equal((check.json() as { status: string }).status, "verified");

    const overwrite = await putToTarget(file.upload, Buffer.from("replacement"));
    assert.equal(overwrite.status, 403);
    const resumed = (await station.openSession(other)).json() as UploadSessionView;
    const again = resumed.files.find((entry) => entry.path === file.path);
    assert.equal(again?.status, "verified");
    assert.equal(again?.upload, undefined);
    const digest = await station.storage.digest(firstBlobName(other.packageId, file.path));
    assert.equal(digest?.sha256, sha256(bytes));
  });
});

describe("limits of the local proof (Azurite)", () => {
  it("documents that Azurite does not emulate container immutability for account-key clients", async () => {
    // Not a station path: the station never overwrites, and in Azure it has no account key and
    // the container's immutability policy blocks this for every identity.
    const connectionString = station.config.storage.connectionString;
    assert.ok(connectionString);
    const container = BlobServiceClient.fromConnectionString(connectionString).getContainerClient(
      station.config.storage.originalsContainer,
    );
    const probe = container.getBlockBlobClient(`azurite-probe/${pkg.packageId}`);
    await probe.upload("first", 5);
    await probe.upload("second", 6);
    assert.equal((await probe.downloadToBuffer()).toString(), "second");
    await probe.delete();
  });
});

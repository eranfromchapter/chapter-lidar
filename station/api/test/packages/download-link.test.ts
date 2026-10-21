// Signed download links (src/routes/packages/download.ts) through the real route
// GET /v1/packages/{packageId}/files/download (OpenAPI getFileDownloadLink): read-only, one
// blob, 10 minutes, bim/admin only, verified files only, the blob the file was verified in
// (package_files.blob_name, also a retry blob), audited without the URL. Signed links are
// exercised against a disposable Azurite container (it checks SAS signatures and permissions)
// and a migrated throwaway Postgres.
//
// A test-only route with wider roles shows issueDownloadLink checks the role itself.

import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";
import type { UserDelegationKey } from "@azure/storage-blob";
import type { FastifyInstance } from "fastify";
import {
  CLOCK_SKEW_MS,
  DOWNLOAD_LINK_TTL_MS,
  accountNameFromUrl,
  attachmentDisposition,
  createReadLinkSigner,
  issueDownloadLink,
  readLinkSignerFromConfig,
  type ReadLinkSigner,
} from "../../src/routes/packages/download.js";
import { testConfig } from "../core/helpers.js";
import { ORIGINALS_CONTAINER as CONTAINER, startAzurite, type TestAzurite } from "./azurite.js";
import { createHash } from "node:crypto";
import { manifestPath } from "../../src/storage/originals.js";
import {
  PACKAGE_ID,
  PLAN_DXF_PATH,
  QUEUED_ID,
  QUEUED_VISIT_ID,
  REVISION_2_ID,
  UNKNOWN_ID,
  MANIFEST,
  VISIT_ID,
  manifestText,
  seedRegistry,
  seedRetriedFile,
  startStation,
  type RetriedFile,
  type TestStation,
} from "./support.js";

const LINK_ROUTE = "/v1/packages/:packageId/files/download";
const CAPTURE_LINK_ROUTE = "/v1/test-only/capture/packages/:packageId/download";

let azurite: TestAzurite;
let connectionString: string;
let blobPort: number;
let station: TestStation;
let signer: ReadLinkSigner;
let retried: RetriedFile;

const BLOB_BODY = "0\nSECTION\n2\nENTITIES\n0\nENDSEC\n0\nEOF\n";
const OTHER_BODY = "other file";

function linkRoutes(app: FastifyInstance): void {
  // Wider route roles than the real route, to show issueDownloadLink checks the role itself.
  app.get(
    CAPTURE_LINK_ROUTE,
    { config: { roles: ["capture", "bim", "admin"] } },
    async (request: { params: unknown; query: unknown }) => {
      const { packageId } = request.params as { packageId: string };
      const { path } = request.query as { path: string };
      return issueDownloadLink(request as never, packageId, path);
    },
  );
}

before(async () => {
  azurite = await startAzurite();
  ({ connectionString, blobPort } = azurite);
  await azurite.put(`${PACKAGE_ID}/${PLAN_DXF_PATH}`, BLOB_BODY);
  const otherPath = MANIFEST.files.find((f) => f.role === "rooms_csv")!.path;
  await azurite.put(`${PACKAGE_ID}/${otherPath}`, OTHER_BODY);

  signer = readLinkSignerFromConfig(
    testConfig({ AZURE_STORAGE_CONNECTION_STRING: connectionString }),
  );
  station = await startStation({ services: { downloadLinks: signer }, routes: linkRoutes });
  await seedRegistry(station.db);
  retried = await seedRetriedFile(station.db);
  await azurite.put(retried.rejectedBlobName, retried.rejectedBody);
  await azurite.put(retried.blobName, retried.body);
  await azurite.put(`${PACKAGE_ID}/${manifestPath(VISIT_ID)}`, manifestText(MANIFEST));
});

after(async () => {
  await station?.close();
  azurite?.stop();
});

async function requestLink(
  path: string,
  roles: ("capture" | "bim" | "admin")[] = ["bim"],
  route = LINK_ROUTE,
  packageId = PACKAGE_ID,
) {
  return station.app.inject({
    method: "GET",
    url: route.replace(":packageId", packageId),
    query: { path },
    headers: await station.auth(roles),
  });
}

describe("download links for bim and admin", () => {
  it("returns a read-only link to the verified blob that expires in 10 minutes", async () => {
    const started = Date.now();
    const response = await requestLink(PLAN_DXF_PATH);
    assert.equal(response.statusCode, 200, response.body);
    const link = response.json() as {
      path: string;
      sha256: string;
      bytes: number;
      url: string;
      expiresAt: string;
    };
    assert.deepEqual(Object.keys(link).sort(), ["bytes", "expiresAt", "path", "sha256", "url"]);
    assert.equal(link.path, PLAN_DXF_PATH);
    const declared = MANIFEST.files.find((f) => f.path === PLAN_DXF_PATH)!;
    assert.equal(link.sha256, declared.sha256);
    assert.equal(link.bytes, declared.bytes);
    const expires = Date.parse(link.expiresAt);
    assert.ok(expires <= started + DOWNLOAD_LINK_TTL_MS + 1000);
    assert.ok(expires >= started + DOWNLOAD_LINK_TTL_MS - 2000);

    const url = new URL(link.url);
    assert.equal(url.searchParams.get("sp"), "r");
    assert.equal(url.searchParams.get("sr"), "b");
    const st = Date.parse(url.searchParams.get("st") ?? "");
    const se = Date.parse(url.searchParams.get("se") ?? "");
    assert.equal(se - st, DOWNLOAD_LINK_TTL_MS + CLOCK_SKEW_MS);

    const download = await fetch(link.url);
    assert.equal(download.status, 200);
    assert.equal(await download.text(), BLOB_BODY);
    assert.equal(download.headers.get("content-disposition"), attachmentDisposition("plan.dxf"));
  });

  it("signs the blob the file was verified in (package_files.blob_name), not one built from the path", async () => {
    const response = await requestLink(retried.path, ["bim"], LINK_ROUTE, retried.packageId);
    assert.equal(response.statusCode, 200, response.body);
    const link = response.json() as { path: string; sha256: string; bytes: number; url: string };
    assert.equal(link.path, retried.path);
    assert.equal(link.sha256, retried.sha256);
    assert.equal(link.bytes, retried.bytes);
    const url = new URL(link.url);
    assert.ok(
      decodeURIComponent(url.pathname).endsWith(`/${CONTAINER}/${retried.blobName}`),
      url.pathname,
    );
    const download = await fetch(link.url);
    assert.equal(download.status, 200);
    assert.equal(await download.text(), retried.body);
  });

  it("cannot write, delete or read another blob with the link", async () => {
    const response = await requestLink(PLAN_DXF_PATH, ["admin"]);
    const { url } = response.json() as { url: string };

    const put = await fetch(url, {
      method: "PUT",
      headers: { "x-ms-blob-type": "BlockBlob", "content-type": "text/plain" },
      body: "overwritten",
    });
    assert.equal(put.status, 403);
    const del = await fetch(url, { method: "DELETE" });
    assert.equal(del.status, 403);

    const other = new URL(url);
    other.pathname = other.pathname.replace(/plan\.dxf$/, "rooms.csv");
    assert.equal((await fetch(other)).status, 403);

    const still = await fetch(url);
    assert.equal(await still.text(), BLOB_BODY);
  });

  it("is rejected by storage once expired", async () => {
    const past = readLinkSignerFromConfig(
      testConfig({ AZURE_STORAGE_CONNECTION_STRING: connectionString }),
    );
    const expired = createReadLinkSigner({
      kind: "shared-key",
      containerName: CONTAINER,
      serviceUrl: azurite.service.url,
      credential: azurite.service.credential as never,
      now: () => Date.now() - DOWNLOAD_LINK_TTL_MS - 60_000,
    });
    const fresh = await past.signRead(`${PACKAGE_ID}/${PLAN_DXF_PATH}`);
    assert.equal((await fetch(fresh.url)).status, 200);
    const stale = await expired.signRead(`${PACKAGE_ID}/${PLAN_DXF_PATH}`);
    assert.equal((await fetch(stale.url)).status, 403);
  });

  it("audits every link without the URL or signature", async () => {
    const response = await requestLink(PLAN_DXF_PATH);
    const { url, expiresAt } = response.json() as { url: string; expiresAt: string };
    const signature = new URL(url).searchParams.get("sig") ?? "";
    assert.ok(signature.length > 0);
    const rows = await station.db.query<{
      action: string;
      target_type: string;
      target_id: string;
      details: Record<string, unknown>;
    }>(
      `SELECT action, target_type, target_id, details FROM audit_log
        WHERE action = 'package_file.download_link' ORDER BY audit_id DESC LIMIT 1`,
    );
    assert.deepEqual(rows.rows[0], {
      action: "package_file.download_link",
      target_type: "package",
      target_id: PACKAGE_ID,
      details: { path: PLAN_DXF_PATH, role: "plan_dxf", expiresAt },
    });
    const all = await station.db.query("SELECT details::text AS d FROM audit_log");
    assert.ok(!all.rows.some((row) => String(row.d).includes(signature)));
    assert.ok(!station.logs.some((line) => line.includes(signature)), "signature in logs");
  });
});

describe("download links of the sealed manifest", () => {
  it("links the stored manifest once sealed, with its fingerprint, audited as role manifest", async () => {
    const path = manifestPath(VISIT_ID);
    const response = await requestLink(path, ["admin"]);
    assert.equal(response.statusCode, 200, response.body);
    const link = response.json() as { path: string; sha256: string; bytes: number; url: string };
    const text = manifestText(MANIFEST);
    assert.equal(link.path, path);
    assert.equal(link.sha256, createHash("sha256").update(text).digest("hex"));
    assert.equal(link.bytes, Buffer.byteLength(text));
    assert.equal(await (await fetch(link.url)).text(), text);
    const rows = await station.db.query<{ details: Record<string, unknown> }>(
      `SELECT details FROM audit_log WHERE action = 'package_file.download_link'
        ORDER BY audit_id DESC LIMIT 1`,
    );
    assert.equal(rows.rows[0]?.details.role, "manifest");
    assert.equal(rows.rows[0]?.details.path, path);
  });

  it("answers 404 before the seal, before the size is recorded, and for another visit's path", async () => {
    for (const [packageId, path] of [
      [REVISION_2_ID, manifestPath(VISIT_ID)],
      [QUEUED_ID, manifestPath(QUEUED_VISIT_ID)],
      [PACKAGE_ID, manifestPath(QUEUED_VISIT_ID)],
    ] as const) {
      const response = await requestLink(path, ["bim"], LINK_ROUTE, packageId);
      assert.equal(response.statusCode, 404, `${packageId} ${path}`);
      assert.equal((response.json() as { code: string }).code, "not_found");
    }
  });
});

describe("download links are refused", () => {
  it("for the capture role, by the route and by issueDownloadLink itself", async () => {
    const viaRoute = await requestLink(PLAN_DXF_PATH, ["capture"]);
    assert.equal(viaRoute.statusCode, 403);
    const viaHelper = await requestLink(PLAN_DXF_PATH, ["capture"], CAPTURE_LINK_ROUTE);
    assert.equal(viaHelper.statusCode, 403);
    assert.equal((viaHelper.json() as { code: string }).code, "forbidden");
  });

  it("for a file that is not verified", async () => {
    const pending = MANIFEST.files[0]!.path;
    const response = await requestLink(pending, ["bim"], LINK_ROUTE, REVISION_2_ID);
    assert.equal(response.statusCode, 409);
    assert.equal((response.json() as { code: string }).code, "file_not_verified");
  });

  it("for an unknown file or package", async () => {
    for (const [packageId, path] of [
      [PACKAGE_ID, "Original Exports/none.dxf"],
      [UNKNOWN_ID, PLAN_DXF_PATH],
      ["not-a-uuid", PLAN_DXF_PATH],
    ] as const) {
      const response = await requestLink(path, ["bim"], LINK_ROUTE, packageId);
      assert.equal(response.statusCode, 404, `${packageId} ${path}`);
    }
  });
});

describe("signer configuration", () => {
  it("needs storage settings and an account key in the connection string", () => {
    assert.throws(() => readLinkSignerFromConfig(testConfig()), /AZURE_STORAGE_ACCOUNT_URL or/);
    assert.throws(
      () =>
        readLinkSignerFromConfig(
          testConfig({
            AZURE_STORAGE_CONNECTION_STRING:
              "BlobEndpoint=https://acct.blob.core.windows.net/;SharedAccessSignature=sv=2024-01-01&sig=abc",
          }),
        ),
      /must carry an account key/,
    );
  });

  it("hands out links on the public blob endpoint when one is configured", async () => {
    const local = readLinkSignerFromConfig(
      testConfig({
        AZURE_STORAGE_CONNECTION_STRING: connectionString.replace("127.0.0.1", "azurite"),
        STORAGE_PUBLIC_BLOB_ENDPOINT: `http://localhost:${blobPort}/devstoreaccount1`,
      }),
    );
    const link = await local.signRead(`${PACKAGE_ID}/${PLAN_DXF_PATH}`);
    assert.ok(link.url.startsWith(`http://localhost:${blobPort}/devstoreaccount1/originals/`));
    assert.equal((await fetch(link.url)).status, 200);
  });

  it("signs with a cached user delegation key in Azure, https only", async () => {
    let now = Date.parse("2026-10-17T15:00:00Z");
    const requested: [Date, Date][] = [];
    const signerWithKey = createReadLinkSigner({
      kind: "user-delegation",
      containerName: CONTAINER,
      serviceUrl: "https://chapterstation.blob.core.windows.net/",
      accountName: accountNameFromUrl("https://chapterstation.blob.core.windows.net/"),
      now: () => now,
      getDelegationKey: async (startsOn, expiresOn): Promise<UserDelegationKey> => {
        requested.push([startsOn, expiresOn]);
        return {
          signedObjectId: "0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d",
          signedTenantId: "4f1c2b8a-1d2e-4c3b-9a8f-0123456789ab",
          signedStartsOn: startsOn,
          signedExpiresOn: expiresOn,
          signedService: "b",
          signedVersion: "2025-01-05",
          value: Buffer.from("k".repeat(32)).toString("base64"),
        };
      },
    });
    const first = new URL((await signerWithKey.signRead("p/a b/c.dxf")).url);
    assert.equal(first.origin, "https://chapterstation.blob.core.windows.net");
    assert.equal(first.pathname, "/originals/p/a%20b/c.dxf");
    assert.equal(first.searchParams.get("sp"), "r");
    assert.equal(first.searchParams.get("spr"), "https");
    assert.equal(first.searchParams.get("skoid"), "0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d");
    assert.equal(requested.length, 1);

    now += 30 * 60_000;
    await signerWithKey.signRead("p/x.dxf");
    assert.equal(requested.length, 1, "key reused while it outlives the link");

    now += 25 * 60_000;
    await signerWithKey.signRead("p/x.dxf");
    assert.equal(requested.length, 2, "key refreshed before the link would outlive it");
  });

  it("reads the account name from the account URL", () => {
    assert.equal(
      accountNameFromUrl("https://chapterstation.blob.core.windows.net"),
      "chapterstation",
    );
    assert.equal(accountNameFromUrl("http://127.0.0.1:10000/devstoreaccount1"), "devstoreaccount1");
  });
});

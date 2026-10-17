// F7 AC3: a file whose uploaded bytes do not match the declared sha256 is rejected and the
// package cannot be sealed.
//
// Runs against a real Postgres and Azurite (see support/infra.ts); the station hashes the blob it
// stored, never anything the client reports.

import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";
import { firstBlobName } from "../../src/storage/originals.js";
import { makePackage, sha256, type TestPackage } from "./support/package.js";
import {
  putToTarget,
  startUploadStation,
  uploadAll,
  type FileCheckView,
  type UploadSessionView,
  type UploadStation,
} from "./support/station.js";

let station: UploadStation;

before(async () => {
  station = await startUploadStation();
});

after(async () => {
  await station?.close();
});

function flipLastByte(data: Buffer): Buffer {
  const copy = Buffer.from(data);
  const last = copy.length - 1;
  copy[last] = (copy[last] ?? 0) ^ 0xff;
  return copy;
}

async function packageState(packageId: string) {
  const pkg = await station.db.query<{ status: string; manifest: unknown }>(
    "SELECT status, manifest FROM packages WHERE package_id = $1",
    [packageId],
  );
  const jobs = await station.db.query<{ n: number }>(
    "SELECT count(*) AS n FROM jobs WHERE package_id = $1",
    [packageId],
  );
  return { row: pkg.rows[0], jobs: jobs.rows[0]?.n };
}

describe("server-side sha256 verification", () => {
  let pkg: TestPackage;
  let session: UploadSessionView;
  let results: Map<string, FileCheckView>;
  let samePath: string;
  let shortPath: string;
  let missingPath: string;

  before(async () => {
    pkg = makePackage();
    const opened = await station.openSession(pkg);
    assert.equal(opened.statusCode, 201, opened.body);
    session = opened.json() as UploadSessionView;

    const paths = pkg.session.files.map((file) => file.path);
    samePath = paths.find((path) => path.endsWith("points.las")) ?? "";
    shortPath = paths.find((path) => path.endsWith("plan.png")) ?? "";
    missingPath = paths.find((path) => path.endsWith("rooms.csv")) ?? "";
    assert.ok(samePath && shortPath && missingPath);

    const sameLength = flipLastByte(pkg.files.get(samePath) ?? Buffer.alloc(0));
    const shorter = (pkg.files.get(shortPath) ?? Buffer.alloc(0)).subarray(1);
    results = await uploadAll(
      station,
      pkg,
      session,
      new Map<string, Buffer | null>([
        [samePath, sameLength],
        [shortPath, shorter],
        [missingPath, null],
      ]),
    );
  });

  it("rejects bytes of the declared size but another sha256 as sha256_mismatch", () => {
    const result = results.get(samePath);
    const declared = pkg.session.files.find((file) => file.path === samePath);
    assert.ok(result && declared);
    assert.equal(result.status, "sha256_mismatch");
    assert.equal(result.expectedSha256, declared.sha256);
    assert.equal(result.expectedBytes, declared.bytes);
    assert.equal(result.actualBytes, declared.bytes);
    assert.equal(
      result.actualSha256,
      sha256(flipLastByte(pkg.files.get(samePath) ?? Buffer.alloc(0))),
    );
    assert.notEqual(result.actualSha256, declared.sha256);
    assert.match(result.checkedAt, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/);
  });

  it("rejects bytes of another size as bytes_mismatch", () => {
    const result = results.get(shortPath);
    const declared = pkg.session.files.find((file) => file.path === shortPath);
    assert.ok(result && declared);
    assert.equal(result.status, "bytes_mismatch");
    assert.equal(result.actualBytes, declared.bytes - 1);
    assert.notEqual(result.actualSha256, declared.sha256);
  });

  it("reports a file that was never uploaded as not_uploaded, without actual values", () => {
    const result = results.get(missingPath);
    assert.ok(result);
    assert.equal(result.status, "not_uploaded");
    assert.equal(result.actualSha256, undefined);
    assert.equal(result.actualBytes, undefined);
  });

  it("verifies every file whose stored bytes match", () => {
    for (const [path, result] of results) {
      if (path !== samePath && path !== shortPath && path !== missingPath) {
        assert.equal(result.status, "verified", path);
        assert.equal(result.actualSha256, result.expectedSha256, path);
      }
    }
  });

  it("records the rejected check in the registry and the audit log", async () => {
    const file = await station.db.query<{
      status: string;
      actual_sha256: string;
      verified_at: Date | null;
    }>(
      "SELECT status, actual_sha256, verified_at FROM package_files WHERE package_id = $1 AND path = $2",
      [pkg.packageId, samePath],
    );
    assert.equal(file.rows[0]?.status, "sha256_mismatch");
    assert.equal(file.rows[0]?.verified_at, null);
    const audits = await station.db.query<{
      action: string;
      details: { path: string; status: string };
    }>(
      "SELECT action, details FROM audit_log WHERE target_type = 'package' AND target_id = $1 AND action = 'file.reject'",
      [pkg.packageId],
    );
    const rejected = audits.rows.map((row) => `${row.details.path}:${row.details.status}`).sort();
    assert.deepEqual(
      rejected,
      [
        `${missingPath}:not_uploaded`,
        `${samePath}:sha256_mismatch`,
        `${shortPath}:bytes_mismatch`,
      ].sort(),
    );
  });

  it("refuses to seal: 409 files_not_verified naming each rejected file; no job, still uploading", async () => {
    const response = await station.seal(pkg.packageId, pkg.manifestBytes);
    assert.equal(response.statusCode, 409, response.body);
    const problem = response.json() as {
      code: string;
      errors: { pointer: string; message: string }[];
    };
    assert.equal(problem.code, "files_not_verified");
    const indexOf = (path: string) => pkg.manifest.files.findIndex((entry) => entry.path === path);
    assert.deepEqual(
      problem.errors.map((error) => error.pointer).sort(),
      [samePath, shortPath, missingPath].map((path) => `/files/${indexOf(path)}`).sort(),
    );
    const state = await packageState(pkg.packageId);
    assert.equal(state.row?.status, "uploading");
    assert.equal(state.row?.manifest, null);
    assert.equal(state.jobs, 0);
  });

  it("refuses a manifest that declares the tampered bytes' sha256 instead (422, not sealed)", async () => {
    const tampered = structuredClone(pkg.manifest);
    const entry = tampered.files.find((file) => file.path === samePath);
    assert.ok(entry);
    entry.sha256 = results.get(samePath)?.actualSha256 ?? "";
    const response = await station.seal(pkg.packageId, Buffer.from(JSON.stringify(tampered)));
    assert.equal(response.statusCode, 422, response.body);
    assert.equal((response.json() as { code: string }).code, "manifest_mismatch");
    assert.equal((await packageState(pkg.packageId)).row?.status, "uploading");
  });

  it("re-checking the same stored bytes gives the same rejection", async () => {
    const response = await station.complete(pkg.packageId, samePath);
    assert.equal(response.statusCode, 200, response.body);
    assert.equal((response.json() as FileCheckView).status, "sha256_mismatch");
  });

  it("issues a fresh target on a new blob for rejected files only; correct bytes then verify and the package seals", async () => {
    const resumed = await station.openSession(pkg);
    assert.equal(resumed.statusCode, 200, resumed.body);
    const again = resumed.json() as UploadSessionView;
    const withTargets = again.files
      .filter((file) => file.upload !== undefined)
      .map((file) => file.path);
    assert.deepEqual(withTargets.sort(), [samePath, shortPath, missingPath].sort());
    // A mismatched file starts a new attempt (pending); a missing upload keeps its target.
    for (const file of again.files) {
      const expected =
        file.upload === undefined
          ? "verified"
          : file.path === missingPath
            ? "not_uploaded"
            : "pending";
      assert.equal(file.status, expected, file.path);
    }

    // The rejected blob stays where it was (originals are immutable); the retry is a new blob.
    const target = again.files.find((file) => file.path === samePath)?.upload;
    assert.ok(target);
    const firstUrl = session.files.find((file) => file.path === samePath)?.upload?.url ?? "";
    assert.notEqual(new URL(target.url).pathname, new URL(firstUrl).pathname);
    const rows = await station.db.query<{ path: string; blob_name: string }>(
      "SELECT path, blob_name FROM package_files WHERE package_id = $1 AND path = ANY($2::text[])",
      [pkg.packageId, [samePath, shortPath, missingPath]],
    );
    const names = new Map(rows.rows.map((row) => [row.path, row.blob_name]));
    assert.equal(names.get(samePath), `${pkg.packageId}.retry-2/${samePath}`);
    assert.equal(names.get(shortPath), `${pkg.packageId}.retry-2/${shortPath}`);
    assert.equal(names.get(missingPath), firstBlobName(pkg.packageId, missingPath));
    const kept = await station.storage.digest(firstBlobName(pkg.packageId, samePath));
    assert.equal(kept?.sha256, results.get(samePath)?.actualSha256);

    const retried = await uploadAll(station, pkg, again);
    for (const [path, result] of retried) {
      assert.equal(result.status, "verified", path);
    }
    const sealed = await station.seal(pkg.packageId, pkg.manifestBytes);
    assert.equal(sealed.statusCode, 202, sealed.body);
    assert.equal((await packageState(pkg.packageId)).row?.status, "checks_queued");
  });
});

describe("a rejected upload cannot be fixed by overwriting it", () => {
  it("the first target cannot overwrite the mismatched blob", async () => {
    const pkg = makePackage();
    const opened = await station.openSession(pkg);
    assert.equal(opened.statusCode, 201, opened.body);
    const session = opened.json() as UploadSessionView;
    const file = session.files[0];
    assert.ok(file?.upload);
    const good = pkg.files.get(file.path) ?? Buffer.alloc(0);

    assert.equal((await putToTarget(file.upload, flipLastByte(good))).status, 201);
    const check = await station.complete(pkg.packageId, file.path);
    assert.equal((check.json() as FileCheckView).status, "sha256_mismatch");

    const overwrite = await putToTarget(file.upload, good);
    assert.equal(overwrite.status, 403, "a create-only target must not overwrite an existing blob");
    const recheck = await station.complete(pkg.packageId, file.path);
    assert.equal((recheck.json() as FileCheckView).status, "sha256_mismatch");
  });
});

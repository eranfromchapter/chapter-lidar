// F7 AC4: sealing a complete package sets checks_queued and creates exactly one job.
//
// Runs against a real Postgres and Azurite (see support/infra.ts).

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { after, before, describe, it } from "node:test";
import { manifestBlobName } from "../../src/storage/originals.js";
import { FIXTURE_ROOT, makePackage, sha256, type TestPackage } from "./support/package.js";
import {
  startUploadStation,
  uploadAll,
  uploadVerifiedPackage,
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

interface JobRow {
  job_id: string;
  type: string;
  status: string;
  attempts: number;
}

async function jobsOf(packageId: string): Promise<JobRow[]> {
  const result = await station.db.query<JobRow>(
    "SELECT job_id, type, status, attempts FROM jobs WHERE package_id = $1",
    [packageId],
  );
  return result.rows;
}

interface PackageBody {
  packageId: string;
  status: string;
  sealedAt?: string;
  files: { path: string; status: string; checkedAt?: string }[];
  manifest?: unknown;
  captureRecord?: { visitId: string };
}

describe("sealing a complete package", () => {
  let pkg: TestPackage;
  let firstJobId: string | undefined;

  before(async () => {
    pkg = makePackage();
    await uploadVerifiedPackage(station, pkg);
  });

  it("answers 202 with the package in checks_queued, its manifest and capture record", async () => {
    const response = await station.seal(pkg.packageId, pkg.manifestBytes);
    assert.equal(response.statusCode, 202, response.body);
    const body = response.json() as PackageBody;
    assert.equal(body.packageId, pkg.packageId);
    assert.equal(body.status, "checks_queued");
    assert.equal(body.sealedAt, pkg.manifest.sealedAt);
    assert.deepEqual(body.manifest, pkg.manifest);
    assert.equal(body.captureRecord?.visitId, pkg.visitId);
    assert.deepEqual(
      body.files.map((file) => file.path),
      pkg.manifest.files.map((file) => file.path),
    );
    assert.ok(body.files.every((file) => file.status === "verified" && file.checkedAt));
  });

  it("creates exactly one queued checks job", async () => {
    const jobs = await jobsOf(pkg.packageId);
    assert.equal(jobs.length, 1);
    assert.equal(jobs[0]?.type, "checks");
    assert.equal(jobs[0]?.status, "queued");
    assert.equal(jobs[0]?.attempts, 0);
    firstJobId = jobs[0]?.job_id;
  });

  it("registers the manifest, its sha256 and the capture record in the registry", async () => {
    const result = await station.db.query<{
      status: string;
      manifest: unknown;
      manifest_sha256: string;
      sealed_at: Date;
      registered_at: Date | null;
      capture_record: unknown;
    }>(
      `SELECT status, manifest, manifest_sha256, sealed_at, registered_at, capture_record
         FROM packages WHERE package_id = $1`,
      [pkg.packageId],
    );
    const row = result.rows[0];
    assert.ok(row);
    assert.equal(row.status, "checks_queued");
    assert.deepEqual(row.manifest, pkg.manifest);
    assert.equal(row.manifest_sha256, sha256(pkg.manifestBytes));
    assert.equal(row.sealed_at.toISOString(), pkg.manifest.sealedAt.replace("Z", ".000Z"));
    assert.ok(row.registered_at instanceof Date);
    const recordPath =
      pkg.manifest.files.find((file) => file.role === "capture_record")?.path ?? "";
    assert.deepEqual(row.capture_record, JSON.parse(pkg.files.get(recordPath)?.toString() ?? ""));
  });

  it("stores the manifest byte for byte as Source Register/{visitId}/manifest.json", async () => {
    const blob = await station.storage.read(
      manifestBlobName(pkg.packageId, pkg.visitId),
      1024 * 1024,
    );
    assert.ok(blob);
    assert.equal(
      manifestBlobName(pkg.packageId, pkg.visitId),
      `${pkg.packageId}/Source Register/${pkg.visitId}/manifest.json`,
    );
    assert.ok(blob.data.equals(pkg.manifestBytes));
  });

  it("audits the seal with the job id", async () => {
    const result = await station.db.query<{
      actor_id: string;
      details: { jobId: string; manifestSha256: string };
    }>("SELECT actor_id, details FROM audit_log WHERE action = 'package.seal' AND target_id = $1", [
      pkg.packageId,
    ]);
    assert.equal(result.rows.length, 1);
    assert.equal(result.rows[0]?.details.jobId, firstJobId);
    assert.equal(result.rows[0]?.details.manifestSha256, sha256(pkg.manifestBytes));
  });

  it("is idempotent: the same manifest again answers 200 and creates no second job", async () => {
    const reformatted = Buffer.from(JSON.stringify(pkg.manifest));
    for (const bytes of [pkg.manifestBytes, reformatted]) {
      const response = await station.seal(pkg.packageId, bytes);
      assert.equal(response.statusCode, 200, response.body);
      assert.equal((response.json() as PackageBody).status, "checks_queued");
    }
    const jobs = await jobsOf(pkg.packageId);
    assert.deepEqual(
      jobs.map((job) => job.job_id),
      [firstJobId],
    );
  });

  it("refuses a different manifest for the sealed package (409) and keeps the first", async () => {
    const other = structuredClone(pkg.manifest);
    other.sealedAt = "2026-10-17T15:11:00Z";
    const response = await station.seal(pkg.packageId, Buffer.from(JSON.stringify(other)));
    assert.equal(response.statusCode, 409, response.body);
    assert.equal((response.json() as { code: string }).code, "package_sealed");
    assert.equal((await jobsOf(pkg.packageId)).length, 1);
  });
});

describe("concurrent seals", () => {
  it("create exactly one job: one 202, every other request 200", async () => {
    const pkg = makePackage();
    await uploadVerifiedPackage(station, pkg);
    const responses = await Promise.all(
      Array.from({ length: 6 }, () => station.seal(pkg.packageId, pkg.manifestBytes)),
    );
    const codes = responses.map((response) => response.statusCode).sort();
    assert.deepEqual(
      codes,
      [200, 200, 200, 200, 200, 202],
      responses.map((r) => r.body).join("\n"),
    );
    assert.equal((await jobsOf(pkg.packageId)).length, 1);
  });
});

describe("sealing is refused unless the package is complete and consistent", () => {
  let pkg: TestPackage;
  let session: UploadSessionView;

  before(async () => {
    pkg = makePackage();
    const opened = await station.openSession(pkg);
    assert.equal(opened.statusCode, 201, opened.body);
    session = opened.json() as UploadSessionView;
  });

  async function assertNotSealed(): Promise<void> {
    const result = await station.db.query<{ status: string }>(
      "SELECT status FROM packages WHERE package_id = $1",
      [pkg.packageId],
    );
    assert.equal(result.rows[0]?.status, "uploading");
    assert.equal((await jobsOf(pkg.packageId)).length, 0);
  }

  it("409 files_not_verified before any file is uploaded", async () => {
    const response = await station.seal(pkg.packageId, pkg.manifestBytes);
    assert.equal(response.statusCode, 409, response.body);
    assert.equal((response.json() as { code: string }).code, "files_not_verified");
    await assertNotSealed();
  });

  it("422 invalid_manifest for a body that is not a contract manifest", async () => {
    const broken = { ...pkg.manifest, schemaVersion: "0.9.0" };
    const response = await station.seal(pkg.packageId, Buffer.from(JSON.stringify(broken)));
    assert.equal(response.statusCode, 422, response.body);
    const problem = response.json() as { code: string; errors: { pointer: string }[] };
    assert.equal(problem.code, "invalid_manifest");
    assert.ok(problem.errors.some((error) => error.pointer === "/schemaVersion"));
    await assertNotSealed();
  });

  it("400 for a body that is not JSON", async () => {
    const response = await station.seal(pkg.packageId, Buffer.from("{not json"));
    assert.equal(response.statusCode, 400, response.body);
    await assertNotSealed();
  });

  it("404 for an unknown package", async () => {
    const other = makePackage();
    const response = await station.seal(other.packageId, other.manifestBytes);
    assert.equal(response.statusCode, 404, response.body);
    assert.equal((response.json() as { code: string }).code, "package_not_found");
  });

  it("422 manifest_mismatch when files or identity differ from the session, even when all files are verified", async () => {
    await uploadAll(station, pkg, session);

    const missing = structuredClone(pkg.manifest);
    missing.files = missing.files.slice(1) as typeof missing.files;
    const extra = structuredClone(pkg.manifest);
    extra.files = [
      ...extra.files,
      { ...pkg.manifest.files[2]!, path: "Original Exports/floor-1/extra.json" },
    ] as typeof extra.files;
    const otherRole = structuredClone(pkg.manifest);
    otherRole.files[3]!.role = "plan_pdf";
    const otherSize = structuredClone(pkg.manifest);
    otherSize.files[4]!.bytes += 1;
    const otherPackage = { ...structuredClone(pkg.manifest), packageId: makePackage().packageId };
    const otherVisit = { ...structuredClone(pkg.manifest), visitId: makePackage().visitId };

    const cases: [string, unknown, string][] = [
      ["a declared file is missing", missing, "/files"],
      ["an undeclared file is listed", extra, `/files/${pkg.manifest.files.length}/path`],
      ["a role differs", otherRole, "/files/3/role"],
      ["a size differs", otherSize, "/files/4/bytes"],
      ["the packageId differs from the URL", otherPackage, "/packageId"],
      ["the visitId differs", otherVisit, "/visitId"],
    ];
    for (const [label, manifest, pointer] of cases) {
      const response = await station.seal(pkg.packageId, Buffer.from(JSON.stringify(manifest)));
      assert.equal(response.statusCode, 422, `${label}: ${response.body}`);
      const problem = response.json() as { code: string; errors: { pointer: string }[] };
      assert.equal(problem.code, "manifest_mismatch", label);
      assert.ok(
        problem.errors.some((error) => error.pointer === pointer),
        `${label}: ${response.body}`,
      );
    }
    await assertNotSealed();

    const sealed = await station.seal(pkg.packageId, pkg.manifestBytes);
    assert.equal(sealed.statusCode, 202, sealed.body);
    assert.equal((await jobsOf(pkg.packageId)).length, 1);
  });
});

describe("the capture record is validated at sealing", () => {
  it("422 invalid_capture_record when the verified capture record breaks its schema", async () => {
    const pkg = makePackage();
    const recordPath =
      pkg.manifest.files.find((file) => file.role === "capture_record")?.path ?? "";
    const broken = Buffer.from(JSON.stringify({ schemaVersion: "1.0.0", visitId: pkg.visitId }));
    // Declare the broken bytes so they verify; only the schema check can stop them.
    const files = new Map(pkg.files);
    files.set(recordPath, broken);
    const entry = pkg.manifest.files.find((file) => file.path === recordPath);
    const declared = pkg.session.files.find((file) => file.path === recordPath);
    assert.ok(entry && declared);
    entry.sha256 = declared.sha256 = sha256(broken);
    entry.bytes = declared.bytes = broken.length;
    const brokenPkg: TestPackage = {
      ...pkg,
      files,
      manifestBytes: Buffer.from(JSON.stringify(pkg.manifest)),
    };
    await uploadVerifiedPackage(station, brokenPkg);
    const response = await station.seal(pkg.packageId, brokenPkg.manifestBytes);
    assert.equal(response.statusCode, 422, response.body);
    assert.equal((response.json() as { code: string }).code, "invalid_capture_record");
    assert.equal((await jobsOf(pkg.packageId)).length, 0);
  });

  it("uses the fixture's own capture record unchanged apart from the visit id", () => {
    const original = JSON.parse(
      readFileSync(
        join(
          FIXTURE_ROOT,
          "Source Register/c1b6d1fb-17af-4f4a-877c-2565ef9bdb86/capture-record.json",
        ),
        "utf8",
      ),
    ) as { visitId: string };
    const pkg = makePackage();
    const recordPath =
      pkg.manifest.files.find((file) => file.role === "capture_record")?.path ?? "";
    const record = JSON.parse(pkg.files.get(recordPath)?.toString() ?? "") as { visitId: string };
    assert.deepEqual({ ...record, visitId: original.visitId }, original);
  });
});

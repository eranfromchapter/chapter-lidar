// Upload sessions (POST /packages) and file reports (POST /packages/{id}/files/complete) against
// a real Postgres and Azurite: create, idempotent resume, conflicts, contract rules, audit, and
// no SAS in logs or the audit log.

import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, before, describe, it } from "node:test";
import { makePackage, type TestPackage } from "./support/package.js";
import {
  startUploadStation,
  type UploadSessionView,
  type UploadStation,
} from "./support/station.js";

let station: UploadStation;

before(async () => {
  station = await startUploadStation({
    STORAGE_PUBLIC_BLOB_ENDPOINT: "http://localhost:10000/devstoreaccount1",
  });
});

after(async () => {
  await station?.close();
});

function problemOf(response: { json(): unknown }): {
  code: string;
  errors?: { pointer: string }[];
} {
  return response.json() as { code: string; errors?: { pointer: string }[] };
}

describe("opening an upload session", () => {
  let pkg: TestPackage;
  let first: UploadSessionView;

  before(async () => {
    pkg = makePackage();
  });

  it("answers 201 with a Location and one create-only target per declared file, in order", async () => {
    const response = await station.openSession(pkg);
    assert.equal(response.statusCode, 201, response.body);
    assert.equal(response.headers.location, `/v1/packages/${pkg.packageId}`);
    first = response.json() as UploadSessionView;
    assert.equal(first.packageId, pkg.packageId);
    assert.equal(first.visitId, pkg.visitId);
    assert.equal(first.dealId, pkg.session.dealId);
    assert.equal(first.revision, 1);
    assert.equal(first.status, "uploading");
    assert.deepEqual(
      first.files.map((file) => file.path),
      pkg.session.files.map((file) => file.path),
    );
    for (const file of first.files) {
      assert.equal(file.status, "pending");
      assert.ok(file.upload, file.path);
      const url = new URL(file.upload.url);
      assert.equal(url.searchParams.get("sp"), "c");
      assert.equal(url.searchParams.get("sr"), "b");
    }
  });

  it("hands out targets on STORAGE_PUBLIC_BLOB_ENDPOINT under <packageId>/<path>", () => {
    for (const file of first.files) {
      const url = new URL(file.upload?.url ?? "");
      assert.equal(url.origin, "http://localhost:10000");
      const expected = `/devstoreaccount1/originals/${pkg.packageId}/${file.path}`;
      assert.equal(decodeURIComponent(url.pathname), expected);
    }
  });

  it("registers the package and its files and audits the creation", async () => {
    const row = await station.db.query<{ status: string; created_by_id: string; deal_id: string }>(
      "SELECT status, created_by_id, deal_id FROM packages WHERE package_id = $1",
      [pkg.packageId],
    );
    assert.equal(row.rows[0]?.status, "uploading");
    assert.equal(row.rows[0]?.deal_id, pkg.session.dealId);
    const files = await station.db.query<{ n: number }>(
      "SELECT count(*) AS n FROM package_files WHERE package_id = $1 AND status = 'pending'",
      [pkg.packageId],
    );
    assert.equal(files.rows[0]?.n, pkg.session.files.length);
    const audits = await station.db.query<{
      actor_id: string;
      actor_roles: string[];
      details: { files: number };
    }>(
      "SELECT actor_id, actor_roles, details FROM audit_log WHERE action = 'package.create' AND target_id = $1",
      [pkg.packageId],
    );
    assert.equal(audits.rows.length, 1);
    assert.equal(audits.rows[0]?.actor_id, row.rows[0]?.created_by_id);
    assert.deepEqual(audits.rows[0]?.actor_roles, ["capture"]);
    assert.equal(audits.rows[0]?.details.files, pkg.session.files.length);
  });

  it("is idempotent: the same body answers 200 with fresh targets for the same blobs", async () => {
    const response = await station.openSession(pkg);
    assert.equal(response.statusCode, 200, response.body);
    const again = response.json() as UploadSessionView;
    assert.equal(again.status, "uploading");
    assert.equal(again.files.length, first.files.length);
    again.files.forEach((file, index) => {
      assert.equal(file.status, "pending");
      assert.equal(
        new URL(file.upload?.url ?? "").pathname,
        new URL(first.files[index]?.upload?.url ?? "").pathname,
      );
    });
    const audits = await station.db.query<{ n: number }>(
      "SELECT count(*) AS n FROM audit_log WHERE action = 'package.resume' AND target_id = $1",
      [pkg.packageId],
    );
    assert.equal(audits.rows[0]?.n, 1);
  });

  it("answers 409 package_conflict for a different body with the same packageId", async () => {
    const response = await station.inject("POST", "/v1/packages", {
      ...pkg.session,
      dealId: "another-deal",
    });
    assert.equal(response.statusCode, 409, response.body);
    assert.equal(problemOf(response).code, "package_conflict");
  });

  it("answers 409 revision_exists for another packageId with the same visit and revision", async () => {
    const response = await station.inject("POST", "/v1/packages", {
      ...pkg.session,
      packageId: randomUUID(),
    });
    assert.equal(response.statusCode, 409, response.body);
    assert.equal(problemOf(response).code, "revision_exists");
  });

  it("refuses revision 2 while the package it supersedes is still uploading (422)", async () => {
    const next = makePackage({
      visitId: pkg.visitId,
      revision: 2,
      supersedesPackageId: pkg.packageId,
    });
    const response = await station.openSession(next);
    assert.equal(response.statusCode, 422, response.body);
    assert.equal(problemOf(response).code, "supersedes_mismatch");
    assert.deepEqual(
      problemOf(response).errors?.map((error) => error.pointer),
      ["/supersedesPackageId"],
    );
  });

  it("accepts revision 2 of the visit when the station never received the package it supersedes", async () => {
    const next = makePackage({
      visitId: pkg.visitId,
      revision: 2,
      supersedesPackageId: randomUUID(),
    });
    const response = await station.openSession(next);
    assert.equal(response.statusCode, 201, response.body);
    const session = response.json() as UploadSessionView;
    assert.equal(session.revision, 2);
    assert.ok(
      session.files.every((file) => file.upload !== undefined && file.status === "pending"),
    );
  });

  it("accepts the admin role and refuses bim (403)", async () => {
    const admin = await station.openSession(makePackage(), ["admin"]);
    assert.equal(admin.statusCode, 201, admin.body);
    const bim = await station.openSession(makePackage(), ["bim"]);
    assert.equal(bim.statusCode, 403, bim.body);
  });
});

describe("contract rules of the session request", () => {
  const base = () =>
    structuredClone(makePackage().session) as unknown as Record<string, unknown> & {
      files: Record<string, unknown>[];
    };

  it("answers 422 invalid_upload_session with a pointer for each cross-field rule", async () => {
    const cases: [string, (body: ReturnType<typeof base>) => void, string][] = [
      ["revision 2 without supersedesPackageId", (b) => (b.revision = 2), "/supersedesPackageId"],
      [
        "revision 1 with supersedesPackageId",
        (b) => (b.supersedesPackageId = randomUUID()),
        "/supersedesPackageId",
      ],
      ["duplicate paths", (b) => (b.files[1]!.path = b.files[0]!.path), "/files/1/path"],
      [
        "captureId on a capture record",
        (b) => {
          b.files[0]!.captureId = randomUUID();
          b.files[0]!.areaKey = "floor-1";
        },
        "/files/0/captureId",
      ],
      [
        "a capture file without captureId",
        (b) => delete b.files[2]!.captureId,
        "/files/2/captureId",
      ],
      ["a capture file without areaKey", (b) => delete b.files[2]!.areaKey, "/files/2/areaKey"],
      [
        "the reserved manifest path",
        (b) => (b.files[0]!.path = `Source Register/${String(b.visitId)}/manifest.json`),
        "/files/0/path",
      ],
    ];
    for (const [label, mutate, pointer] of cases) {
      const body = base();
      mutate(body);
      const response = await station.inject("POST", "/v1/packages", body);
      assert.equal(response.statusCode, 422, `${label}: ${response.body}`);
      const problem = problemOf(response);
      assert.equal(problem.code, "invalid_upload_session", label);
      assert.ok(
        problem.errors?.some((error) => error.pointer === pointer),
        `${label}: ${response.body}`,
      );
      const stored = await station.db.query("SELECT 1 FROM packages WHERE package_id = $1", [
        body.packageId,
      ]);
      assert.equal(stored.rowCount, 0, `${label}: nothing may be registered`);
    }
  });

  it("answers 400 invalid_request for schema violations", async () => {
    const cases: [string, (body: ReturnType<typeof base>) => void][] = [
      ["an unknown property", (b) => (b.extra = true)],
      [
        "an uppercase sha256",
        (b) => (b.files[0]!.sha256 = String(b.files[0]!.sha256).toUpperCase()),
      ],
      ["negative bytes", (b) => (b.files[0]!.bytes = -1)],
      ["an unknown role", (b) => (b.files[0]!.role = "selfie")],
      ["a path with ..", (b) => (b.files[0]!.path = "Original Exports/../secret")],
      ["an absolute path", (b) => (b.files[0]!.path = "/etc/passwd")],
      ["no files", (b) => (b.files = [])],
      ["a non-uuid packageId", (b) => (b.packageId = "package-1")],
      ["revision 0", (b) => (b.revision = 0)],
      ["an empty dealId", (b) => (b.dealId = "")],
    ];
    for (const [label, mutate] of cases) {
      const body = base();
      mutate(body);
      const response = await station.inject("POST", "/v1/packages", body);
      assert.equal(response.statusCode, 400, `${label}: ${response.body}`);
      assert.equal(problemOf(response).code, "invalid_request", label);
    }
  });
});

describe("file reports", () => {
  it("answer 404 for an unknown package or an undeclared path and 400 for a bad packageId", async () => {
    const pkg = makePackage();
    assert.equal((await station.openSession(pkg)).statusCode, 201);
    const unknownPackage = await station.complete(randomUUID(), pkg.session.files[0]?.path ?? "");
    assert.equal(unknownPackage.statusCode, 404);
    assert.equal(problemOf(unknownPackage).code, "package_not_found");
    const unknownPath = await station.complete(pkg.packageId, "Original Exports/none.bin");
    assert.equal(unknownPath.statusCode, 404);
    assert.equal(problemOf(unknownPath).code, "file_not_found");
    const badId = await station.inject("POST", "/v1/packages/not-a-uuid/files/complete", {
      path: "a",
    });
    assert.equal(badId.statusCode, 400);
    const badBody = await station.inject("POST", `/v1/packages/${pkg.packageId}/files/complete`, {
      path: "a",
      sha256: "0".repeat(64),
    });
    assert.equal(badBody.statusCode, 400);
  });
});

describe("secrets", () => {
  it("never writes a SAS signature to the log or the audit log", async () => {
    const pkg = makePackage();
    const response = await station.openSession(pkg);
    const session = response.json() as UploadSessionView;
    const signatures = session.files.map(
      (file) => new URL(file.upload?.url ?? "").searchParams.get("sig") ?? "",
    );
    assert.ok(signatures.every((sig) => sig.length > 10));
    await station.openSession(pkg);
    const audit = await station.db.query<{ details: unknown }>("SELECT details FROM audit_log");
    const auditText = JSON.stringify(audit.rows);
    const logText = station.logs.join("\n");
    for (const sig of signatures) {
      assert.ok(!auditText.includes(sig), "SAS signature found in audit_log");
      assert.ok(!logText.includes(sig), "SAS signature found in the log");
      assert.ok(!logText.includes(encodeURIComponent(sig)), "SAS signature found in the log");
    }
    assert.ok(!/AccountKey=/i.test(logText));
  });
});

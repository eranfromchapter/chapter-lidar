// Revision n+1 of a visit (phone-package §10.3, OpenAPI 1.1.0 createUploadSession): unchanged
// files are verified at once by carry-over from revision n, only new and changed files are
// uploaded, supersedes_mismatch, the next-revision notice's removal, the station's createdAt in
// the session answer, the retired phone report at sealing, and the review read model stored at
// sealing (field controls, manifest size, links). Every answer of these flows is checked
// against contract/openapi/station.yaml. Runs against a real Postgres and Azurite.

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { after, before, describe, it } from "node:test";
import { manifestPath } from "../../src/storage/originals.js";
import { OpenApiContract } from "./support/openapi.js";
import {
  FIXTURE_ROOT,
  makePackage,
  nextRevision,
  sha256,
  type TestPackage,
} from "./support/package.js";
import {
  startUploadStation,
  uploadAll,
  uploadVerifiedPackage,
  type UploadSessionView,
  type UploadStation,
} from "./support/station.js";

const REVIEW_BASE_URL = "https://review.example.test/";
const HUB_DEAL_TEMPLATE = "https://hub.example.test/deals/{dealId}?tab=files";

let station: UploadStation;
const contract = new OpenApiContract();

before(async () => {
  station = await startUploadStation({
    REVIEW_BASE_URL,
    HUB_WEB_DEAL_URL_TEMPLATE: HUB_DEAL_TEMPLATE,
  });
});

after(async () => {
  await station?.close();
});

interface PackageFileBody {
  path: string;
  status: string;
  checkedAt?: string;
  carriedOverFrom?: string;
}

interface PackageBody {
  packageId: string;
  status: string;
  createdAt: string;
  files: PackageFileBody[];
  links?: { review: string; hub?: string };
  fieldControls?: unknown;
  manifestFile?: { path: string; sha256: string; bytes: number };
  nextRevision?: { revision: number; updatedBy?: string; changes: unknown[] };
}

interface FileRegistryRow {
  path: string;
  status: string;
  blob_name: string;
  actual_sha256: string | null;
  actual_bytes: number | null;
  checked_at: Date | null;
  verified_at: Date | null;
  carried_over_from: string | null;
}

async function registryFiles(packageId: string): Promise<Map<string, FileRegistryRow>> {
  const result = await station.db.query<FileRegistryRow>(
    `SELECT path, status, blob_name, actual_sha256, actual_bytes, checked_at, verified_at,
            carried_over_from
       FROM package_files WHERE package_id = $1`,
    [packageId],
  );
  return new Map(result.rows.map((row) => [row.path, row]));
}

/** The response, after checking it against the operation in station.yaml. */
function checked<T extends Parameters<OpenApiContract["assertResponse"]>[1]>(
  operationId: string,
  response: T,
): T {
  contract.assertResponse(operationId, response);
  return response;
}

async function getPackage(packageId: string): Promise<PackageBody> {
  const response = checked(
    "getPackage",
    await station.inject("GET", `/v1/packages/${packageId}`, undefined, ["bim"]),
  );
  assert.equal(response.statusCode, 200, response.body);
  return response.json() as PackageBody;
}

async function sealedPackage(options: Parameters<typeof makePackage>[0] = {}) {
  const pkg = makePackage(options);
  await uploadVerifiedPackage(station, pkg);
  const sealed = checked("sealPackage", await station.seal(pkg.packageId, pkg.manifestBytes));
  assert.equal(sealed.statusCode, 202, sealed.body);
  return pkg;
}

function problemOf(response: { json(): unknown }) {
  return response.json() as { code: string; errors?: { pointer: string; message: string }[] };
}

const roleOf = (pkg: TestPackage, role: string) =>
  pkg.manifest.files.find((file) => file.role === role)?.path ?? "";

describe("revision 2 reuses the verified files of revision 1", () => {
  let rev1: TestPackage;
  let rev2: TestPackage;
  let rev1Before: PackageBody;
  let changedPath: string;
  let addedPath: string;
  let session: UploadSessionView;

  before(async () => {
    rev1 = await sealedPackage();
    rev1Before = await getPackage(rev1.packageId);
    changedPath = roleOf(rev1, "rooms_csv");
    const photo = roleOf(rev1, "photo");
    addedPath = photo.replace("photo-0001.jpg", "photo-0002.jpg");
    rev2 = nextRevision(rev1, {
      replace: new Map([[changedPath, Buffer.from("Room,Area\nLiving room,12.0\n")]]),
      add: [{ path: addedPath, like: photo, data: Buffer.from("second photo bytes") }],
    });
  });

  it("verifies unchanged files at once and grants targets only for new or changed files", async () => {
    const response = checked("createUploadSession", await station.openSession(rev2));
    assert.equal(response.statusCode, 201, response.body);
    session = response.json() as typeof session;
    assert.match(String(session.createdAt), /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/);
    for (const file of session.files) {
      if (file.path === changedPath || file.path === addedPath) {
        assert.equal(file.status, "pending", file.path);
        assert.ok(file.upload, file.path);
        assert.ok(!("carriedOverFrom" in file), file.path);
      } else {
        assert.deepEqual(file, {
          path: file.path,
          status: "verified",
          carriedOverFrom: rev1.packageId,
        });
      }
    }
    assert.equal(session.files.filter((file) => file.upload !== undefined).length, 2);
  });

  it("registers carried files on revision 1's blobs with revision 1's check, and audits it", async () => {
    const before = await registryFiles(rev1.packageId);
    const after = await registryFiles(rev2.packageId);
    for (const [path, row] of after) {
      if (path === changedPath || path === addedPath) {
        assert.equal(row.status, "pending");
        assert.equal(row.carried_over_from, null);
        assert.equal(row.blob_name, `${rev2.packageId}/${path}`);
        continue;
      }
      const previous = before.get(path);
      assert.ok(previous, path);
      assert.deepEqual(
        { ...row, carried_over_from: null },
        { ...previous, carried_over_from: null },
        path,
      );
      assert.equal(row.carried_over_from, rev1.packageId);
    }
    const audits = await station.db.query<{ details: Record<string, unknown> }>(
      "SELECT details FROM audit_log WHERE action = 'package.create' AND target_id = $1",
      [rev2.packageId],
    );
    assert.equal(audits.rows.length, 1);
    assert.equal(audits.rows[0]?.details.files, rev2.session.files.length);
    assert.equal(audits.rows[0]?.details.uploadTargets, 2);
    assert.equal(audits.rows[0]?.details.carriedOver, rev2.session.files.length - 2);
    assert.equal(audits.rows[0]?.details.supersedesPackageId, rev1.packageId);
  });

  it("answers completeFile for a carried file from the stored check, without reading storage", async () => {
    const carried = roleOf(rev2, "plan_dxf");
    const storage = station.storage as { digest: typeof station.storage.digest };
    const digest = storage.digest;
    let reads = 0;
    storage.digest = async (blobName) => {
      reads += 1;
      return digest.call(station.storage, blobName);
    };
    try {
      const response = checked("completeFile", await station.complete(rev2.packageId, carried));
      assert.equal(response.statusCode, 200, response.body);
      const check = response.json() as { status: string; checkedAt: string };
      assert.equal(check.status, "verified");
      const original = rev1Before.files.find((file) => file.path === carried);
      assert.equal(check.checkedAt, original?.checkedAt);
      assert.equal(reads, 0);
    } finally {
      storage.digest = digest;
    }
  });

  it("resumes with the same carried files and targets only for the rest", async () => {
    const response = checked("createUploadSession", await station.openSession(rev2));
    assert.equal(response.statusCode, 200, response.body);
    const resumed = response.json() as typeof session;
    assert.equal(resumed.createdAt, session.createdAt);
    assert.deepEqual(
      resumed.files.filter((file) => file.carriedOverFrom !== undefined).map((file) => file.path),
      session.files.filter((file) => file.carriedOverFrom !== undefined).map((file) => file.path),
    );
    assert.deepEqual(
      resumed.files.filter((file) => file.upload !== undefined).map((file) => file.path),
      [changedPath, addedPath],
    );
  });

  it("seals revision 2 after uploading only the new and changed files", async () => {
    const results = await uploadAll(station, rev2, session);
    assert.deepEqual([...results.keys()].sort(), [changedPath, addedPath].sort());
    const sealed = checked("sealPackage", await station.seal(rev2.packageId, rev2.manifestBytes));
    assert.equal(sealed.statusCode, 202, sealed.body);
    const body = sealed.json() as PackageBody;
    assert.equal(body.createdAt, session.createdAt);
    const carried = body.files.filter((file) => file.carriedOverFrom === rev1.packageId);
    assert.equal(carried.length, rev2.session.files.length - 2);
    const fetched = await getPackage(rev2.packageId);
    assert.deepEqual(
      fetched.files.filter((file) => file.carriedOverFrom !== undefined).length,
      carried.length,
    );
  });

  it("leaves revision 1 unchanged", async () => {
    const now = await getPackage(rev1.packageId);
    assert.deepEqual(now.files, rev1Before.files);
  });

  it("hands out download links of carried files that read revision 1's blob", async () => {
    const path = roleOf(rev2, "capture_model");
    const response = checked(
      "getFileDownloadLink",
      await station.inject(
        "GET",
        `/v1/packages/${rev2.packageId}/files/download?${new URLSearchParams({ path })}`,
        undefined,
        ["bim"],
      ),
    );
    assert.equal(response.statusCode, 200, response.body);
    const link = response.json() as { url: string; sha256: string };
    assert.ok(decodeURIComponent(new URL(link.url).pathname).includes(`${rev1.packageId}/${path}`));
    const fetched = Buffer.from(await (await fetch(link.url)).arrayBuffer());
    assert.equal(sha256(fetched), link.sha256);
    assert.deepEqual(fetched, rev1.files.get(path));
  });
});

describe("supersedes_mismatch", () => {
  let rev1: TestPackage;

  before(async () => {
    rev1 = await sealedPackage();
  });

  const cases: [string, () => TestPackage, string][] = [
    [
      "another visit",
      () => makePackage({ revision: 2, supersedesPackageId: rev1.packageId }),
      "another visit",
    ],
    [
      "another deal",
      () =>
        makePackage({
          visitId: rev1.visitId,
          revision: 2,
          supersedesPackageId: rev1.packageId,
          dealId: "fixture-deal-0002",
        }),
      "another deal",
    ],
    [
      "a revision gap",
      () =>
        makePackage({ visitId: rev1.visitId, revision: 3, supersedesPackageId: rev1.packageId }),
      "not revision 2",
    ],
  ];

  for (const [label, build, message] of cases) {
    it(`answers 422 for ${label} and registers nothing`, async () => {
      const pkg = build();
      const response = checked("createUploadSession", await station.openSession(pkg));
      assert.equal(response.statusCode, 422, response.body);
      const problem = problemOf(response);
      assert.equal(problem.code, "supersedes_mismatch");
      assert.ok(
        problem.errors?.some(
          (error) => error.pointer === "/supersedesPackageId" && error.message.includes(message),
        ),
        response.body,
      );
      const rows = await station.db.query("SELECT 1 FROM packages WHERE package_id = $1", [
        pkg.packageId,
      ]);
      assert.equal(rows.rowCount, 0);
    });
  }
});

describe("the next-revision notice", () => {
  let rev1: TestPackage;
  const notice = {
    revision: 2,
    updatedAt: "2026-10-21T14:02:00Z",
    changes: [
      { kind: "added", subject: "capture", title: "Primary closet", detail: "Room · 3 files" },
    ],
  };

  before(async () => {
    rev1 = await sealedPackage();
  });

  it("is shown on revision 1 until the session of revision 2 opens", async () => {
    const put = checked(
      "putNextRevisionNotice",
      await station.inject("PUT", `/v1/packages/${rev1.packageId}/next-revision`, notice),
    );
    assert.equal(put.statusCode, 200, put.body);
    assert.deepEqual((await getPackage(rev1.packageId)).nextRevision, {
      ...notice,
      updatedBy: "Dana Field",
    });

    const rev2 = nextRevision(rev1);
    const opened = checked("createUploadSession", await station.openSession(rev2));
    assert.equal(opened.statusCode, 201, opened.body);
    assert.equal((await getPackage(rev1.packageId)).nextRevision, undefined);
    const audit = await station.db.query<{ details: Record<string, unknown> }>(
      "SELECT details FROM audit_log WHERE action = 'package.create' AND target_id = $1",
      [rev2.packageId],
    );
    assert.equal(audit.rows[0]?.details.nextRevisionNoticeRemoved, true);
    assert.equal(audit.rows[0]?.details.uploadTargets, 0);
  });

  it("cannot be stored again once revision 2 exists (409 revision_exists)", async () => {
    const put = checked(
      "putNextRevisionNotice",
      await station.inject("PUT", `/v1/packages/${rev1.packageId}/next-revision`, notice),
    );
    assert.equal(put.statusCode, 409, put.body);
    assert.equal(problemOf(put).code, "revision_exists");
  });
});

describe("the retired phone report at sealing", () => {
  it("accepts a legacy 1.0.0 manifest that lists spatial-report.pdf (202)", async () => {
    const pkg = makePackage({ fixture: "legacy-1.0.0" });
    assert.equal(pkg.manifest.schemaVersion, "1.0.0");
    assert.ok(pkg.manifest.files.some((file) => file.role === "spatial_report_pdf"));
    await uploadVerifiedPackage(station, pkg);
    const sealed = checked("sealPackage", await station.seal(pkg.packageId, pkg.manifestBytes));
    assert.equal(sealed.statusCode, 202, sealed.body);
  });

  it("refuses a 1.1.0 manifest that lists the retired role (422 invalid_manifest)", async () => {
    const pkg = makePackage({ fixture: "legacy-1.0.0", schemaVersion: "1.1.0" });
    await uploadVerifiedPackage(station, pkg);
    const index = pkg.manifest.files.findIndex((file) => file.role === "spatial_report_pdf");
    const sealed = checked("sealPackage", await station.seal(pkg.packageId, pkg.manifestBytes));
    assert.equal(sealed.statusCode, 422, sealed.body);
    const problem = problemOf(sealed);
    assert.equal(problem.code, "invalid_manifest");
    assert.ok(
      problem.errors?.some((error) => error.pointer === `/files/${index}/role`),
      sealed.body,
    );
  });
});

describe("the review read model stored at sealing", () => {
  it("stores the parsed field controls and the manifest size, and links the package", async () => {
    const pkg = await sealedPackage();
    const controlsPath = roleOf(pkg, "field_controls");
    const expected = JSON.parse(String(pkg.files.get(controlsPath))) as unknown;
    const row = await station.db.query<{ field_controls: unknown; manifest_bytes: number }>(
      "SELECT field_controls, manifest_bytes FROM packages WHERE package_id = $1",
      [pkg.packageId],
    );
    assert.deepEqual(row.rows[0]?.field_controls, expected);
    assert.equal(row.rows[0]?.manifest_bytes, pkg.manifestBytes.length);

    const body = await getPackage(pkg.packageId);
    assert.deepEqual(body.fieldControls, expected);
    assert.deepEqual(body.manifestFile, {
      path: manifestPath(pkg.visitId),
      sha256: sha256(pkg.manifestBytes),
      bytes: pkg.manifestBytes.length,
    });
    assert.deepEqual(body.links, {
      review: `https://review.example.test/packages/${pkg.packageId}`,
      hub: "https://hub.example.test/deals/fixture-deal-0001?tab=files",
    });
  });

  it("seals a package whose field controls break the contract, without storing them", async () => {
    const fixtureVisit = "c1b6d1fb-17af-4f4a-877c-2565ef9bdb86";
    const controls = `Field Measurements/${fixtureVisit}/field-controls.json`;
    assert.ok(readFileSync(join(FIXTURE_ROOT, controls)).length > 0, "fixture path");
    const pkg = await sealedPackage({
      fileOverrides: new Map([[controls, Buffer.from('{"schemaVersion":"9.9.9"}')]]),
    });
    const body = await getPackage(pkg.packageId);
    assert.equal(body.status, "checks_queued");
    assert.equal(body.fieldControls, undefined);
    assert.equal(body.manifestFile?.bytes, pkg.manifestBytes.length);
    assert.ok(station.logs.some((line) => line.includes("field controls do not match")));
  });

  it("answers the station's createdAt when the session opens (201) and resumes (200)", async () => {
    const pkg = makePackage();
    const opened = checked("createUploadSession", await station.openSession(pkg));
    const resumed = checked("createUploadSession", await station.openSession(pkg));
    const createdAt = (opened.json() as { createdAt: string }).createdAt;
    assert.equal((resumed.json() as { createdAt: string }).createdAt, createdAt);
    assert.equal((await getPackage(pkg.packageId)).createdAt, createdAt);
  });
});

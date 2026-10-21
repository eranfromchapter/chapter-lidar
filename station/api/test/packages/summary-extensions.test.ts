// The 1.1.0 package summary and detail (web-review §9.1 A and B, phone-package §10.3, critique
// R-14 to R-16) as listPackages and getPackage return them: updatedAt, createdBy, captures
// before and after the seal, totals, checks per state, publication per state, report per
// state, links, PackageFile.generator / carriedOverFrom / hub, manifestFile and fieldControls.
// Every response validates against contract/openapi/station.yaml. Runs against a throwaway
// Postgres; worker-written rows (check runs, publications, spatial reports) are seeded.

import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { after, before, describe, it } from "node:test";
import { linksOf, reportFloors } from "../../src/routes/packages/store.js";
import { manifestPath } from "../../src/storage/originals.js";
import { OpenApi } from "./openapi.js";
import {
  BROKEN_VERDICT_ID,
  DEAL_ID,
  FIELD_CONTROLS,
  FLOOR_1,
  FLOOR_2,
  MANIFEST,
  PACKAGE_ID,
  QUEUED_ID,
  REVISION_2_ID,
  VERDICT,
  VISIT_ID,
  filesOf,
  insertFile,
  insertPackage,
  manifestText,
  seedRegistry,
  startStation,
  type ManifestFile,
  type TestStation,
} from "./support.js";

const REVIEW = "https://review.example.test/base/";
const HUB_TEMPLATE = "https://hub.example.test/deals/{dealId}";

const openapi = new OpenApi();
let station: TestStation;

const STATE_DEAL = "HUB-5005";
const CHECKING_ID = "a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c01";
const ERROR_ID = "a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c02";
const FAILED_PUBLICATION_ID = "a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c03";
const OLD_REPORT_ID = "a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c04";
const TWO_FLOOR_UPLOAD_ID = "a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c05";
const NAMELESS_ID = "a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c06";
const ODD_DEAL_ID = "a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c07";
const ODD_DEAL = "HUB 7/7?x";
const ODD_FLOORS_ID = "a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c08";
const ODD_FLOORS_VERDICT = "c1d2e3f4-a5b6-4c7d-8e9f-0a1b2c3d4e08";

const PLAN_DXF = MANIFEST.files.find((file) => file.role === "plan_dxf")!;
const MESH = MANIFEST.files.find((file) => file.role === "mesh_glb")!;
const PHOTO = MANIFEST.files.find((file) => file.role === "photo")!;

function sha256(text: string): string {
  return createHash("sha256").update(text).digest("hex");
}

/** A visit id per package id (only the last digits differ). */
function visitOf(packageId: string): string {
  return `b${packageId.slice(1)}`;
}

async function sealedWithVerdict(packageId: string, verdictId: string): Promise<void> {
  const manifest = {
    ...MANIFEST,
    packageId,
    visitId: visitOf(packageId),
    files: MANIFEST.files.slice(0, 1),
  };
  await insertPackage(
    station.db,
    {
      packageId,
      visitId: visitOf(packageId),
      dealId: STATE_DEAL,
      revision: 1,
      status: "verdict_ready",
      createdAt: "2026-10-18T09:00:00.000Z",
      sealed: { manifest },
    },
    filesOf(manifest),
  );
  const verdict = { ...VERDICT, verdictId, packageId };
  await station.db.query(
    `INSERT INTO verdicts (verdict_id, package_id, outcome, evaluated_at, document)
     VALUES ($1, $2, $3, $4, $5::jsonb)`,
    [verdictId, packageId, VERDICT.outcome, VERDICT.evaluatedAt, JSON.stringify(verdict)],
  );
}

async function sealedWithStatus(packageId: string, status: string): Promise<void> {
  const manifest = {
    ...MANIFEST,
    packageId,
    visitId: visitOf(packageId),
    files: MANIFEST.files.slice(0, 1),
  };
  await insertPackage(
    station.db,
    {
      packageId,
      visitId: visitOf(packageId),
      dealId: STATE_DEAL,
      revision: 1,
      status,
      createdAt: "2026-10-18T09:00:00.000Z",
      sealed: { manifest },
    },
    filesOf(manifest),
  );
}

before(async () => {
  station = await startStation({
    env: { REVIEW_BASE_URL: REVIEW, HUB_WEB_DEAL_URL_TEMPLATE: HUB_TEMPLATE },
  });
  await seedRegistry(station.db);

  // PACKAGE_ID: a completed run with three rule results, published, with its spatial report.
  const run = await station.db.query<{ run_id: string }>(
    `INSERT INTO check_runs (package_id, status, evaluator_name, evaluator_version, started_at,
                             finished_at)
     VALUES ($1, 'completed', 'station-checks', '1.1.0', '2026-10-17T15:20:01.400Z',
             '2026-10-17T15:20:44.900Z')
     RETURNING run_id`,
    [PACKAGE_ID],
  );
  for (const [ordinal, ruleId] of [
    "scale.controls",
    "coverage.rooms",
    "orientation.compass",
  ].entries()) {
    await station.db.query(
      `INSERT INTO check_results (run_id, ordinal, rule_id, title, status)
       VALUES ($1, $2, $3, 'A rule', 'passed')`,
      [run.rows[0]?.run_id, ordinal, ruleId],
    );
  }
  const entry = (fields: Record<string, unknown>) => ({
    folder: null,
    sha256: "a".repeat(64),
    bytes: 1,
    recordedAt: "2026-10-17T15:30:00Z",
    ...fields,
  });
  await station.db.query(
    `INSERT INTO hub_publications (package_id, verdict_id, status, attempts, files, published_at)
     VALUES ($1, $2, 'published', 1, $3::jsonb, '2026-10-17T15:31:09.700Z')`,
    [
      PACKAGE_ID,
      VERDICT.verdictId,
      JSON.stringify([
        entry({ kind: "uploaded", name: "plan.dxf", path: PLAN_DXF.path, role: "plan_dxf" }),
        entry({
          kind: "linked",
          name: MESH.path,
          path: MESH.path,
          role: "mesh_glb",
          reason: "too_large",
        }),
        entry({
          kind: "linked",
          name: PHOTO.path,
          path: PHOTO.path,
          role: "photo",
          reason: "not_published",
        }),
        entry({
          kind: "uploaded",
          name: "manifest.json",
          path: manifestPath(VISIT_ID),
          role: "manifest",
        }),
        entry({
          kind: "uploaded",
          name: `spatial-report-${VERDICT.verdictId}.pdf`,
          path: null,
          role: "spatial_report",
          verdictId: VERDICT.verdictId,
        }),
      ]),
    ],
  );
  await station.db.query(
    `INSERT INTO spatial_reports (package_id, verdict_id, file_name, blob_name, sha256, bytes,
                                  pages, checks_page, floors, generated_at)
     VALUES ($1, $2, $3, $4, $5, 3355443, 28, 4, $6::jsonb, $7)`,
    [
      PACKAGE_ID,
      VERDICT.verdictId,
      `spatial-report-${VERDICT.verdictId}.pdf`,
      `${PACKAGE_ID}/spatial-report-${VERDICT.verdictId}.pdf`,
      sha256("report"),
      JSON.stringify([
        { ...FLOOR_1, roomsScanned: 12, roomsUnlabeled: 5, floorAreaSqFt: 807.5 },
        { ...FLOOR_2, roomsScanned: 4, roomsUnlabeled: 0, floorAreaSqFt: 312.2 },
      ]),
      VERDICT.evaluatedAt,
    ],
  );

  // BROKEN_VERDICT_ID: a verdict whose publish job is queued (no publication row yet).
  await station.db.query("INSERT INTO jobs (type, package_id) VALUES ('publish', $1)", [
    BROKEN_VERDICT_ID,
  ]);

  // Checks running (claimed job), checks failed (failed run).
  await sealedWithStatus(CHECKING_ID, "checking");
  await station.db.query(
    `INSERT INTO jobs (type, package_id, status, attempts, locked_at, locked_by)
     VALUES ('checks', $1, 'running', 1, '2026-10-18T10:00:00.250Z', 'worker-1')`,
    [CHECKING_ID],
  );
  await sealedWithStatus(ERROR_ID, "check_error");
  await station.db.query(
    `INSERT INTO check_runs (package_id, status, started_at, finished_at, error)
     VALUES ($1, 'failed', '2026-10-18T10:00:00Z', '2026-10-18T10:00:09Z', 'HUB unavailable')`,
    [ERROR_ID],
  );

  // The current verdict's publication failed and there is no report.
  const failedVerdict = "c1d2e3f4-a5b6-4c7d-8e9f-0a1b2c3d4e03";
  await sealedWithVerdict(FAILED_PUBLICATION_ID, failedVerdict);
  await station.db.query(
    `INSERT INTO hub_publications (package_id, verdict_id, status, attempts, error)
     VALUES ($1, $2, 'publish_failed', 5, '{"status": 503, "message": "HUB unavailable"}')`,
    [FAILED_PUBLICATION_ID, failedVerdict],
  );

  // A report row of an earlier verdict.
  await sealedWithVerdict(OLD_REPORT_ID, "c1d2e3f4-a5b6-4c7d-8e9f-0a1b2c3d4e04");
  const oldVerdict = "c1d2e3f4-a5b6-4c7d-8e9f-0a1b2c3d4e99";
  await station.db.query(
    `INSERT INTO spatial_reports (package_id, verdict_id, file_name, blob_name, sha256, bytes,
                                  pages, checks_page, floors, generated_at)
     VALUES ($1, $2, $3, 'old', $4, 1, 1, 1, '[]', now())`,
    [OLD_REPORT_ID, oldVerdict, `spatial-report-${oldVerdict}.pdf`, sha256("old")],
  );

  // A report whose floors the worker wrote off-contract: an extra key, a missing key, a
  // negative count and a non-object.
  await sealedWithVerdict(ODD_FLOORS_ID, ODD_FLOORS_VERDICT);
  await station.db.query(
    `INSERT INTO spatial_reports (package_id, verdict_id, file_name, blob_name, sha256, bytes,
                                  pages, checks_page, floors, generated_at)
     VALUES ($1, $2, $3, 'odd', $4, 1, 1, 1, $5::jsonb, $6)`,
    [
      ODD_FLOORS_ID,
      ODD_FLOORS_VERDICT,
      `spatial-report-${ODD_FLOORS_VERDICT}.pdf`,
      sha256("odd"),
      JSON.stringify([
        { ...FLOOR_1, roomsScanned: 3, roomsUnlabeled: 1, floorAreaSqFt: 120.4, label: "Ground" },
        { ...FLOOR_2, roomsScanned: 2, roomsUnlabeled: 0 },
        { ...FLOOR_2, roomsScanned: -1, roomsUnlabeled: 0, floorAreaSqFt: 10 },
        "floor-3",
      ]),
      VERDICT.evaluatedAt,
    ],
  );

  // Uploading with files of two floors, declared floor 2 first.
  const floor1 = MANIFEST.files.find((file) => file.areaKey === "floor-1")!;
  const floor2 = MANIFEST.files.find((file) => file.areaKey === "floor-2")!;
  await insertPackage(
    station.db,
    {
      packageId: TWO_FLOOR_UPLOAD_ID,
      visitId: visitOf(TWO_FLOOR_UPLOAD_ID),
      dealId: STATE_DEAL,
      revision: 1,
      status: "uploading",
      createdAt: "2026-10-18T11:00:00.000Z",
    },
    [floor2, floor1] as ManifestFile[],
  );
  await insertFile(station.db, TWO_FLOOR_UPLOAD_ID, floor2, "pending");
  await insertFile(station.db, TWO_FLOOR_UPLOAD_ID, floor1, "verified");

  // No creator name; a deal id that needs URL encoding.
  await station.db.query(
    `INSERT INTO packages (package_id, visit_id, deal_id, revision, session_request, created_by_id)
     VALUES ($1, $2, $3, 1, '{"files":[]}', 'service-principal-1')`,
    [NAMELESS_ID, visitOf(NAMELESS_ID), STATE_DEAL],
  );
  await station.db.query(
    `INSERT INTO packages (package_id, visit_id, deal_id, revision, session_request, created_by_id,
                           created_by_name)
     VALUES ($1, $2, $3, 1, '{"files":[]}', 'user-1', 'Dana Field')`,
    [ODD_DEAL_ID, visitOf(ODD_DEAL_ID), ODD_DEAL],
  );
});

after(async () => {
  await station?.close();
});

type Body = Record<string, unknown> & { files: Record<string, unknown>[] };

async function detail(packageId: string): Promise<Body> {
  const response = await station.app.inject({
    method: "GET",
    url: `/v1/packages/${packageId}`,
    headers: await station.auth(["bim"]),
  });
  assert.deepEqual(openapi.responseErrors("getPackage", response), [], response.body);
  assert.equal(response.statusCode, 200, response.body);
  return response.json() as Body;
}

async function summaries(dealId: string): Promise<Map<string, Record<string, unknown>>> {
  const response = await station.app.inject({
    method: "GET",
    url: `/v1/packages?${new URLSearchParams({ dealId })}`,
    headers: await station.auth(["capture"]),
  });
  assert.deepEqual(openapi.responseErrors("listPackages", response), [], response.body);
  const { packages } = response.json() as { packages: Record<string, unknown>[] };
  return new Map(packages.map((pkg) => [String(pkg.packageId), pkg]));
}

describe("summary fields", () => {
  it("updatedAt is the latest change of the package, its files, verdict, publication and report", async () => {
    const latest = await station.db.query<{ at: Date }>(
      `SELECT max(at) AS at FROM (
         SELECT updated_at AS at FROM packages WHERE package_id = $1
         UNION ALL SELECT updated_at FROM package_files WHERE package_id = $1
         UNION ALL SELECT updated_at FROM verdicts WHERE package_id = $1
         UNION ALL SELECT updated_at FROM hub_publications WHERE package_id = $1
         UNION ALL SELECT updated_at FROM spatial_reports WHERE package_id = $1) t`,
      [PACKAGE_ID],
    );
    const report = await station.db.query<{ at: Date }>(
      "SELECT updated_at AS at FROM spatial_reports WHERE package_id = $1",
      [PACKAGE_ID],
    );
    assert.deepEqual(latest.rows[0]?.at, report.rows[0]?.at, "the report row is the last change");
    const expected = latest.rows[0]!.at.toISOString().replace(/\.\d{3}Z$/, "Z");
    assert.equal((await detail(PACKAGE_ID)).updatedAt, expected);
    assert.equal((await summaries(DEAL_ID)).get(PACKAGE_ID)?.updatedAt, expected);
  });

  it("createdBy is the session's user, omitted when the name is unknown", async () => {
    const rows = await summaries(STATE_DEAL);
    assert.deepEqual(rows.get(CHECKING_ID)?.createdBy, { name: "Dana Field" });
    assert.ok(!("createdBy" in rows.get(NAMELESS_ID)!));
  });

  it("captures follow the capture record once sealed, else first appearance in path order", async () => {
    const sealed = await detail(PACKAGE_ID);
    assert.deepEqual(sealed.captures, [
      { ...FLOOR_1, label: "Floor 1", mode: "floor" },
      { ...FLOOR_2, label: "Floor 2", mode: "floor" },
    ]);
    assert.equal(sealed.visitedAt, "2026-10-17T13:55:00Z");
    assert.equal(sealed.operatorName, "Test Operator");
    const uploading = await detail(TWO_FLOOR_UPLOAD_ID);
    assert.deepEqual(uploading.captures, [FLOOR_1, FLOOR_2]);
    assert.ok(!("visitedAt" in uploading) && !("operatorName" in uploading));
    assert.deepEqual((await detail(NAMELESS_ID)).captures, []);
  });

  it("totals count every declared file and the verified ones", async () => {
    const rev2 = await detail(REVISION_2_ID);
    const declared = MANIFEST.files.slice(0, 5);
    const verified = declared[4]!;
    assert.deepEqual(rev2.totals, {
      files: 5,
      bytes: declared.reduce((sum, file) => sum + file.bytes, 0),
      filesVerified: 1,
      bytesVerified: verified.bytes,
    });
    assert.deepEqual((await detail(NAMELESS_ID)).totals, {
      files: 0,
      bytes: 0,
      filesVerified: 0,
      bytesVerified: 0,
    });
  });
});

describe("checks", () => {
  it("is omitted before the seal and follows the package status after it", async () => {
    const rows = new Map([...(await summaries(DEAL_ID)), ...(await summaries(STATE_DEAL))]);
    assert.ok(!("checks" in rows.get(REVISION_2_ID)!));
    assert.deepEqual(rows.get(QUEUED_ID)?.checks, { status: "queued" });
    assert.deepEqual(rows.get(CHECKING_ID)?.checks, {
      status: "running",
      startedAt: "2026-10-18T10:00:00Z",
    });
    assert.deepEqual(rows.get(PACKAGE_ID)?.checks, {
      status: "completed",
      startedAt: "2026-10-17T15:20:01Z",
      finishedAt: "2026-10-17T15:20:44Z",
      rules: 3,
    });
    assert.deepEqual(rows.get(ERROR_ID)?.checks, {
      status: "failed",
      startedAt: "2026-10-18T10:00:00Z",
      finishedAt: "2026-10-18T10:00:09Z",
    });
    // A verdict without a recorded run: completed at the verdict's time.
    assert.deepEqual(rows.get(FAILED_PUBLICATION_ID)?.checks, {
      status: "completed",
      finishedAt: VERDICT.evaluatedAt,
    });
  });
});

describe("publication", () => {
  it("is the HUB publication state with the revision's folder, pending while only queued", async () => {
    const rows = new Map([
      ...(await summaries(DEAL_ID)),
      ...(await summaries("HUB-2002")),
      ...(await summaries(STATE_DEAL)),
    ]);
    assert.deepEqual(rows.get(PACKAGE_ID)?.publication, {
      status: "published",
      publishedAt: "2026-10-17T15:31:09Z",
      hubFolder: `Capture/${VISIT_ID}/r1`,
    });
    assert.deepEqual(rows.get(BROKEN_VERDICT_ID)?.publication, {
      status: "pending",
      hubFolder: "Capture/6a7b8c9d-0e1f-4a2b-8c3d-4e5f6a7b8c9d/r1",
    });
    assert.deepEqual(rows.get(FAILED_PUBLICATION_ID)?.publication, {
      status: "publish_failed",
      hubFolder: `Capture/${visitOf(FAILED_PUBLICATION_ID)}/r1`,
    });
    assert.ok(!("publication" in rows.get(QUEUED_ID)!));
  });
});

describe("report", () => {
  it("is ready with the report's facts and HUB state for the current verdict", async () => {
    assert.deepEqual((await detail(PACKAGE_ID)).report, {
      status: "ready",
      generatedAt: VERDICT.evaluatedAt,
      pages: 28,
      bytes: 3355443,
      sha256: sha256("report"),
      checksPage: 4,
      floors: [
        { ...FLOOR_1, roomsScanned: 12, roomsUnlabeled: 5, floorAreaSqFt: 807.5 },
        { ...FLOOR_2, roomsScanned: 4, roomsUnlabeled: 0, floorAreaSqFt: 312.2 },
      ],
      hub: { state: "uploaded" },
    });
  });

  it("is pending without a report of the current verdict, failed when its publication failed", async () => {
    const rows = new Map([...(await summaries("HUB-2002")), ...(await summaries(STATE_DEAL))]);
    assert.deepEqual(rows.get(BROKEN_VERDICT_ID)?.report, { status: "pending" });
    assert.deepEqual(rows.get(OLD_REPORT_ID)?.report, { status: "pending" });
    assert.deepEqual(rows.get(FAILED_PUBLICATION_ID)?.report, { status: "failed" });
    assert.ok(!("report" in rows.get(CHECKING_ID)!));
    assert.ok(!("report" in rows.get(ERROR_ID)!));
  });

  it("keeps only the contract fields of each floor and leaves out floors it cannot read", async () => {
    const expected = [{ ...FLOOR_1, roomsScanned: 3, roomsUnlabeled: 1, floorAreaSqFt: 120.4 }];
    // detail() and summaries() check every body against the contract.
    assert.deepEqual(
      ((await detail(ODD_FLOORS_ID)).report as { floors: unknown }).floors,
      expected,
    );
    assert.deepEqual(
      ((await summaries(STATE_DEAL)).get(ODD_FLOORS_ID)?.report as { floors: unknown }).floors,
      expected,
    );
    assert.deepEqual(reportFloors({ not: "an array" }), []);
  });
});

describe("links", () => {
  it("names the review page and the HUB deal page of every package", async () => {
    const pkg = await detail(PACKAGE_ID);
    assert.deepEqual(pkg.links, {
      review: `https://review.example.test/base/packages/${PACKAGE_ID}`,
      hub: `https://hub.example.test/deals/${DEAL_ID}`,
    });
    const odd = await summaries(ODD_DEAL);
    assert.deepEqual(odd.get(ODD_DEAL_ID)?.links, {
      review: `https://review.example.test/base/packages/${ODD_DEAL_ID}`,
      hub: "https://hub.example.test/deals/HUB%207%2F7%3Fx",
    });
  });

  it("omits the HUB link without a template and every link without the review URL", () => {
    assert.equal(linksOf({}, PACKAGE_ID, DEAL_ID), undefined);
    assert.equal(linksOf({ hubDealUrlTemplate: HUB_TEMPLATE }, PACKAGE_ID, DEAL_ID), undefined);
    assert.deepEqual(linksOf({ reviewBaseUrl: "https://r.example.test" }, PACKAGE_ID, DEAL_ID), {
      review: `https://r.example.test/packages/${PACKAGE_ID}`,
    });
  });
});

describe("package detail", () => {
  it("files carry the manifest generator and their HUB state", async () => {
    const pkg = await detail(PACKAGE_ID);
    const byPath = new Map(pkg.files.map((file) => [String(file.path), file]));
    assert.deepEqual(byPath.get(PLAN_DXF.path)?.hub, { state: "uploaded" });
    assert.deepEqual(byPath.get(MESH.path)?.hub, { state: "linked", reason: "too_large" });
    assert.deepEqual(byPath.get(PHOTO.path)?.hub, { state: "linked", reason: "not_published" });
    const others = pkg.files.filter(
      (file) => ![PLAN_DXF, MESH, PHOTO].some((f) => f.path === file.path),
    );
    assert.ok(others.every((file) => !("hub" in file)));
    for (const file of pkg.files) {
      const entry = MANIFEST.files.find((candidate) => candidate.path === file.path) as unknown as {
        generator: string;
        generatorVersion: string;
      };
      assert.equal(file.generator, entry.generator);
      assert.equal(file.generatorVersion, entry.generatorVersion);
      assert.ok(!("carriedOverFrom" in file));
    }
    const uploading = await detail(REVISION_2_ID);
    assert.ok(uploading.files.every((file) => !("generator" in file) && !("hub" in file)));
  });

  it("manifestFile and fieldControls are present once sealed and recorded", async () => {
    const pkg = await detail(PACKAGE_ID);
    assert.deepEqual(pkg.manifestFile, {
      path: manifestPath(VISIT_ID),
      sha256: sha256(manifestText(MANIFEST)),
      bytes: Buffer.byteLength(manifestText(MANIFEST)),
      hub: { state: "uploaded" },
    });
    assert.deepEqual(pkg.fieldControls, FIELD_CONTROLS);
    // Sealed before the read model and not backfilled yet: no size, so no manifestFile.
    const queued = await detail(QUEUED_ID);
    assert.ok(!("manifestFile" in queued) && !("fieldControls" in queued));
    const uploading = await detail(REVISION_2_ID);
    assert.ok(!("manifestFile" in uploading) && !("fieldControls" in uploading));
  });
});

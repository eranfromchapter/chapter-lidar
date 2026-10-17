// F7 AC6 (packages and verdicts area): listPackages, getPackage and getVerdict match
// contract/openapi/station.yaml: the routes exist with the documented roles, query strings are
// accepted or rejected exactly as the document says, and every response (status, content type
// and body) validates against the document. Runs against a migrated throwaway Postgres.

import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";
import { OpenApi } from "./openapi.js";
import {
  BROKEN_VERDICT_ID,
  CAPTURE_RECORD,
  DEAL_ID,
  MANIFEST,
  OTHER_DEAL_ID,
  OTHER_DEAL_PACKAGE_ID,
  PACKAGE_ID,
  QUEUED_ID,
  REVISION_2_ID,
  UNKNOWN_ID,
  VERDICT,
  VISIT_ID,
  seedRegistry,
  startStation,
  type TestStation,
} from "./support.js";

const OPERATIONS = ["listPackages", "getPackage", "getVerdict"] as const;

const openapi = new OpenApi();
let station: TestStation;

before(async () => {
  station = await startStation();
  await seedRegistry(station.db);
});

after(async () => {
  await station?.close();
});

async function call(
  operationId: (typeof OPERATIONS)[number],
  url: string,
  roles: readonly ("capture" | "bim" | "admin")[] = ["capture"],
) {
  const response = await station.app.inject({
    method: "GET",
    url,
    headers: await station.auth(roles),
  });
  const errors = openapi.responseErrors(operationId, response);
  assert.deepEqual(errors, [], `${url} -> ${response.statusCode} ${response.body}`);
  return response;
}

describe("packages area implements its OpenAPI operations", () => {
  for (const operationId of OPERATIONS) {
    it(`${operationId} is routed with the documented roles`, () => {
      const op = openapi.operation(operationId);
      const route = station.app.routeAccess.find(
        (access) => access.url === op.routeUrl && access.method.split(",").includes(op.method),
      );
      assert.ok(route, `no route for ${op.method} ${op.routeUrl}`);
      assert.deepEqual([...route.roles].sort(), [...op.roles].sort());
    });
  }
});

describe("listPackages", () => {
  it("lists a deal's packages newest first with the verdict summary only when ready", async () => {
    const response = await call("listPackages", `/v1/packages?dealId=${DEAL_ID}`);
    assert.equal(response.statusCode, 200);
    const { packages } = response.json() as { packages: Record<string, unknown>[] };
    assert.deepEqual(
      packages.map((p) => p.packageId),
      [REVISION_2_ID, PACKAGE_ID, QUEUED_ID],
    );
    const [rev2, rev1, queued] = packages;
    assert.deepEqual(rev1, {
      packageId: PACKAGE_ID,
      visitId: VISIT_ID,
      dealId: DEAL_ID,
      revision: 1,
      status: "verdict_ready",
      createdAt: "2026-10-17T15:06:10Z",
      sealedAt: MANIFEST.sealedAt,
      verdict: {
        verdictId: VERDICT.verdictId,
        outcome: VERDICT.outcome,
        evaluatedAt: VERDICT.evaluatedAt,
      },
    });
    assert.equal(rev2?.supersedesPackageId, PACKAGE_ID);
    assert.equal(rev2?.status, "uploading");
    assert.ok(!("sealedAt" in rev2!) && !("verdict" in rev2!));
    assert.equal(queued?.status, "checks_queued");
    assert.ok(!("verdict" in queued!) && !("supersedesPackageId" in queued!));
  });

  it("filters by visitId and returns an empty list for an unknown deal", async () => {
    const byVisit = await call(
      "listPackages",
      `/v1/packages?dealId=${DEAL_ID}&visitId=${VISIT_ID}`,
    );
    assert.deepEqual(
      (byVisit.json() as { packages: { packageId: string }[] }).packages.map((p) => p.packageId),
      [REVISION_2_ID, PACKAGE_ID],
    );
    const other = await call("listPackages", `/v1/packages?dealId=${OTHER_DEAL_ID}`, ["bim"]);
    assert.deepEqual(
      (other.json() as { packages: { packageId: string }[] }).packages.map((p) => p.packageId),
      [OTHER_DEAL_PACKAGE_ID, BROKEN_VERDICT_ID],
    );
    const none = await call("listPackages", "/v1/packages?dealId=HUB-none", ["admin"]);
    assert.deepEqual(none.json(), { packages: [] });
  });

  const queries: [string, Record<string, string | string[]>][] = [
    ["a deal", { dealId: DEAL_ID }],
    ["a deal and visit", { dealId: DEAL_ID, visitId: VISIT_ID }],
    ["the longest deal id", { dealId: "D".repeat(64) }],
    ["no dealId", {}],
    ["an empty dealId", { dealId: "" }],
    ["a 65-character dealId", { dealId: "D".repeat(65) }],
    ["a visitId that is not a uuid", { dealId: DEAL_ID, visitId: "visit-1" }],
    ["an uppercase visitId", { dealId: DEAL_ID, visitId: VISIT_ID.toUpperCase() }],
    ["an unknown parameter", { dealId: DEAL_ID, limit: "5" }],
    ["a repeated dealId", { dealId: [DEAL_ID, OTHER_DEAL_ID] }],
  ];

  for (const [label, query] of queries) {
    it(`accepts or rejects ${label} as the document does`, async () => {
      const search = new URLSearchParams();
      for (const [name, value] of Object.entries(query)) {
        for (const item of Array.isArray(value) ? value : [value]) {
          search.append(name, item);
        }
      }
      const response = await call("listPackages", `/v1/packages?${search.toString()}`);
      const expected = openapi.queryErrors("listPackages", query).length === 0 ? 200 : 400;
      assert.equal(response.statusCode, expected, response.body);
    });
  }
});

describe("getPackage", () => {
  it("returns a sealed package with files, manifest, capture record and verdict summary", async () => {
    const response = await call("getPackage", `/v1/packages/${PACKAGE_ID}`, ["bim"]);
    assert.equal(response.statusCode, 200);
    const body = response.json() as Record<string, unknown> & { files: Record<string, unknown>[] };
    assert.deepEqual(body.manifest, MANIFEST);
    assert.deepEqual(body.captureRecord, CAPTURE_RECORD);
    assert.deepEqual(body.verdict, {
      verdictId: VERDICT.verdictId,
      outcome: VERDICT.outcome,
      evaluatedAt: VERDICT.evaluatedAt,
    });
    assert.equal(body.files.length, MANIFEST.files.length);
    const paths = body.files.map((file) => String(file.path));
    assert.deepEqual(paths, [...paths].sort());
    const floorFile = body.files.find((file) => file.role === "plan_dxf");
    assert.deepEqual(floorFile, {
      path: "Original Exports/floor-1/3f6c2a9e-8b1d-4c57-9e2a-6d4b1f0c7a35/plan.dxf",
      role: "plan_dxf",
      captureId: "3f6c2a9e-8b1d-4c57-9e2a-6d4b1f0c7a35",
      areaKey: "floor-1",
      sha256: "2503b19c26ff845d3fa3b0c0988436a8abe944c056ca1247ab6ff391043779ab",
      bytes: 1258291,
      status: "verified",
      checkedAt: "2026-10-17T15:10:30Z",
    });
    assert.ok(!JSON.stringify(body).includes("blob"), "storage names are not exposed");
  });

  it("returns an uploading package without manifest, verdict or checkedAt on pending files", async () => {
    const response = await call("getPackage", `/v1/packages/${REVISION_2_ID}`);
    const body = response.json() as Record<string, unknown> & { files: Record<string, unknown>[] };
    for (const key of ["manifest", "captureRecord", "verdict", "sealedAt"]) {
      assert.ok(!(key in body), key);
    }
    const statuses = body.files.map((file) => file.status).sort();
    assert.deepEqual(statuses, [
      "bytes_mismatch",
      "not_uploaded",
      "pending",
      "sha256_mismatch",
      "verified",
    ]);
    const pending = body.files.find((file) => file.status === "pending");
    assert.ok(pending && !("checkedAt" in pending));
  });

  it("answers 404 for an unknown or malformed package id", async () => {
    for (const id of [UNKNOWN_ID, "not-a-uuid", PACKAGE_ID.toUpperCase()]) {
      const response = await call("getPackage", `/v1/packages/${id}`);
      assert.equal(response.statusCode, 404, id);
      assert.equal((response.json() as { code: string }).code, "not_found");
    }
  });
});

describe("getVerdict", () => {
  it("returns the stored verdict document unchanged", async () => {
    const response = await call("getVerdict", `/v1/packages/${PACKAGE_ID}/verdict`);
    assert.equal(response.statusCode, 200);
    assert.deepEqual(response.json(), VERDICT);
  });

  it("answers 404 verdict_not_ready until the checks have finished", async () => {
    for (const id of [QUEUED_ID, REVISION_2_ID]) {
      const response = await call("getVerdict", `/v1/packages/${id}/verdict`, ["bim"]);
      assert.equal(response.statusCode, 404);
      assert.equal((response.json() as { code: string }).code, "verdict_not_ready");
    }
  });

  it("answers 404 not_found for an unknown or malformed package id", async () => {
    for (const id of [UNKNOWN_ID, "nope"]) {
      const response = await call("getVerdict", `/v1/packages/${id}/verdict`);
      assert.equal(response.statusCode, 404);
      assert.equal((response.json() as { code: string }).code, "not_found");
    }
  });

  it("never serves a stored verdict that breaks the contract", async () => {
    const response = await station.app.inject({
      method: "GET",
      url: `/v1/packages/${BROKEN_VERDICT_ID}/verdict`,
      headers: await station.auth(["admin"]),
    });
    assert.equal(response.statusCode, 500);
    assert.equal((response.json() as { code: string }).code, "internal_error");
    assert.ok(station.logs.some((line) => line.includes("does not match the contract")));
  });
});

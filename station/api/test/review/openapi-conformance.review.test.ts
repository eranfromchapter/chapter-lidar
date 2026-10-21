// listReviewProjects and listReviewPackages (web-review §9.1 C and D, OpenAPI 1.1.0) match
// contract/openapi/station.yaml: routes and roles, query strings accepted or rejected as
// documented, every answer validates. Behaviour: one row per deal with packages and its newest
// package, ordering by the last package change, name and address from the HUB cache (also when
// expired), else the newest sealed capture record, else "HUB deal {dealId}", search by name,
// address, deal prefix and id prefixes, limit and truncated. The HUB lookup writes the cache
// through (hub/persist.ts). Runs against a throwaway Postgres.

import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";
import { OpenApi } from "../packages/openapi.js";
import {
  BROKEN_VERDICT_ID,
  CAPTURE_RECORD,
  DEAL_ID,
  FLOOR_2,
  MANIFEST,
  OTHER_DEAL_ID,
  OTHER_DEAL_PACKAGE_ID,
  PACKAGE_ID,
  QUEUED_ID,
  REVISION_2_ID,
  RETRIED_ID,
  filesOf,
  insertFile,
  insertPackage,
  seedRegistry,
  seedRetriedFile,
  startStation,
  type TestStation,
} from "../packages/support.js";

const openapi = new OpenApi();
let station: TestStation;

/** A deal without a cache row whose only package is sealed with a capture record. */
const RECORD_DEAL = "HUB-4004";
const RECORD_PACKAGE_ID = "6e7f8a9b-0c1d-4e2f-9a3b-4c5d6e7f8a9b";
const RECORD_VISIT_ID = "7f8a9b0c-1d2e-4f3a-8b4c-5d6e7f8a9b0c";
const RECORD_ADDRESS = "12 Example Lane, Testville, NY 10001";

type Roles = readonly ("capture" | "bim" | "admin")[];

interface ProjectRow {
  dealId: string;
  projectName?: string;
  address: { formatted: string };
  packageCount: number;
  latest: { packageId: string; updatedAt: string };
}

interface PackageRow {
  packageId: string;
  dealId: string;
  projectName?: string;
  address: { formatted: string };
}

async function get(
  operationId: "listReviewProjects" | "listReviewPackages",
  url: string,
  roles: Roles = ["bim"],
) {
  const response = await station.app.inject({
    method: "GET",
    url,
    headers: await station.auth(roles),
  });
  assert.deepEqual(openapi.responseErrors(operationId, response), [], response.body);
  return response;
}

async function projects(query = "", roles: Roles = ["bim"]) {
  const response = await get("listReviewProjects", `/v1/review/projects${query}`, roles);
  assert.equal(response.statusCode, 200, response.body);
  return response.json() as { projects: ProjectRow[]; truncated: boolean };
}

async function packages(query = "", roles: Roles = ["bim"]) {
  const response = await get("listReviewPackages", `/v1/review/packages${query}`, roles);
  assert.equal(response.statusCode, 200, response.body);
  return response.json() as { packages: PackageRow[]; truncated: boolean };
}

/** Moves a package's last change to now (any update of the row does). */
async function touch(packageId: string): Promise<void> {
  await station.db.query("UPDATE packages SET status = status WHERE package_id = $1", [packageId]);
}

before(async () => {
  station = await startStation();
  await seedRegistry(station.db);
  await seedRetriedFile(station.db);
  // The HUB cache knows DEAL_ID only, and its entry has expired.
  await station.db.query(
    `INSERT INTO projects_cache (deal_id, project_name, address_formatted, fetched_at, expires_at)
     VALUES ($1, 'Maverick penthouse', '424 West End Avenue, New York, NY 10024',
             now() - interval '2 hours', now() - interval '1 hour')`,
    [DEAL_ID],
  );
  const recordManifest = {
    ...MANIFEST,
    packageId: RECORD_PACKAGE_ID,
    visitId: RECORD_VISIT_ID,
    files: MANIFEST.files.slice(0, 2),
  };
  await insertPackage(
    station.db,
    {
      packageId: RECORD_PACKAGE_ID,
      visitId: RECORD_VISIT_ID,
      dealId: RECORD_DEAL,
      revision: 1,
      status: "checks_queued",
      createdAt: "2026-10-14T09:00:00.000Z",
      sealed: { manifest: recordManifest, captureRecord: CAPTURE_RECORD },
    },
    filesOf(recordManifest),
  );
  for (const file of filesOf(recordManifest)) {
    await insertFile(station.db, RECORD_PACKAGE_ID, file, "verified");
  }
});

after(async () => {
  await station?.close();
});

describe("review routes", () => {
  for (const operationId of ["listReviewProjects", "listReviewPackages"]) {
    it(`${operationId} is routed with the documented roles`, () => {
      const op = openapi.operation(operationId);
      const route = station.app.routeAccess.find(
        (access) => access.url === op.routeUrl && access.method.split(",").includes(op.method),
      );
      assert.ok(route, `no route for ${op.method} ${op.routeUrl}`);
      assert.deepEqual([...route.roles].sort(), [...op.roles].sort());
    });
  }

  it("answer 401 without a token and 403 without a station role", async () => {
    for (const [operationId, url] of [
      ["listReviewProjects", "/v1/review/projects"],
      ["listReviewPackages", "/v1/review/packages"],
    ] as const) {
      const anonymous = await station.app.inject({ method: "GET", url });
      assert.equal(anonymous.statusCode, 401);
      assert.deepEqual(openapi.responseErrors(operationId, anonymous), []);
      const noRole = await station.app.inject({
        method: "GET",
        url,
        headers: { authorization: `Bearer ${await station.issuer.mint({ roles: [] })}` },
      });
      assert.equal(noRole.statusCode, 403);
      assert.deepEqual(openapi.responseErrors(operationId, noRole), []);
    }
  });
});

describe("listReviewProjects", () => {
  it("lists one row per deal with packages, its count and its newest package", async () => {
    const { projects: rows, truncated } = await projects("", ["capture"]);
    assert.equal(truncated, false);
    const byDeal = new Map(rows.map((row) => [row.dealId, row]));
    assert.deepEqual(
      [...byDeal.keys()].sort(),
      [DEAL_ID, OTHER_DEAL_ID, "HUB-3003", RECORD_DEAL].sort(),
    );
    assert.equal(byDeal.get(DEAL_ID)?.packageCount, 3);
    assert.equal(byDeal.get(DEAL_ID)?.latest.packageId, REVISION_2_ID);
    assert.equal(byDeal.get(OTHER_DEAL_ID)?.packageCount, 2);
    assert.equal(byDeal.get(OTHER_DEAL_ID)?.latest.packageId, OTHER_DEAL_PACKAGE_ID);
    assert.equal(byDeal.get("HUB-3003")?.latest.packageId, RETRIED_ID);
  });

  it("names projects from the cache, else the newest capture record, else the deal", async () => {
    const byDeal = new Map((await projects()).projects.map((row) => [row.dealId, row]));
    const name = (dealId: string) => {
      const row = byDeal.get(dealId);
      return { projectName: row?.projectName, address: row?.address.formatted };
    };
    assert.deepEqual(name(DEAL_ID), {
      projectName: "Maverick penthouse",
      address: "424 West End Avenue, New York, NY 10024",
    });
    assert.deepEqual(name(RECORD_DEAL), {
      projectName: "12 Example Lane",
      address: RECORD_ADDRESS,
    });
    assert.deepEqual(name(OTHER_DEAL_ID), {
      projectName: undefined,
      address: `HUB deal ${OTHER_DEAL_ID}`,
    });
    assert.ok(!("projectName" in byDeal.get(OTHER_DEAL_ID)!));
  });

  it("orders projects by their most recent package change", async () => {
    await touch(QUEUED_ID);
    assert.equal((await projects()).projects[0]?.dealId, DEAL_ID);
    await touch(BROKEN_VERDICT_ID);
    const rows = (await projects()).projects;
    assert.equal(rows[0]?.dealId, OTHER_DEAL_ID);
    // The latest package stays the newest one, whatever changed last.
    assert.equal(rows[0]?.latest.packageId, OTHER_DEAL_PACKAGE_ID);
    const changes = rows.map((row) => row.dealId);
    await station.db.query(
      "INSERT INTO hub_publications (package_id, status) VALUES ($1, 'pending')",
      [RECORD_PACKAGE_ID],
    );
    assert.deepEqual(
      (await projects()).projects.map((row) => row.dealId),
      [RECORD_DEAL, ...changes.filter((deal) => deal !== RECORD_DEAL)],
    );
  });

  const searches: [string, string, string[]][] = [
    ["part of a cached address, any case", "WEST END", [DEAL_ID]],
    ["part of a cached name", "penthouse", [DEAL_ID]],
    // PACKAGE_ID's capture record names the same address.
    ["part of a capture record address", "example lane", [DEAL_ID, RECORD_DEAL]],
    ["the start of a deal id, any case", "hub-20", [OTHER_DEAL_ID]],
    ["a package id prefix of 8 hex characters", RECORD_PACKAGE_ID.slice(0, 8), [RECORD_DEAL]],
    ["a whole package id", OTHER_DEAL_PACKAGE_ID, [OTHER_DEAL_ID]],
    ["a capture id prefix", FLOOR_2.captureId.slice(0, 13), [DEAL_ID]],
    ["7 hex characters (too short for an id)", RECORD_PACKAGE_ID.slice(0, 7), []],
    ["a deal id in the middle", "UB-10", []],
    ["nothing known", "nowhere at all", []],
    ["LIKE wildcards as text", "%", []],
  ];
  for (const [label, q, expected] of searches) {
    it(`finds projects by ${label}`, async () => {
      const rows = (await projects(`?q=${encodeURIComponent(q)}`)).projects;
      assert.deepEqual(rows.map((row) => row.dealId).sort(), [...expected].sort());
    });
  }

  it("stops at limit and says the list is truncated", async () => {
    const all = (await projects()).projects;
    const page = await projects("?limit=2");
    assert.equal(page.truncated, true);
    assert.deepEqual(
      page.projects.map((row) => row.dealId),
      all.slice(0, 2).map((row) => row.dealId),
    );
    assert.equal((await projects(`?limit=${all.length}`)).truncated, false);
  });

  const queries: [string, Record<string, string>][] = [
    ["no parameters", {}],
    ["q and limit", { q: "west", limit: "5" }],
    ["a 200-character q", { q: "q".repeat(200) }],
    ["a 201-character q", { q: "q".repeat(201) }],
    ["an empty q", { q: "" }],
    ["limit 0", { limit: "0" }],
    ["limit 201", { limit: "201" }],
    ["a limit that is not a number", { limit: "many" }],
    ["an unknown parameter", { dealId: DEAL_ID }],
  ];
  for (const [label, query] of queries) {
    it(`accepts or rejects ${label} as the document does`, async () => {
      const response = await get(
        "listReviewProjects",
        `/v1/review/projects?${new URLSearchParams(query).toString()}`,
      );
      const expected = openapi.queryErrors("listReviewProjects", query).length === 0 ? 200 : 400;
      assert.equal(response.statusCode, expected, response.body);
    });
  }
});

describe("listReviewPackages", () => {
  it("lists every package newest first with its project's name and address", async () => {
    const { packages: rows, truncated } = await packages("", ["capture"]);
    assert.equal(truncated, false);
    const ordered = await station.db.query<{ package_id: string }>(
      "SELECT package_id FROM packages ORDER BY created_at DESC, revision DESC, package_id",
    );
    assert.deepEqual(
      rows.map((row) => row.packageId),
      ordered.rows.map((row) => row.package_id),
    );
    const byId = new Map(rows.map((row) => [row.packageId, row]));
    assert.equal(byId.get(PACKAGE_ID)?.projectName, "Maverick penthouse");
    assert.equal(byId.get(QUEUED_ID)?.address.formatted, "424 West End Avenue, New York, NY 10024");
    assert.equal(byId.get(RECORD_PACKAGE_ID)?.address.formatted, RECORD_ADDRESS);
    assert.equal(byId.get(OTHER_DEAL_PACKAGE_ID)?.address.formatted, `HUB deal ${OTHER_DEAL_ID}`);
  });

  it("matches a project's text for all its packages, an id prefix for that package only", async () => {
    const byText = (await packages("?q=penthouse")).packages.map((row) => row.packageId);
    assert.deepEqual(byText.sort(), [PACKAGE_ID, QUEUED_ID, REVISION_2_ID].sort());
    const byId = (await packages(`?q=${QUEUED_ID.slice(0, 8)}`)).packages.map(
      (row) => row.packageId,
    );
    assert.deepEqual(byId, [QUEUED_ID]);
  });

  it("stops at limit and says the list is truncated", async () => {
    const page = await packages("?limit=1");
    assert.equal(page.packages.length, 1);
    assert.equal(page.truncated, true);
  });

  const queries: [string, Record<string, string>][] = [
    ["no parameters", {}],
    ["limit 200", { limit: "200" }],
    ["limit 201", { limit: "201" }],
    ["an unknown parameter", { visitId: RECORD_VISIT_ID }],
  ];
  for (const [label, query] of queries) {
    it(`accepts or rejects ${label} as the document does`, async () => {
      const response = await get(
        "listReviewPackages",
        `/v1/review/packages?${new URLSearchParams(query).toString()}`,
      );
      const expected = openapi.queryErrors("listReviewPackages", query).length === 0 ? 200 : 400;
      assert.equal(response.statusCode, expected, response.body);
    });
  }
});

describe("the HUB project cache feeds the review lists", () => {
  it("stores every project the HUB returns, and the lists use its name", async () => {
    const listed = await station.app.inject({
      method: "GET",
      url: "/v1/projects",
      headers: await station.auth(["capture"]),
    });
    assert.equal(listed.statusCode, 200, listed.body);
    const cached = await station.db.query<{ deal_id: string; project_name: string }>(
      "SELECT deal_id, project_name FROM projects_cache WHERE deal_id LIKE 'fixture-deal-%' ORDER BY deal_id",
    );
    assert.deepEqual(cached.rows, [
      { deal_id: "fixture-deal-0001", project_name: "Fixture project" },
      { deal_id: "fixture-deal-0002", project_name: "Fixture second project" },
    ]);
    const packageId = "8a9b0c1d-2e3f-4a4b-9c5d-6e7f8a9b0c1d";
    await insertPackage(
      station.db,
      {
        packageId,
        visitId: "9b0c1d2e-3f4a-4b5c-8d6e-7f8a9b0c1d2e",
        dealId: "fixture-deal-0002",
        revision: 1,
        status: "uploading",
        createdAt: "2026-10-20T10:00:00.000Z",
      },
      filesOf(MANIFEST).slice(0, 1),
    );
    const row = (await projects("?q=fixture-deal-0002")).projects[0];
    assert.equal(row?.projectName, "Fixture second project");
    assert.equal(row?.address.formatted, "200 Sample Avenue, Testville, NY 00000");
  });
});

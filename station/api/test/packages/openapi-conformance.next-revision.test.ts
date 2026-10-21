// putNextRevisionNotice (phone-package §10.2/§10.4, OpenAPI 1.1.0) matches
// contract/openapi/station.yaml: the route has the documented roles, bodies are accepted or
// rejected exactly as NextRevisionNoticeInput says, every documented answer is produced and
// validates, the notice is stored with who sent it and returned as Package.nextRevision, and
// every store is audited. (Its removal when the superseding session opens is in
// test/uploads/carry-over.test.ts, which has blob storage.) Runs against a throwaway Postgres.

import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";
import { OpenApi } from "./openapi.js";
import {
  BIM_NAME,
  BIM_OID,
  PACKAGE_ID,
  QUEUED_ID,
  REVISION_2_ID,
  UNKNOWN_ID,
  seedRegistry,
  startStation,
  type TestStation,
} from "./support.js";

const openapi = new OpenApi();
const OPERATION = "putNextRevisionNotice";
let station: TestStation;
const produced = new Set<number>();

before(async () => {
  station = await startStation();
  await seedRegistry(station.db);
});

after(async () => {
  await station?.close();
});

type Roles = readonly ("capture" | "bim" | "admin")[];

async function put(packageId: string, body: unknown, roles: Roles = ["capture"]) {
  const response = await station.app.inject({
    method: "PUT",
    url: `/v1/packages/${packageId}/next-revision`,
    headers: { ...(await station.auth(roles)), "content-type": "application/json" },
    payload: JSON.stringify(body),
  });
  assert.deepEqual(openapi.responseErrors(OPERATION, response), [], response.body);
  produced.add(response.statusCode);
  return response;
}

const drawn = {
  revision: 2,
  updatedAt: "2026-05-16T15:40:00Z",
  changes: [
    {
      kind: "added",
      subject: "capture",
      title: "Primary closet",
      detail: "Room · 3 files",
      answersNextAction: "Scan the primary closet once it is unlocked.",
    },
    {
      method: "tape",
      detail: "Ceiling height · 2,490 mm · 8' 2\"",
      title: "Room 4 ceiling height",
      subject: "field_control",
      kind: "added",
    },
    { kind: "added", subject: "photos", title: "3 photos", detail: "Primary closet" },
  ],
};

describe("putNextRevisionNotice is implemented as documented", () => {
  it("is routed with the documented roles", () => {
    const op = openapi.operation(OPERATION);
    const route = station.app.routeAccess.find(
      (access) => access.url === op.routeUrl && access.method.split(",").includes(op.method),
    );
    assert.ok(route, `no route for ${op.method} ${op.routeUrl}`);
    assert.deepEqual([...route.roles].sort(), [...op.roles].sort());
  });

  it("stores the notice with who sent it and returns it, changes in the documented field order", async () => {
    const response = await put(QUEUED_ID, drawn);
    assert.equal(response.statusCode, 200, response.body);
    const expected = {
      revision: 2,
      updatedAt: drawn.updatedAt,
      updatedBy: BIM_NAME,
      changes: [
        drawn.changes[0],
        {
          kind: "added",
          subject: "field_control",
          title: "Room 4 ceiling height",
          detail: "Ceiling height · 2,490 mm · 8' 2\"",
          method: "tape",
        },
        drawn.changes[2],
      ],
    };
    assert.deepEqual(response.json(), expected);
    assert.equal(JSON.stringify(response.json()), JSON.stringify(expected));

    const pkg = await station.app.inject({
      method: "GET",
      url: `/v1/packages/${QUEUED_ID}`,
      headers: await station.auth(["bim"]),
    });
    assert.deepEqual(openapi.responseErrors("getPackage", pkg), []);
    assert.deepEqual((pkg.json() as { nextRevision?: unknown }).nextRevision, expected);
  });

  it("replaces the stored notice on every PUT and audits each one", async () => {
    const second = { revision: 2, updatedAt: "2026-05-16T15:45:10Z", changes: [] };
    const response = await put(QUEUED_ID, second, ["admin"]);
    assert.equal(response.statusCode, 200, response.body);
    assert.deepEqual(response.json(), { ...second, updatedBy: BIM_NAME });
    const rows = await station.db.query<{ notice: unknown; updated_by_id: string }>(
      "SELECT notice, updated_by_id FROM next_revision_notices WHERE package_id = $1",
      [QUEUED_ID],
    );
    assert.deepEqual(rows.rows, [{ notice: second, updated_by_id: BIM_OID }]);
    const audits = await station.db.query<{ details: Record<string, unknown> }>(
      `SELECT details FROM audit_log WHERE action = 'package.next_revision' AND target_id = $1
        ORDER BY audit_id`,
      [QUEUED_ID],
    );
    assert.deepEqual(
      audits.rows.map((row) => row.details),
      [
        { revision: 2, updatedAt: drawn.updatedAt, changes: 3 },
        { revision: 2, updatedAt: second.updatedAt, changes: 0 },
      ],
    );
  });

  it("answers 409 package_not_sealed while the package is uploading", async () => {
    const response = await put(REVISION_2_ID, { ...drawn, revision: 3 });
    assert.equal(response.statusCode, 409);
    assert.equal((response.json() as { code: string }).code, "package_not_sealed");
  });

  it("answers 409 revision_exists once a package supersedes it", async () => {
    const response = await put(PACKAGE_ID, drawn);
    assert.equal(response.statusCode, 409);
    assert.equal((response.json() as { code: string }).code, "revision_exists");
  });

  it("answers 422 revision_mismatch when the revision is not the next one", async () => {
    const response = await put(QUEUED_ID, { ...drawn, revision: 3 });
    assert.equal(response.statusCode, 422);
    const problem = response.json() as { code: string; errors: { pointer: string }[] };
    assert.equal(problem.code, "revision_mismatch");
    assert.deepEqual(
      problem.errors.map((error) => error.pointer),
      ["/revision"],
    );
  });

  it("answers 404 for an unknown or malformed package id", async () => {
    for (const id of [UNKNOWN_ID, "nope", QUEUED_ID.toUpperCase()]) {
      const response = await put(id, drawn);
      assert.equal(response.statusCode, 404, id);
      assert.equal((response.json() as { code: string }).code, "not_found");
    }
  });

  it("answers 403 for the bim role and 401 without a token, storing nothing", async () => {
    const before = await station.db.query("SELECT notice FROM next_revision_notices");
    const forbidden = await put(QUEUED_ID, drawn, ["bim"]);
    assert.equal(forbidden.statusCode, 403);
    const anonymous = await station.app.inject({
      method: "PUT",
      url: `/v1/packages/${QUEUED_ID}/next-revision`,
      headers: { "content-type": "application/json" },
      payload: JSON.stringify(drawn),
    });
    assert.equal(anonymous.statusCode, 401);
    assert.deepEqual(openapi.responseErrors(OPERATION, anonymous), []);
    produced.add(anonymous.statusCode);
    const afterRows = await station.db.query("SELECT notice FROM next_revision_notices");
    assert.deepEqual(afterRows.rows, before.rows);
  });

  const change = drawn.changes[2]!;
  const bodies: [string, unknown][] = [
    ["the drawn notice", drawn],
    ["no changes", { ...drawn, changes: [] }],
    ["50 changes", { ...drawn, changes: Array.from({ length: 50 }, () => change) }],
    ["51 changes", { ...drawn, changes: Array.from({ length: 51 }, () => change) }],
    ["revision 1", { ...drawn, revision: 1 }],
    ["a revision that is not an integer", { ...drawn, revision: 2.5 }],
    ["a revision as text", { ...drawn, revision: "2" }],
    ["no updatedAt", { revision: 2, changes: [] }],
    ["an updatedAt with milliseconds", { ...drawn, updatedAt: "2026-05-16T15:40:00.123Z" }],
    ["an updatedAt with an offset", { ...drawn, updatedAt: "2026-05-16T11:40:00-04:00" }],
    ["updatedBy from the client", { ...drawn, updatedBy: "Someone Else" }],
    ["an unknown kind", { ...drawn, changes: [{ ...change, kind: "moved" }] }],
    ["an unknown subject", { ...drawn, changes: [{ ...change, subject: "rooms" }] }],
    ["an empty title", { ...drawn, changes: [{ ...change, title: "" }] }],
    ["a 201-character title", { ...drawn, changes: [{ ...change, title: "t".repeat(201) }] }],
    ["a 300-character detail", { ...drawn, changes: [{ ...change, detail: "d".repeat(300) }] }],
    ["a 301-character detail", { ...drawn, changes: [{ ...change, detail: "d".repeat(301) }] }],
    [
      "a 501-character answersNextAction",
      { ...drawn, changes: [{ ...change, answersNextAction: "a".repeat(501) }] },
    ],
    ["a method that is not tape or laser", { ...drawn, changes: [{ ...change, method: "eye" }] }],
    ["an unknown change property", { ...drawn, changes: [{ ...change, room: "Room 4" }] }],
    ["a change without detail", { ...drawn, changes: [{ ...change, detail: undefined }] }],
    ["a list as body", [drawn]],
    ["null as body", null],
  ];

  for (const [label, body] of bodies) {
    it(`accepts or rejects ${label} as the document's schema does`, async () => {
      const normalized = JSON.parse(JSON.stringify(body)) as unknown;
      const schemaErrors = openapi.requestBodyErrors(OPERATION, normalized);
      const response = await put(QUEUED_ID, normalized);
      if (schemaErrors.length === 0) {
        assert.equal(response.statusCode, 200, response.body);
      } else {
        assert.equal(response.statusCode, 400, `${schemaErrors.join("; ")} -> ${response.body}`);
        assert.equal((response.json() as { code: string }).code, "invalid_request");
      }
    });
  }

  it("produced every documented status", () => {
    const documented = Object.keys(
      openapi.operation(OPERATION).node.responses as Record<string, unknown>,
    ).sort();
    assert.deepEqual([...produced].map(String).sort(), documented);
  });
});

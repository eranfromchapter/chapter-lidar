// F7 AC6 (modeling decisions area): listModelingDecisions, createModelingDecision and (1.1.0)
// listAllModelingDecisions match contract/openapi/station.yaml: the routes exist with the
// documented roles, request bodies and query strings are accepted or rejected exactly as the
// document says, and every response validates against the document. Also covers the
// cross-field rules (422), the recorded author and time, the audit row, the append-only log
// and the review screen's list across packages (newest first, deal filter, limit).
// Runs against a throwaway Postgres.

import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";
import { OpenApi } from "./openapi.js";
import {
  BIM_NAME,
  BIM_OID,
  BROKEN_VERDICT_ID,
  CAPTURE_MODEL_PATH,
  DEAL_ID,
  MANIFEST,
  OTHER_DEAL_ID,
  FIELD_CONTROLS_PATH,
  FLOOR_1,
  FLOOR_2,
  PACKAGE_ID,
  PLAN_DXF_PATH,
  QUEUED_ID,
  REVISION_2_ID,
  UNKNOWN_ID,
  filesOf,
  insertFile,
  seedRegistry,
  startStation,
  type TestStation,
} from "./support.js";

const openapi = new OpenApi();
let station: TestStation;

before(async () => {
  station = await startStation();
  await seedRegistry(station.db);
});

after(async () => {
  await station?.close();
});

type Roles = readonly ("capture" | "bim" | "admin")[];

async function list(packageId: string, roles: Roles = ["bim"]) {
  const response = await station.app.inject({
    method: "GET",
    url: `/v1/packages/${packageId}/modeling-decisions`,
    headers: await station.auth(roles),
  });
  assert.deepEqual(openapi.responseErrors("listModelingDecisions", response), [], response.body);
  return response;
}

async function create(packageId: string, body: unknown, roles: Roles = ["bim"]) {
  const response = await station.app.inject({
    method: "POST",
    url: `/v1/packages/${packageId}/modeling-decisions`,
    headers: { ...(await station.auth(roles)), "content-type": "application/json" },
    payload: JSON.stringify(body),
  });
  assert.deepEqual(openapi.responseErrors("createModelingDecision", response), [], response.body);
  return response;
}

const minimal = {
  element: "Floor 1 kitchen north wall",
  decision: "Wall length taken from tape distance A.",
  sources: [{ path: FIELD_CONTROLS_PATH, controlId: "dist-a" }],
};

const full = {
  element: "Floor 1 living room south window",
  decision: "Window width from the capture model, checked against photo 14.",
  captureId: FLOOR_1.captureId,
  areaKey: FLOOR_1.areaKey,
  sources: [
    { path: CAPTURE_MODEL_PATH, elementId: "window-3" },
    { path: PLAN_DXF_PATH },
    { path: FIELD_CONTROLS_PATH, controlId: "open-2" },
  ],
  note: "Confirm sill height on the next visit.",
};

describe("modeling decisions area implements its OpenAPI operations", () => {
  for (const operationId of [
    "listModelingDecisions",
    "createModelingDecision",
    "listAllModelingDecisions",
  ]) {
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

describe("createModelingDecision", () => {
  it("logs a decision with the signed-in author and time, and audits it", async () => {
    const before = Math.floor(Date.now() / 1000) * 1000;
    const response = await create(PACKAGE_ID, full);
    assert.equal(response.statusCode, 201);
    const body = response.json() as Record<string, unknown>;
    const { decisionId, decidedAt, ...rest } = body;
    assert.match(String(decisionId), /^[0-9a-f-]{36}$/);
    const decidedMs = Date.parse(String(decidedAt));
    assert.ok(decidedMs >= before && decidedMs <= Date.now() + 1000, String(decidedAt));
    assert.deepEqual(rest, {
      packageId: PACKAGE_ID,
      ...full,
      decidedBy: { name: BIM_NAME, userId: BIM_OID },
    });

    const audit = await station.db.query<{
      actor_id: string;
      action: string;
      target_type: string;
      details: Record<string, unknown>;
    }>("SELECT actor_id, action, target_type, details FROM audit_log WHERE target_id = $1", [
      decisionId,
    ]);
    assert.equal(audit.rows.length, 1);
    assert.deepEqual(audit.rows[0], {
      actor_id: BIM_OID,
      action: "modeling_decision.create",
      target_type: "modeling_decision",
      details: { packageId: PACKAGE_ID, captureId: FLOOR_1.captureId, sourceCount: 3 },
    });
  });

  it("ignores client attempts to set the author (unknown properties are rejected)", async () => {
    const response = await create(PACKAGE_ID, {
      ...minimal,
      decidedBy: { name: "Someone Else", userId: "x" },
    });
    assert.equal(response.statusCode, 400);
  });

  const bodies: [string, unknown][] = [
    ["the minimal body", minimal],
    ["the full body", full],
    ["the longest element", { ...minimal, element: "e".repeat(300) }],
    ["no element", { decision: minimal.decision, sources: minimal.sources }],
    ["an empty element", { ...minimal, element: "" }],
    ["a 301-character element", { ...minimal, element: "e".repeat(301) }],
    ["a 2001-character decision", { ...minimal, decision: "d".repeat(2001) }],
    ["an empty note", { ...minimal, note: "" }],
    ["no sources", { element: minimal.element, decision: minimal.decision }],
    ["an empty sources list", { ...minimal, sources: [] }],
    ["a source without path", { ...minimal, sources: [{ controlId: "dist-a" }] }],
    ["an absolute source path", { ...minimal, sources: [{ path: "/etc/passwd" }] }],
    ["a source path with ..", { ...minimal, sources: [{ path: "a/../b" }] }],
    ["an unknown source property", { ...minimal, sources: [{ path: PLAN_DXF_PATH, page: 1 }] }],
    [
      "a 129-character controlId",
      { ...minimal, sources: [{ path: FIELD_CONTROLS_PATH, controlId: "c".repeat(129) }] },
    ],
    ["a captureId that is not a uuid", { ...minimal, captureId: "floor-1", areaKey: "floor-1" }],
    ["an areaKey with capitals", { ...minimal, captureId: FLOOR_1.captureId, areaKey: "Floor-1" }],
    ["an unknown property", { ...minimal, status: "final" }],
    ["a number as element", { ...minimal, element: 5 }],
    ["a boolean as note", { ...minimal, note: true }],
    ["one source object instead of a list", { ...minimal, sources: { path: PLAN_DXF_PATH } }],
    ["a string as sources", { ...minimal, sources: PLAN_DXF_PATH }],
    ["a list as body", [minimal]],
    ["null as body", null],
  ];

  for (const [label, body] of bodies) {
    it(`accepts or rejects ${label} as the document's schema does`, async () => {
      const schemaErrors = openapi.requestBodyErrors("createModelingDecision", body);
      const response = await create(PACKAGE_ID, body);
      if (schemaErrors.length === 0) {
        assert.equal(response.statusCode, 201, response.body);
      } else {
        assert.equal(response.statusCode, 400, `${schemaErrors.join("; ")} -> ${response.body}`);
        assert.equal((response.json() as { code: string }).code, "invalid_request");
      }
    });
  }

  it("answers 400 for a body that is not JSON", async () => {
    const response = await station.app.inject({
      method: "POST",
      url: `/v1/packages/${PACKAGE_ID}/modeling-decisions`,
      headers: { ...(await station.auth(["bim"])), "content-type": "application/json" },
      payload: "{not json",
    });
    assert.deepEqual(openapi.responseErrors("createModelingDecision", response), []);
    assert.equal(response.statusCode, 400);
  });

  const ruleBreaks: [string, Record<string, unknown>, string[]][] = [
    ["captureId without areaKey", { ...minimal, captureId: FLOOR_1.captureId }, ["/areaKey"]],
    ["areaKey without captureId", { ...minimal, areaKey: FLOOR_1.areaKey }, ["/captureId"]],
    [
      "a capture paired with the wrong area",
      { ...minimal, captureId: FLOOR_1.captureId, areaKey: FLOOR_2.areaKey },
      ["/captureId"],
    ],
    [
      "a capture that is not in the package",
      { ...minimal, captureId: "9a8b7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d", areaKey: "floor-9" },
      ["/captureId"],
    ],
    [
      "a source path that is not a file of the package",
      { ...minimal, sources: [{ path: PLAN_DXF_PATH }, { path: "Original Exports/nope.dxf" }] },
      ["/sources/1/path"],
    ],
    [
      "a controlId on a file that is not the field controls",
      { ...minimal, sources: [{ path: PLAN_DXF_PATH, controlId: "dist-a" }] },
      ["/sources/0/controlId"],
    ],
    [
      "an elementId on a file that is not a capture model",
      { ...minimal, sources: [{ path: FIELD_CONTROLS_PATH, elementId: "wall-1" }] },
      ["/sources/0/elementId"],
    ],
  ];

  for (const [label, body, pointers] of ruleBreaks) {
    it(`answers 422 for ${label}`, async () => {
      assert.deepEqual(openapi.requestBodyErrors("createModelingDecision", body), []);
      const response = await create(PACKAGE_ID, body);
      assert.equal(response.statusCode, 422, response.body);
      const problem = response.json() as { code: string; errors: { pointer: string }[] };
      assert.equal(problem.code, "decision_rule_violation");
      assert.deepEqual(
        problem.errors.map((error) => error.pointer),
        pointers,
      );
    });
  }

  it("answers 404 for an unknown or malformed package id", async () => {
    for (const id of [UNKNOWN_ID, "nope"]) {
      const response = await create(id, minimal);
      assert.equal(response.statusCode, 404, id);
      assert.equal((response.json() as { code: string }).code, "not_found");
    }
  });

  it("writes nothing when the decision is rejected", async () => {
    const count = async () =>
      Number(
        (await station.db.query<{ n: number }>("SELECT count(*) AS n FROM modeling_decisions"))
          .rows[0]?.n,
      );
    const auditCount = async () =>
      Number(
        (
          await station.db.query<{ n: number }>(
            "SELECT count(*) AS n FROM audit_log WHERE action = 'modeling_decision.create'",
          )
        ).rows[0]?.n,
      );
    const [decisions, audits] = [await count(), await auditCount()];
    await create(PACKAGE_ID, { ...minimal, areaKey: "floor-1" });
    await create(UNKNOWN_ID, minimal);
    assert.equal(await count(), decisions);
    assert.equal(await auditCount(), audits);
  });
});

describe("listModelingDecisions", () => {
  it("lists the package's decisions oldest first and nothing of other packages", async () => {
    const first = await create(QUEUED_ID, {
      element: "Floor 1 hall",
      decision: "First.",
      sources: [
        { path: "Source Register/7c4e1b9a-2d3f-4a68-9b5c-e0f1a2b3c4d5/capture-record.json" },
      ],
    });
    assert.equal(first.statusCode, 201, first.body);
    const second = await create(
      QUEUED_ID,
      {
        element: "Floor 1 hall",
        decision: "Second.",
        sources: [
          { path: "Source Register/7c4e1b9a-2d3f-4a68-9b5c-e0f1a2b3c4d5/capture-record.json" },
        ],
      },
      ["admin"],
    );
    assert.equal(second.statusCode, 201, second.body);

    const response = await list(QUEUED_ID, ["admin"]);
    assert.equal(response.statusCode, 200);
    const { decisions } = response.json() as { decisions: Record<string, unknown>[] };
    assert.deepEqual(
      decisions.map((d) => d.decision),
      ["First.", "Second."],
    );
    assert.deepEqual(decisions[0], first.json());
    assert.ok(decisions.every((d) => d.packageId === QUEUED_ID));
  });

  it("returns an empty list for a package without decisions", async () => {
    const response = await list(REVISION_2_ID);
    assert.deepEqual(response.json(), { decisions: [] });
  });

  it("answers 404 for an unknown or malformed package id", async () => {
    for (const id of [UNKNOWN_ID, "nope"]) {
      const response = await list(id);
      assert.equal(response.statusCode, 404, id);
    }
  });

  it("keeps decisions append-only", async () => {
    await assert.rejects(
      station.db.query("UPDATE modeling_decisions SET decision = 'changed'"),
      /append-only/,
    );
    await assert.rejects(station.db.query("DELETE FROM modeling_decisions"), /append-only/);
  });
});

describe("listAllModelingDecisions", () => {
  type Decision = Record<string, unknown> & { decisionId: string; decidedAt: string };

  async function listAll(query = "", roles: Roles = ["bim"]) {
    const response = await station.app.inject({
      method: "GET",
      url: `/v1/modeling-decisions${query}`,
      headers: await station.auth(roles),
    });
    assert.deepEqual(
      openapi.responseErrors("listAllModelingDecisions", response),
      [],
      response.body,
    );
    return response;
  }

  let otherDeal: Decision;

  before(async () => {
    await insertFile(station.db, BROKEN_VERDICT_ID, filesOf(MANIFEST)[0]!, "verified");
    const created = await create(BROKEN_VERDICT_ID, {
      element: "Other deal hall",
      decision: "Taken from the plan.",
      sources: [{ path: MANIFEST.files[0]!.path }],
    });
    assert.equal(created.statusCode, 201, created.body);
    otherDeal = created.json() as Decision;
  });

  it("lists decisions of every package newest first, with each package's deal and revision", async () => {
    const response = await listAll();
    assert.equal(response.statusCode, 200);
    const { decisions, truncated } = response.json() as {
      decisions: Decision[];
      truncated: boolean;
    };
    assert.equal(truncated, false);
    const all = await station.db.query<{ n: number }>(
      "SELECT count(*) AS n FROM modeling_decisions",
    );
    assert.equal(decisions.length, all.rows[0]?.n);
    const times = decisions.map((decision) => Date.parse(decision.decidedAt));
    assert.deepEqual(
      times,
      [...times].sort((a, b) => b - a),
    );
    const { decisionId, packageId, ...rest } = otherDeal;
    assert.deepEqual(decisions[0], {
      decisionId,
      packageId,
      dealId: OTHER_DEAL_ID,
      revision: 1,
      ...rest,
    });
    assert.equal(
      JSON.stringify(Object.keys(decisions[0]!).slice(0, 4)),
      JSON.stringify(["decisionId", "packageId", "dealId", "revision"]),
    );
  });

  it("filters by dealId", async () => {
    const response = await listAll(`?dealId=${DEAL_ID}`, ["admin"]);
    const { decisions } = response.json() as { decisions: Decision[] };
    assert.ok(decisions.length > 0);
    assert.ok(decisions.every((decision) => decision.dealId === DEAL_ID));
    assert.ok(!decisions.some((decision) => decision.decisionId === otherDeal.decisionId));
    const none = await listAll("?dealId=HUB-none");
    assert.deepEqual(none.json(), { decisions: [], truncated: false });
  });

  it("stops at limit and says the list is truncated", async () => {
    const page = (await listAll("?limit=1")).json() as {
      decisions: Decision[];
      truncated: boolean;
    };
    assert.equal(page.truncated, true);
    assert.deepEqual(
      page.decisions.map((decision) => decision.decisionId),
      [otherDeal.decisionId],
    );
  });

  it("answers 403 for the capture role", async () => {
    const response = await listAll("", ["capture"]);
    assert.equal(response.statusCode, 403);
  });

  const queries: [string, Record<string, string>][] = [
    ["no parameters", {}],
    ["a deal", { dealId: DEAL_ID }],
    ["limit 200", { limit: "200" }],
    ["limit 0", { limit: "0" }],
    ["limit 201", { limit: "201" }],
    ["a limit that is not a number", { limit: "ten" }],
    ["an empty dealId", { dealId: "" }],
    ["a 65-character dealId", { dealId: "D".repeat(65) }],
    ["an unknown parameter", { packageId: PACKAGE_ID }],
  ];
  for (const [label, query] of queries) {
    it(`accepts or rejects ${label} as the document does`, async () => {
      const response = await listAll(`?${new URLSearchParams(query).toString()}`);
      const expected =
        openapi.queryErrors("listAllModelingDecisions", query).length === 0 ? 200 : 400;
      assert.equal(response.statusCode, expected, response.body);
    });
  }
});

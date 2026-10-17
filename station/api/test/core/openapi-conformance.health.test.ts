// F7 AC6 for the core area: getHealth is implemented with the path, method, access rule and
// response schemas of contract/openapi/station.yaml.
//
// 1. Route: GET /health under the /v1 server base (and the bare /health alias the station also
//    serves) is registered as public, matching `security: []` and `x-roles: []`.
// 2. 200: against a migrated throwaway Postgres (STATION_TEST_DATABASE_URL when set, otherwise a
//    Docker container), the body must match the documented Health schema.
// 3. 503: with a database that does not answer, the response must be the documented
//    application/problem+json Problem.

import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";
import type { FastifyInstance, LightMyRequestResponse } from "fastify";
import { buildServer } from "../../src/core/app.js";
import { type Database, createDatabase, urlConnection } from "../../src/core/db.js";
import { OpenApi } from "../packages/openapi.js";
import { startTestDatabase, type TestDatabase } from "../uploads/support/infra.js";
import { fakeDatabase, logCollector, testConfig } from "./helpers.js";

const OPERATION_ID = "getHealth";
const openapi = new OpenApi();
const op = openapi.operation(OPERATION_ID);

/** The documented URL (server base /v1 + path) and the bare alias the station also serves. */
const URLS = [op.routeUrl, op.path];

function assertConforms(response: LightMyRequestResponse, status: number): void {
  assert.equal(response.statusCode, status, response.body);
  assert.deepEqual(
    openapi.responseErrors(OPERATION_ID, response),
    [],
    `${OPERATION_ID} ${response.statusCode} does not match station.yaml: ${response.body}`,
  );
}

describe("getHealth route", () => {
  let app: FastifyInstance;

  before(async () => {
    app = await buildServer({
      config: testConfig(),
      db: fakeDatabase(),
      routesDir: false,
      logStream: logCollector().stream,
    });
    await app.ready();
  });

  after(async () => {
    await app.close();
  });

  it("is documented as GET /health, public, with 200 and 503 responses", () => {
    assert.equal(op.method, "GET");
    assert.equal(op.path, "/health");
    assert.deepEqual(op.roles, []);
    assert.deepEqual(op.node.security, []);
    assert.deepEqual(Object.keys(op.node.responses as object).sort(), ["200", "503"]);
  });

  for (const url of URLS) {
    it(`GET ${url} is registered as public with exactly its x-roles`, () => {
      const route = app.routeAccess.find(
        (access) => access.url === url && access.method.split(",").includes(op.method),
      );
      assert.ok(route, `${op.method} ${url} is not registered`);
      assert.equal(route.public, true);
      assert.deepEqual([...route.roles], [...op.roles]);
    });
  }
});

describe("getHealth 200 against Postgres", () => {
  let database: TestDatabase;
  let db: Database;
  let app: FastifyInstance;

  before(async () => {
    database = await startTestDatabase();
    db = createDatabase({ connection: urlConnection(database.url), poolMax: 2 });
    app = await buildServer({
      config: testConfig({ DATABASE_URL: database.url }),
      db,
      routesDir: false,
      logStream: logCollector().stream,
    });
    await app.ready();
  });

  after(async () => {
    await app?.close();
    await db?.close();
    await database?.release();
  });

  for (const url of URLS) {
    it(`GET ${url} without a token returns a body matching the Health schema`, async () => {
      const response = await app.inject({ method: "GET", url });
      assertConforms(response, 200);
      assert.deepEqual(response.json(), { status: "ok", version: "1.0.0-test" });
    });
  }

  it("the Health schema rejects bodies the station must never send", () => {
    const pointer = "#/components/schemas/Health";
    assert.deepEqual(openapi.errorsAt(pointer, { status: "ok", version: "1.0.0-test" }), []);
    assert.notDeepEqual(openapi.errorsAt(pointer, { status: "degraded", version: "1" }), []);
    assert.notDeepEqual(openapi.errorsAt(pointer, { status: "ok" }), []);
    assert.notDeepEqual(openapi.errorsAt(pointer, { status: "ok", version: "" }), []);
    assert.notDeepEqual(openapi.errorsAt(pointer, { status: "ok", version: "1", db: "up" }), []);
  });
});

describe("getHealth 503 when the registry is unreachable", () => {
  const cases: [string, () => Database][] = [
    [
      "an injected database whose ping fails",
      () => {
        const db = fakeDatabase();
        db.pingFails = true;
        return db;
      },
    ],
    [
      "a real pool pointed at a closed loopback port",
      () =>
        createDatabase({
          connection: urlConnection("postgres://station@127.0.0.1:1/station_test"),
          poolMax: 1,
        }),
    ],
  ];

  for (const [label, makeDb] of cases) {
    describe(label, () => {
      let db: Database;
      let app: FastifyInstance;

      before(async () => {
        db = makeDb();
        app = await buildServer({
          config: testConfig(),
          db,
          routesDir: false,
          logStream: logCollector().stream,
        });
        await app.ready();
      });

      after(async () => {
        await app.close();
        await db.close();
      });

      for (const url of URLS) {
        it(`GET ${url} returns the documented 503 Problem`, async () => {
          const response = await app.inject({ method: "GET", url });
          assertConforms(response, 503);
          const body = response.json() as { status: number; code: string };
          assert.equal(body.status, 503);
          assert.equal(body.code, "registry_unavailable");
        });
      }
    });
  }
});

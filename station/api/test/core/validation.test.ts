// Request validation (F7: "Request validation never coerces types: a wrong type is rejected
// with 400, not converted"):
//
// - JSON bodies are never coerced: a string where an integer is required, a number where a
//   string is required, a scalar where an array is required or null are all 400, and a valid
//   body reaches the handler exactly as sent.
// - Query strings and path parameters are text on the wire, so a value is parsed to its
//   declared type ("2" -> 2) and still rejected when it is not one ("two" -> 400).
// - Unknown properties are rejected (not stripped), defaults are applied, and only the first
//   schema error is reported (allErrors stays off).
//
// The routes are a test-only area in fixtures/validation-routes, autoloaded like src/routes.

import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { after, before, describe, it } from "node:test";
import type { FastifyInstance } from "fastify";
import { buildServer } from "../../src/core/app.js";
import {
  fakeDatabase,
  logCollector,
  startTestIssuer,
  testConfig,
  type TestIssuer,
} from "./helpers.js";

const ROUTES = fileURLToPath(new URL("./fixtures/validation-routes", import.meta.url));

let issuer: TestIssuer;
let app: FastifyInstance;
let authorization: string;

before(async () => {
  issuer = await startTestIssuer();
  app = await buildServer({
    config: testConfig({ ENTRA_JWKS_URL: issuer.jwksUrl }),
    db: fakeDatabase(),
    routesDir: ROUTES,
    logStream: logCollector().stream,
  });
  await app.ready();
  authorization = `Bearer ${await issuer.mint({ roles: ["bim"] })}`;
});

after(async () => {
  await app?.close();
  await issuer?.close();
});

interface ProblemBody {
  status: number;
  code: string;
  errors?: { pointer: string; message: string }[];
}

async function postBody(payload: unknown) {
  return app.inject({
    method: "POST",
    url: "/v1/types/body",
    headers: { authorization, "content-type": "application/json" },
    payload: JSON.stringify(payload),
  });
}

async function get(url: string) {
  return app.inject({ method: "GET", url, headers: { authorization } });
}

function assertInvalid(response: Awaited<ReturnType<typeof get>>, pointer?: string): ProblemBody {
  assert.equal(response.statusCode, 400, response.body);
  assert.match(String(response.headers["content-type"]), /^application\/problem\+json/);
  const problem = response.json() as ProblemBody;
  assert.equal(problem.code, "invalid_request");
  if (pointer !== undefined) {
    assert.deepEqual(
      problem.errors?.map((error) => error.pointer),
      [pointer],
    );
  }
  return problem;
}

describe("request bodies are never coerced", () => {
  it("rejects a string where an integer is required, without converting it", async () => {
    assertInvalid(await postBody({ count: "5" }), "/count");
    assertInvalid(await postBody({ count: "0" }), "/count");
  });

  it("rejects other wrong types too", async () => {
    const cases: [string, Record<string, unknown>, string][] = [
      ["a float as integer", { count: 1.5 }, "/count"],
      ["a boolean as integer", { count: true }, "/count"],
      ["null as integer", { count: null }, "/count"],
      ["a string as boolean", { count: 1, flag: "true" }, "/flag"],
      ["a number as boolean", { count: 1, flag: 1 }, "/flag"],
      ["a number as string", { count: 1, label: 5 }, "/label"],
      ["a boolean as string", { count: 1, label: false }, "/label"],
      ["a scalar as array", { count: 1, tags: "a" }, "/tags"],
      ["a number inside a string array", { count: 1, tags: ["a", 2] }, "/tags/1"],
    ];
    for (const [label, payload, pointer] of cases) {
      const response = await postBody(payload);
      assert.equal(response.statusCode, 400, `${label}: ${response.body}`);
      assertInvalid(response, pointer);
    }
  });

  it("passes a valid body through exactly as sent, with defaults applied", async () => {
    const response = await postBody({ count: 5, flag: false, label: "7", tags: ["1"] });
    assert.equal(response.statusCode, 200, response.body);
    assert.deepEqual(response.json(), {
      body: { count: 5, flag: false, label: "7", tags: ["1"], mode: "plain" },
      types: { count: "number", flag: "boolean", label: "string", tags: "array", mode: "string" },
    });
  });

  it("rejects unknown properties instead of stripping them", async () => {
    assertInvalid(await postBody({ count: 1, extra: true }), "/extra");
  });

  it("reports only the first schema error", async () => {
    const problem = assertInvalid(await postBody({ count: "1", flag: "yes", label: 3 }));
    assert.equal(problem.errors?.length, 1);
  });
});

describe("query strings and path parameters are parsed to their declared types", () => {
  it("parses a valid integer query value", async () => {
    const response = await get("/v1/types/query?limit=2");
    assert.equal(response.statusCode, 200, response.body);
    assert.deepEqual(response.json(), { limit: 2, limitType: "number" });
  });

  it("applies the default when the value is absent", async () => {
    const response = await get("/v1/types/query");
    assert.deepEqual(response.json(), { limit: 25, limitType: "number" });
  });

  it("still rejects a query value that is not of the declared type or out of range", async () => {
    for (const query of ["limit=two", "limit=1.5", "limit=0", "limit=101", "limit=", "page=2"]) {
      const response = await get(`/v1/types/query?${query}`);
      assert.equal(response.statusCode, 400, `${query}: ${response.body}`);
      assertInvalid(response);
    }
  });

  it("accepts a single value for an array query parameter, as before", async () => {
    const one = await get("/v1/types/query?tag=a");
    assert.deepEqual(one.json(), { limit: 25, limitType: "number", tag: ["a"] });
    const two = await get("/v1/types/query?tag=a&tag=b");
    assert.deepEqual(two.json(), { limit: 25, limitType: "number", tag: ["a", "b"] });
  });

  it("parses a valid integer path parameter and rejects an invalid one", async () => {
    const response = await get("/v1/types/items/7");
    assert.equal(response.statusCode, 200, response.body);
    assert.deepEqual(response.json(), { n: 7, nType: "number" });
    for (const value of ["x", "0", "1.5"]) {
      assertInvalid(await get(`/v1/types/items/${value}`));
    }
  });
});

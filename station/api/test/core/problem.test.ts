import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";
import type { FastifyInstance } from "fastify";
import { buildServer } from "../../src/core/app.js";
import {
  ProblemError,
  defaultCode,
  problemBody,
  validationErrors,
} from "../../src/core/problem.js";
import {
  fakeDatabase,
  logCollector,
  startTestIssuer,
  testConfig,
  type TestIssuer,
} from "./helpers.js";

let issuer: TestIssuer;
let app: FastifyInstance;
const logs = logCollector();

before(async () => {
  issuer = await startTestIssuer();
  app = await buildServer({
    config: testConfig({ ENTRA_JWKS_URL: issuer.jwksUrl }),
    db: fakeDatabase(),
    routesDir: false,
    logStream: logs.stream,
  });
  app.get("/v1/test/conflict", { config: { roles: ["capture"] } }, async () => {
    throw new ProblemError(409, "package_sealed", { detail: "The package is already sealed." });
  });
  app.get("/v1/test/crash", { config: { roles: ["capture"] } }, async () => {
    throw new Error("connection to db.internal:5432 refused for user station");
  });
  app.post("/v1/test/echo", { config: { roles: ["capture"] } }, async (request) => request.body);
  await app.ready();
});

after(async () => {
  await app.close();
  await issuer.close();
});

async function auth(): Promise<Record<string, string>> {
  return { authorization: `Bearer ${await issuer.mint({ roles: ["capture"] })}` };
}

describe("problem responses", () => {
  it("sends ProblemError as problem+json with its code", async () => {
    const response = await app.inject({ url: "/v1/test/conflict", headers: await auth() });
    assert.equal(response.statusCode, 409);
    assert.match(String(response.headers["content-type"]), /^application\/problem\+json/);
    assert.deepEqual(response.json(), {
      type: "about:blank",
      title: "Conflict",
      status: 409,
      code: "package_sealed",
      detail: "The package is already sealed.",
    });
  });

  it("hides internal error text behind a 500 internal_error", async () => {
    const response = await app.inject({ url: "/v1/test/crash", headers: await auth() });
    assert.equal(response.statusCode, 500);
    const body = response.json() as Record<string, unknown>;
    assert.equal(body.code, "internal_error");
    assert.ok(!response.body.includes("db.internal"));
  });

  it("maps malformed JSON and unsupported media types to 4xx problems", async () => {
    const headers = { ...(await auth()), "content-type": "application/json" };
    const bad = await app.inject({ method: "POST", url: "/v1/test/echo", headers, payload: "{" });
    assert.equal(bad.statusCode, 400);
    assert.equal((bad.json() as { code: string }).code, "bad_request");

    const media = await app.inject({
      method: "POST",
      url: "/v1/test/echo",
      headers: { ...(await auth()), "content-type": "text/csv" },
      payload: "a,b",
    });
    assert.equal(media.statusCode, 415);
    assert.equal((media.json() as { code: string }).code, "unsupported_media_type");
  });

  it("returns the request id header", async () => {
    const response = await app.inject({ url: "/health" });
    assert.match(String(response.headers["x-request-id"]), /^[0-9a-f-]{36}$/);
  });
});

describe("problem helpers", () => {
  it("derives codes from status phrases", () => {
    assert.equal(defaultCode(404), "not_found");
    assert.equal(defaultCode(413), "payload_too_large");
    assert.equal(defaultCode(422), "unprocessable_entity");
  });

  it("rejects invalid statuses and codes", () => {
    assert.throws(() => new ProblemError(200, "ok"), RangeError);
    assert.throws(() => new ProblemError(400, "Bad-Code"), RangeError);
  });

  it("omits empty optional members", () => {
    assert.deepEqual(problemBody(404, "verdict_not_ready", { errors: [] }), {
      type: "about:blank",
      title: "Not Found",
      status: 404,
      code: "verdict_not_ready",
    });
  });

  it("builds JSON Pointers for required and additional properties", () => {
    assert.deepEqual(
      validationErrors([
        { instancePath: "/files/0", keyword: "required", params: { missingProperty: "sha256" } },
        {
          instancePath: "",
          keyword: "additionalProperties",
          params: { additionalProperty: "a/b" },
        },
        { instancePath: "/revision", keyword: "minimum", message: "must be >= 1" },
      ]),
      [
        { pointer: "/files/0/sha256", message: "required" },
        { pointer: "/a~1b", message: "additionalProperties" },
        { pointer: "/revision", message: "must be >= 1" },
      ],
    );
  });
});

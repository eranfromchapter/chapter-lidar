// F7 AC6 for the projects area: the station implements every `projects` operation of
// contract/openapi/station.yaml with matching roles, request schemas and response schemas.
//
// Each documented response status is produced through the real app (every src/routes area, a
// test Entra issuer, an injected HubClient) and its body is validated against the document's
// schema for that status and media type.

import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";
import type { FastifyInstance, FastifySchema, InjectOptions } from "fastify";
import { buildServer } from "../../src/core/app.js";
import { FakeHubClient } from "../../src/hub/fake.js";
import type { HubClient } from "../../src/hub/types.js";
import {
  fakeDatabase,
  logCollector,
  startTestIssuer,
  testConfig,
  type TestIssuer,
} from "../core/helpers.js";
import { FailingHubClient, bearer } from "./helpers.js";
import {
  type JsonSchema,
  type OpenApiOperation,
  type SchemaValidator,
  loadStationOpenApi,
  operations,
  routeUrl,
  schemaValidator,
  withoutAnnotations,
} from "./openapi.js";

const TAG = "projects";

interface CapturedRoute {
  method: string;
  url: string;
  schema: FastifySchema | undefined;
}

let issuer: TestIssuer;
let projectOps: OpenApiOperation[];
let validator: SchemaValidator;
const apps: FastifyInstance[] = [];
/** Route options seen by requests that passed sign-in (method + url -> options). */
const seenRoutes = new Map<string, CapturedRoute>();
/** operationId -> statuses produced and validated by the tests below. */
const covered = new Map<string, Set<string>>();

async function appWith(hub: HubClient): Promise<FastifyInstance> {
  const app = await buildServer({
    config: testConfig({ ENTRA_JWKS_URL: issuer.jwksUrl }),
    db: fakeDatabase(),
    services: { hub },
    logStream: logCollector().stream,
  });
  // Runs after the core auth hook, so only for requests that passed sign-in.
  app.addHook("onRequest", async (request) => {
    const { method, url, schema } = request.routeOptions;
    if (typeof method === "string" && typeof url === "string") {
      seenRoutes.set(`${method} ${url}`, { method, url, schema });
    }
  });
  await app.ready();
  apps.push(app);
  return app;
}

let healthy: FastifyInstance;
let failing: FastifyInstance;

function operation(operationId: string): OpenApiOperation {
  const found = projectOps.find((op) => op.operationId === operationId);
  assert.ok(found, `operation ${operationId} is not in the OpenAPI document`);
  return found;
}

function schemaKey(op: OpenApiOperation, status: string, type: string): string {
  return `${op.operationId} ${status} ${type}`;
}

/** Sends the request and checks status, media type and body against the document. */
async function conforms(
  app: FastifyInstance,
  operationId: string,
  request: InjectOptions,
  expectedStatus: number,
): Promise<unknown> {
  const op = operation(operationId);
  const response = await app.inject(request);
  const status = String(response.statusCode);
  assert.equal(response.statusCode, expectedStatus, `${request.url}: ${response.body}`);
  const documented = op.responses[status];
  assert.ok(documented, `${operationId} answered ${status}, which the document does not list`);
  const type =
    String(response.headers["content-type"] ?? "")
      .split(";")[0]
      ?.trim() ?? "";
  assert.ok(
    type in documented,
    `${operationId} ${status} answered ${type}; documented: ${Object.keys(documented).join(", ")}`,
  );
  const body = response.json() as unknown;
  const errors = await validator.validate(schemaKey(op, status, type), body);
  assert.deepEqual(errors, [], `${operationId} ${status} body does not match the schema`);
  const statuses = covered.get(operationId) ?? new Set<string>();
  statuses.add(status);
  covered.set(operationId, statuses);
  return body;
}

before(async () => {
  issuer = await startTestIssuer();
  const document = loadStationOpenApi();
  projectOps = operations(document).filter((op) => op.tags.includes(TAG));
  const schemas: Record<string, JsonSchema> = {};
  for (const op of projectOps) {
    for (const [status, media] of Object.entries(op.responses)) {
      for (const [type, schema] of Object.entries(media)) {
        schemas[schemaKey(op, status, type)] = schema;
      }
    }
  }
  validator = await schemaValidator(schemas);
  healthy = await appWith(new FakeHubClient());
  failing = await appWith(new FailingHubClient());
});

after(async () => {
  for (const app of apps) {
    await app.close();
  }
  await validator?.close();
  await issuer?.close();
});

describe("projects operations in the OpenAPI document", () => {
  it("are listProjects and getProject", () => {
    assert.deepEqual(projectOps.map((op) => op.operationId).sort(), ["getProject", "listProjects"]);
  });

  it("each have a route with the same method, path and roles", () => {
    for (const op of projectOps) {
      const access = healthy.routeAccess.find(
        (r) => r.method === op.method && r.url === routeUrl(op.path),
      );
      assert.ok(access, `${op.operationId}: no route ${op.method} ${routeUrl(op.path)}`);
      assert.equal(access.public, false);
      assert.deepEqual([...access.roles].sort(), [...op.roles].sort(), `${op.operationId} roles`);
    }
  });

  it("have no route under /v1/projects that the document does not list", () => {
    const documented = new Set(projectOps.map((op) => `${op.method} ${routeUrl(op.path)}`));
    const extra = healthy.routeAccess
      .filter((r) => r.method !== "HEAD")
      .filter((r) => r.url === "/v1/projects" || r.url.startsWith("/v1/projects/"))
      .map((r) => `${r.method} ${r.url}`)
      .filter((key) => !documented.has(key));
    assert.deepEqual(extra, []);
  });
});

describe("listProjects request schema", () => {
  it("matches the documented query parameters, unknown parameters rejected", async () => {
    const op = operation("listProjects");
    const token = await issuer.mint({ roles: ["capture"] });
    await healthy.inject({ method: "GET", url: "/v1/projects", headers: bearer(token) });
    const route = seenRoutes.get("GET /v1/projects");
    const querystring = route?.schema?.querystring as JsonSchema | undefined;
    assert.ok(querystring, "GET /v1/projects must validate its query string");
    const queryParams = op.parameters.filter((p) => p.in === "query");
    assert.deepEqual(
      withoutAnnotations(querystring),
      withoutAnnotations({
        type: "object",
        additionalProperties: false,
        properties: Object.fromEntries(queryParams.map((p) => [p.name, p.schema])),
        ...(queryParams.some((p) => p.required === true)
          ? { required: queryParams.filter((p) => p.required === true).map((p) => p.name) }
          : {}),
      }),
    );
    assert.equal(op.parameters.filter((p) => p.in !== "query").length, 0);
  });
});

describe("getProject request schema", () => {
  it("documents only the dealId path parameter, which the route enforces as DealId", async () => {
    const op = operation("getProject");
    assert.deepEqual(
      op.parameters.map((p) => `${p.in}:${p.name}`),
      ["path:dealId"],
    );
    const token = await issuer.mint({ roles: ["capture"] });
    await healthy.inject({ method: "GET", url: "/v1/projects/x", headers: bearer(token) });
    const route = seenRoutes.get("GET /v1/projects/:dealId");
    assert.ok(route, "GET /v1/projects/:dealId must exist");
    // Out-of-schema ids answer 404 (the only documented client error), so the route checks
    // the id itself with DEAL_ID_SCHEMA instead of a params schema (which would answer 400).
    assert.equal(route.schema?.params, undefined);
    const { DEAL_ID_SCHEMA } = await import("../../src/routes/projects/schemas.js");
    const documented = op.parameters[0]?.schema as JsonSchema;
    assert.deepEqual(withoutAnnotations(documented), withoutAnnotations({ ...DEAL_ID_SCHEMA }));
  });
});

describe("listProjects responses", () => {
  const url = "/v1/projects";

  it("200 lists confirmed-address projects", async () => {
    const token = await issuer.mint({ roles: ["capture"] });
    const body = (await conforms(
      healthy,
      "listProjects",
      { method: "GET", url, headers: bearer(token) },
      200,
    )) as {
      projects: { dealId: string }[];
    };
    assert.deepEqual(
      body.projects.map((p) => p.dealId),
      ["fixture-deal-0001", "fixture-deal-0002"],
    );
  });

  it("200 with q and limit", async () => {
    for (const role of ["capture", "bim", "admin"]) {
      const token = await issuer.mint({ roles: [role] });
      await conforms(
        healthy,
        "listProjects",
        { method: "GET", url: `${url}?q=example&limit=1`, headers: bearer(token) },
        200,
      );
    }
  });

  it("400 for parameters outside the schema", async () => {
    const token = await issuer.mint({ roles: ["bim"] });
    for (const query of [
      "q=",
      `q=${"x".repeat(201)}`,
      "limit=0",
      "limit=101",
      "limit=two",
      "page=2",
    ]) {
      await conforms(
        healthy,
        "listProjects",
        { method: "GET", url: `${url}?${query}`, headers: bearer(token) },
        400,
      );
    }
  });

  it("401 without a token", async () => {
    await conforms(healthy, "listProjects", { method: "GET", url }, 401);
  });

  it("403 for a token without a station role", async () => {
    const token = await issuer.mint({ roles: null });
    await conforms(healthy, "listProjects", { method: "GET", url, headers: bearer(token) }, 403);
  });

  it("502 when the HUB fails", async () => {
    const token = await issuer.mint({ roles: ["capture"] });
    const body = (await conforms(
      failing,
      "listProjects",
      { method: "GET", url, headers: bearer(token) },
      502,
    )) as {
      code: string;
    };
    assert.equal(body.code, "hub_unavailable");
  });
});

describe("getProject responses", () => {
  it("200 for the fixture deal", async () => {
    const token = await issuer.mint({ roles: ["bim"] });
    const body = await conforms(
      healthy,
      "getProject",
      { method: "GET", url: "/v1/projects/fixture-deal-0001", headers: bearer(token) },
      200,
    );
    assert.deepEqual(body, {
      dealId: "fixture-deal-0001",
      projectName: "Fixture project",
      address: { formatted: "100 Example Street, Testville, NY 00000" },
    });
  });

  it("404 for an unknown deal, a deal without a confirmed address and an out-of-schema id", async () => {
    const token = await issuer.mint({ roles: ["admin"] });
    for (const dealId of ["no-such-deal", "fixture-deal-0003", "d".repeat(65)]) {
      await conforms(
        healthy,
        "getProject",
        { method: "GET", url: `/v1/projects/${dealId}`, headers: bearer(token) },
        404,
      );
    }
  });

  it("401 without a token", async () => {
    await conforms(
      healthy,
      "getProject",
      { method: "GET", url: "/v1/projects/fixture-deal-0001" },
      401,
    );
  });

  it("403 for a token without a station role", async () => {
    const token = await issuer.mint({ roles: ["Capture"] });
    await conforms(
      healthy,
      "getProject",
      { method: "GET", url: "/v1/projects/fixture-deal-0001", headers: bearer(token) },
      403,
    );
  });

  it("502 when the HUB fails", async () => {
    const token = await issuer.mint({ roles: ["capture"] });
    await conforms(
      failing,
      "getProject",
      { method: "GET", url: "/v1/projects/fixture-deal-0001", headers: bearer(token) },
      502,
    );
  });
});

describe("coverage", () => {
  it("produced every documented status of every projects operation", () => {
    for (const op of projectOps) {
      assert.deepEqual(
        [...(covered.get(op.operationId) ?? [])].sort(),
        Object.keys(op.responses).sort(),
        `${op.operationId}: statuses produced vs documented`,
      );
    }
  });
});

// F7 AC1: requests without a valid Entra token get 401 and wrong-role requests get 403 on
// every route.
//
// Signing keys come from an in-process JWKS on 127.0.0.1 (createRemoteJWKSet, as in
// production); no other network is used.

import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { after, before, describe, it } from "node:test";
import type { FastifyInstance, InjectOptions } from "fastify";
import { SignJWT, UnsecuredJWT } from "jose";
import { buildServer } from "../../src/core/app.js";
import { ROLES, type Role } from "../../src/core/auth.js";
import {
  AUDIENCE,
  ISSUER,
  OTHER_TENANT_ID,
  SECOND_AUDIENCE,
  USER_OID,
  fakeDatabase,
  logCollector,
  startTestIssuer,
  testConfig,
  type TestIssuer,
} from "./helpers.js";

const FIXTURE_ROUTES = fileURLToPath(new URL("./fixtures/routes", import.meta.url));
const MISSING_ROLES_ROUTES = fileURLToPath(
  new URL("./fixtures/routes-missing-roles", import.meta.url),
);
const SAMPLE_UUID = "3f2a1b4c-5d6e-4f70-8a9b-0c1d2e3f4a5b";

let issuer: TestIssuer;
const logs = logCollector();
let app: FastifyInstance;

async function probeApp(
  routesDir: string | false = FIXTURE_ROUTES,
  jwksUrl?: string,
): Promise<FastifyInstance> {
  return buildServer({
    config: testConfig({ ENTRA_JWKS_URL: jwksUrl ?? issuer.jwksUrl }),
    db: fakeDatabase(),
    routesDir,
    logStream: logs.stream,
  });
}

function bearer(token: string): Record<string, string> {
  return { authorization: `Bearer ${token}` };
}

function assertProblem(
  response: Awaited<ReturnType<FastifyInstance["inject"]>>,
  status: number,
  code: string,
): void {
  assert.equal(response.statusCode, status, response.body);
  assert.match(String(response.headers["content-type"]), /^application\/problem\+json/);
  const body = response.json() as Record<string, unknown>;
  assert.equal(body.status, status);
  assert.equal(body.code, code);
  assert.equal(typeof body.type, "string");
  assert.equal(typeof body.title, "string");
}

before(async () => {
  issuer = await startTestIssuer();
  app = await probeApp();
  await app.ready();
});

after(async () => {
  await app.close();
  await issuer.close();
});

describe("Entra token validation", () => {
  const route = "/v1/probe/bim";

  it("returns 401 with a Bearer challenge when there is no token", async () => {
    const response = await app.inject({ method: "GET", url: route });
    assertProblem(response, 401, "unauthorized");
    assert.equal(response.headers["www-authenticate"], 'Bearer realm="chapter-station"');
  });

  it("returns 401 invalid_token for a non-bearer or malformed authorization header", async () => {
    for (const authorization of ["Basic ZGFuYTpzZWNyZXQ=", "Bearer", "Bearer not-a-jwt", "x"]) {
      const response = await app.inject({ method: "GET", url: route, headers: { authorization } });
      assertProblem(response, 401, "unauthorized");
      assert.equal(
        response.headers["www-authenticate"],
        'Bearer realm="chapter-station", error="invalid_token"',
        authorization,
      );
    }
  });

  const rejected: [string, () => Promise<string>][] = [
    ["an expired token", () => issuer.mint({ roles: ["bim"] }, { expiresInSeconds: -120 })],
    [
      "a token that is not valid yet",
      () => issuer.mint({ roles: ["bim"] }, { notBeforeSeconds: 600 }),
    ],
    ["a wrong issuer", () => issuer.mint({ roles: ["bim"], iss: "https://sts.windows.net/x/" })],
    [
      "the v1.0 issuer of the same tenant",
      () => issuer.mint({ roles: ["bim"], iss: ISSUER.replace("/v2.0", "") }),
    ],
    ["a wrong audience", () => issuer.mint({ roles: ["bim"], aud: "api://someone-else" })],
    ["another tenant", () => issuer.mint({ roles: ["bim"], tid: OTHER_TENANT_ID })],
    ["no tenant claim", () => issuer.mint({ roles: ["bim"], tid: null })],
    ["no oid claim", () => issuer.mint({ roles: ["bim"], oid: null })],
    ["a key that is not in the JWKS", () => issuer.mintWithForeignKey({ roles: ["bim"] })],
    ["an unknown key id", () => issuer.mintWithForeignKey({ roles: ["bim"] }, "unknown-key-id")],
    [
      "an HS256 token",
      () =>
        new SignJWT({ roles: ["bim"], tid: "x", oid: USER_OID, aud: AUDIENCE, iss: ISSUER })
          .setProtectedHeader({ alg: "HS256", kid: issuer.kid })
          .setIssuedAt()
          .setExpirationTime("1h")
          .sign(new TextEncoder().encode("a-shared-secret-that-is-long-enough-1234")),
    ],
    [
      "an unsigned token (alg none)",
      async () =>
        new UnsecuredJWT({ roles: ["bim"], oid: USER_OID, aud: AUDIENCE, iss: ISSUER })
          .setIssuedAt()
          .setExpirationTime("1h")
          .encode(),
    ],
    [
      "a token with a tampered payload",
      async () => {
        const [header, , signature] = (await issuer.mint({ roles: ["capture"] })).split(".");
        const forged = Buffer.from(
          JSON.stringify({ iss: ISSUER, aud: AUDIENCE, roles: ["bim"], oid: USER_OID }),
        ).toString("base64url");
        return `${header}.${forged}.${signature}`;
      },
    ],
  ];

  for (const [label, makeToken] of rejected) {
    it(`returns 401 for ${label}`, async () => {
      const response = await app.inject({
        method: "GET",
        url: route,
        headers: bearer(await makeToken()),
      });
      assertProblem(response, 401, "unauthorized");
      assert.match(String(response.headers["www-authenticate"]), /error="invalid_token"/);
    });
  }

  it("returns 403 for a valid token without one of the route's roles", async () => {
    const response = await app.inject({
      method: "GET",
      url: route,
      headers: bearer(await issuer.mint({ roles: ["capture"] })),
    });
    assertProblem(response, 403, "forbidden");
    assert.match(String((response.json() as { detail: string }).detail), /bim/);
  });

  it("returns 403 for a valid token without a roles claim", async () => {
    const response = await app.inject({
      method: "GET",
      url: route,
      headers: bearer(await issuer.mint({ roles: null })),
    });
    assertProblem(response, 403, "forbidden");
  });

  it("does not treat admin as a superset of other roles", async () => {
    const response = await app.inject({
      method: "GET",
      url: route,
      headers: bearer(await issuer.mint({ roles: ["admin"] })),
    });
    assertProblem(response, 403, "forbidden");
  });

  it("ignores unknown roles in the token", async () => {
    const response = await app.inject({
      method: "GET",
      url: route,
      headers: bearer(await issuer.mint({ roles: ["Bim", "bim-reader", "owner"] })),
    });
    assertProblem(response, 403, "forbidden");
  });

  it("accepts a valid token with the role and exposes the principal", async () => {
    const response = await app.inject({
      method: "GET",
      url: route,
      headers: bearer(await issuer.mint({ roles: ["bim", "capture"] })),
    });
    assert.equal(response.statusCode, 200, response.body);
    assert.deepEqual(response.json(), {
      userId: USER_OID,
      name: "Dana Field",
      roles: ["capture", "bim"],
    });
  });

  it("accepts every configured audience and a case-insensitive Bearer scheme", async () => {
    const token = await issuer.mint({ roles: ["bim"], aud: SECOND_AUDIENCE });
    const response = await app.inject({
      method: "GET",
      url: route,
      headers: { authorization: `bearer ${token}` },
    });
    assert.equal(response.statusCode, 200, response.body);
  });

  it("falls back to preferred_username, then oid, for the principal name", async () => {
    const byUsername = await app.inject({
      method: "GET",
      url: route,
      headers: bearer(await issuer.mint({ roles: ["bim"], name: null })),
    });
    assert.equal((byUsername.json() as { name: string }).name, "dana@hellochapter.com");
    const byOid = await app.inject({
      method: "GET",
      url: route,
      headers: bearer(await issuer.mint({ roles: ["bim"], name: null, preferred_username: null })),
    });
    assert.equal((byOid.json() as { name: string }).name, USER_OID);
  });

  it("checks the token before the body: 401, then 403, then 400", async () => {
    const url = `/v1/probe/${SAMPLE_UUID}/notes`;
    const badBody: InjectOptions = { method: "POST", url, payload: { text: "", extra: 1 } };

    assertProblem(await app.inject(badBody), 401, "unauthorized");

    const bim = await issuer.mint({ roles: ["bim"] });
    assertProblem(await app.inject({ ...badBody, headers: bearer(bim) }), 403, "forbidden");

    const capture = await issuer.mint({ roles: ["capture"] });
    const invalid = await app.inject({ ...badBody, headers: bearer(capture) });
    assertProblem(invalid, 400, "invalid_request");
    const errors = (invalid.json() as { errors: { pointer: string }[] }).errors;
    assert.ok(errors.length >= 1);
    assert.ok(errors.every((error) => typeof error.pointer === "string"));

    const ok = await app.inject({
      method: "POST",
      url,
      headers: bearer(capture),
      payload: { text: "kitchen wall" },
    });
    assert.equal(ok.statusCode, 201, ok.body);
  });

  it("rejects unknown body properties instead of stripping them", async () => {
    const capture = await issuer.mint({ roles: ["capture"] });
    const response = await app.inject({
      method: "POST",
      url: `/v1/probe/${SAMPLE_UUID}/notes`,
      headers: bearer(capture),
      payload: { text: "ok", unexpected: true },
    });
    assertProblem(response, 400, "invalid_request");
    const errors = (response.json() as { errors: { pointer: string }[] }).errors;
    assert.deepEqual(
      errors.map((error) => error.pointer),
      ["/unexpected"],
    );
  });

  it("never writes a token to the log", async () => {
    const tokens = [
      await issuer.mint({ roles: ["bim"] }),
      await issuer.mint({ roles: ["capture"] }),
      await issuer.mint({ roles: ["bim"] }, { expiresInSeconds: -120 }),
    ];
    for (const token of tokens) {
      await app.inject({ method: "GET", url: route, headers: bearer(token) });
    }
    assert.ok(logs.lines.length > 0, "the app should have logged requests");
    for (const token of tokens) {
      const signature = token.split(".")[2] ?? token;
      assert.ok(!logs.lines.some((line) => line.includes(signature)), "token found in logs");
    }
    assert.ok(!logs.lines.some((line) => /eyJ[A-Za-z0-9_-]{10,}\./.test(line)));
  });

  it("returns 401 and logs an error when the signing keys cannot be loaded", async () => {
    const local = logCollector();
    const offline = await buildServer({
      config: testConfig({ ENTRA_JWKS_URL: "http://127.0.0.1:9/discovery/v2.0/keys" }),
      db: fakeDatabase(),
      routesDir: FIXTURE_ROUTES,
      logStream: local.stream,
    });
    try {
      const response = await offline.inject({
        method: "GET",
        url: route,
        headers: bearer(await issuer.mint({ roles: ["bim"] })),
      });
      assertProblem(response, 401, "unauthorized");
      assert.ok(local.lines.some((line) => line.includes("signing keys unavailable")));
    } finally {
      await offline.close();
    }
  });
});

describe("every route requires a role", () => {
  it("answers 401 without a token and 403 with the other roles on every protected route", async () => {
    // The real app: every src/routes area plus a test-only protected route.
    const real = await buildServer({
      config: testConfig({ ENTRA_JWKS_URL: issuer.jwksUrl }),
      db: fakeDatabase(),
      logStream: logs.stream,
    });
    real.get("/v1/test-only/protected", { config: { roles: ["admin"] } }, async () => ({}));
    await real.ready();
    try {
      const protectedRoutes = real.routeAccess.filter((access) => !access.public);
      assert.ok(protectedRoutes.length >= 1);
      for (const access of protectedRoutes) {
        const url = access.url.replace(/:[A-Za-z0-9_]+/g, SAMPLE_UUID).replace(/\*$/, "x");
        for (const method of access.method.split(",")) {
          const request = { method: method as InjectOptions["method"], url };
          const anonymous = await real.inject(request);
          assert.equal(anonymous.statusCode, 401, `${method} ${access.url} without a token`);

          const otherRoles = ROLES.filter((role) => !access.roles.includes(role));
          const token = await issuer.mint({ roles: otherRoles.length > 0 ? otherRoles : null });
          const wrongRole = await real.inject({ ...request, headers: bearer(token) });
          assert.equal(wrongRole.statusCode, 403, `${method} ${access.url} with ${otherRoles}`);
        }
      }
    } finally {
      await real.close();
    }
  });

  it("lists every route with its roles and only /health as public", async () => {
    const urls = app.routeAccess.map((access) => `${access.method} ${access.url}`);
    assert.ok(urls.includes("GET /health"));
    assert.ok(urls.includes("GET /v1/health"));
    assert.ok(urls.includes("GET /v1/probe/bim"));
    assert.ok(urls.includes("POST /v1/probe/:packageId/notes"));
    assert.ok(!urls.some((url) => url.includes("/probe/helper")), "helper.ts must not load");
    for (const access of app.routeAccess) {
      if (access.public) {
        assert.ok(["/health", "/v1/health"].includes(access.url), access.url);
      } else {
        assert.ok(access.roles.length > 0);
      }
    }
  });

  const misconfigured: [string, (server: FastifyInstance) => void, RegExp][] = [
    ["no config", (s) => s.get("/v1/open", async () => ({})), /no access rule/],
    [
      "empty roles",
      (s) => s.get("/v1/open", { config: { roles: [] } }, async () => ({})),
      /no access rule/,
    ],
    [
      "an unknown role",
      (s) => s.get("/v1/open", { config: { roles: ["owner" as Role] } }, async () => ({})),
      /unknown roles/,
    ],
    [
      "duplicate roles",
      (s) => s.get("/v1/open", { config: { roles: ["bim", "bim"] } }, async () => ({})),
      /duplicate roles/,
    ],
    [
      "public on a non-health path",
      (s) => s.get("/v1/packages", { config: { public: true } }, async () => ({})),
      /only \/health, \/v1\/health may be public/,
    ],
    [
      "public and roles together",
      (s) => s.get("/v1/open", { config: { public: true, roles: ["bim"] } }, async () => ({})),
      /cannot also declare roles/,
    ],
  ];

  for (const [label, register, message] of misconfigured) {
    it(`refuses to start with a route that has ${label}`, async () => {
      const server = await probeApp(false);
      assert.throws(() => register(server), message);
      await server.close();
    });
  }

  it("refuses to start when an autoloaded route area declares no roles", async () => {
    await assert.rejects(async () => {
      const server = await probeApp(MISSING_ROLES_ROUTES);
      await server.ready();
    }, /GET \/v1\/careless has no access rule/);
  });
});

describe("health and unknown routes", () => {
  it("serves GET /health and GET /v1/health without a token", async () => {
    for (const url of ["/health", "/v1/health"]) {
      const response = await app.inject({ method: "GET", url });
      assert.equal(response.statusCode, 200, response.body);
      assert.deepEqual(response.json(), { status: "ok", version: "1.0.0-test" });
    }
  });

  it("returns 503 registry_unavailable when the database does not answer", async () => {
    const db = fakeDatabase();
    db.pingFails = true;
    const server = await buildServer({
      config: testConfig({ ENTRA_JWKS_URL: issuer.jwksUrl }),
      db,
      routesDir: false,
      logStream: logs.stream,
    });
    try {
      const response = await server.inject({ method: "GET", url: "/health" });
      assertProblem(response, 503, "registry_unavailable");
    } finally {
      await server.close();
    }
  });

  it("returns a 404 problem for unknown routes", async () => {
    const response = await app.inject({ method: "GET", url: "/v1/nothing-here?x=1" });
    assertProblem(response, 404, "not_found");
  });
});

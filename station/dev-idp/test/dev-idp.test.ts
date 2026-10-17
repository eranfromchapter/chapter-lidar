// F13 AC1: dev-idp tokens are accepted by the station auth plugin with the requested roles, and
// the dev-idp refuses to start in production.
//
// Tokens are verified by the station's real app and auth plugin (station/api/src/core), with
// ENTRA_JWKS_URL pointing at an in-process dev-idp on 127.0.0.1 (createRemoteJWKSet, as on the
// local stack). No network beyond loopback, no Docker.

import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { Buffer } from "node:buffer";
import { once } from "node:events";
import { Writable } from "node:stream";
import { fileURLToPath } from "node:url";
import { after, before, describe, it } from "node:test";
import { buildServer } from "../../api/src/core/app.js";
import { requirePrincipal } from "../../api/src/core/auth.js";
import { loadConfig } from "../../api/src/core/config.js";
import type { Database } from "../../api/src/core/db.js";
import {
  DEFAULT_AUDIENCE,
  DEFAULT_ISSUER,
  DEFAULT_NAME,
  DEFAULT_SUBJECT,
  DEFAULT_TENANT_ID,
  MAX_TOKEN_LIFETIME_SECONDS,
  createDevIdp,
  loadDevIdpConfig,
} from "../src/server.mjs";

type DevIdp = ReturnType<typeof createDevIdp>;
type StationApp = Awaited<ReturnType<typeof buildServer>>;

const SERVER_PATH = fileURLToPath(new URL("../src/server.mjs", import.meta.url));
const OTHER_TENANT_ID = "9e8d7c6b-5a49-4382-8170-fedcba987654";

/** Database stand-in: the probe routes never query it. */
const noDatabase: Database = {
  async query() {
    throw new Error("the dev-idp tests do not use the database");
  },
  async transaction() {
    throw new Error("the dev-idp tests do not use the database");
  },
  async ping() {},
  async close() {},
};

function logCollector(): { lines: string[]; stream: Writable } {
  const lines: string[] = [];
  const stream = new Writable({
    write(chunk: Buffer, _encoding, callback) {
      lines.push(...chunk.toString("utf8").split("\n").filter(Boolean));
      callback();
    },
  });
  return { lines, stream };
}

async function startIdp(env: Record<string, string> = {}): Promise<{ idp: DevIdp; url: string }> {
  const idp = createDevIdp(loadDevIdpConfig({ NODE_ENV: "test", ...env }));
  const { port } = await idp.listen(0, "127.0.0.1");
  return { idp, url: `http://127.0.0.1:${port}` };
}

/**
 * The station app as configured on the local stack (the .env.example values), with the JWKS at
 * the given dev-idp, plus probe routes guarded by the real auth plugin.
 */
async function stationApp(idpUrl: string, logs: Writable): Promise<StationApp> {
  const config = loadConfig({
    NODE_ENV: "development",
    LOG_LEVEL: "info",
    DATABASE_URL: "postgres://station@127.0.0.1:1/station",
    ENTRA_TENANT_ID: "00000000-0000-0000-0000-000000000000",
    ENTRA_AUDIENCE: "api://chapter-capture-station-local",
    ENTRA_ISSUER: DEFAULT_ISSUER,
    ENTRA_JWKS_URL: `${idpUrl}/keys`,
    STATION_VERSION: "1.0.0-test",
  });
  const app = await buildServer({ config, db: noDatabase, routesDir: false, logStream: logs });
  for (const role of ["capture", "bim", "admin"] as const) {
    app.get(`/probe/${role}`, { config: { roles: [role] } }, async (request) =>
      requirePrincipal(request),
    );
  }
  await app.ready();
  return app;
}

async function requestToken(idpUrl: string, body: unknown): Promise<string> {
  const response = await fetch(`${idpUrl}/token`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  assert.equal(response.status, 200, await response.clone().text());
  const json = (await response.json()) as { access_token: string };
  return json.access_token;
}

function decodePart(token: string, index: 0 | 1): Record<string, unknown> {
  const part = token.split(".")[index];
  assert.ok(part !== undefined);
  return JSON.parse(Buffer.from(part, "base64url").toString("utf8")) as Record<string, unknown>;
}

async function probe(app: StationApp, role: string, token?: string) {
  return app.inject({
    method: "GET",
    url: `/probe/${role}`,
    headers: token === undefined ? {} : { authorization: `Bearer ${token}` },
  });
}

describe("dev-idp tokens and the station auth plugin", () => {
  const logs = logCollector();
  let main: { idp: DevIdp; url: string };
  let app: StationApp;

  before(async () => {
    main = await startIdp();
    app = await stationApp(main.url, logs.stream);
  });

  after(async () => {
    await app.close();
    await main.idp.close();
  });

  it("a capture token is accepted with the capture role and the default user", async () => {
    const token = await requestToken(main.url, { roles: ["capture"] });
    const response = await probe(app, "capture", token);
    assert.equal(response.statusCode, 200, response.body);
    assert.deepEqual(response.json(), {
      kind: "user",
      userId: DEFAULT_SUBJECT,
      name: DEFAULT_NAME,
      tenantId: DEFAULT_TENANT_ID,
      roles: ["capture"],
    });
  });

  it("the requested roles, subject and name arrive; missing roles get 403", async () => {
    const token = await requestToken(main.url, {
      roles: ["bim", "admin"],
      sub: "e2e-bim-user",
      name: "Dana Field",
    });
    for (const role of ["bim", "admin"]) {
      const response = await probe(app, role, token);
      assert.equal(response.statusCode, 200, response.body);
      const principal = response.json() as Record<string, unknown>;
      assert.deepEqual(principal.roles, ["bim", "admin"]);
      assert.equal(principal.userId, "e2e-bim-user");
      assert.equal(principal.name, "Dana Field");
    }
    const forbidden = await probe(app, "capture", token);
    assert.equal(forbidden.statusCode, 403, forbidden.body);
  });

  it("every role can be requested", async () => {
    const token = await requestToken(main.url, { roles: ["admin", "capture", "bim"] });
    for (const role of ["capture", "bim", "admin"]) {
      assert.equal((await probe(app, role, token)).statusCode, 200);
    }
  });

  it("no token gets 401", async () => {
    const response = await probe(app, "capture");
    assert.equal(response.statusCode, 401);
  });

  it("tokens are RS256, carry every checked claim and live at most one hour", async () => {
    const response = await fetch(`${main.url}/token`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ roles: ["capture"] }),
    });
    assert.equal(response.status, 200);
    assert.match(String(response.headers.get("cache-control")), /no-store/);
    const body = (await response.json()) as Record<string, unknown>;
    assert.deepEqual(Object.keys(body).sort(), ["access_token", "expires_in", "token_type"]);
    assert.equal(body.token_type, "Bearer");
    assert.equal(typeof body.access_token, "string");
    const token = body.access_token as string;

    const header = decodePart(token, 0);
    assert.equal(header.alg, "RS256");
    assert.equal(header.typ, "JWT");
    assert.equal(header.kid, main.idp.kid);

    const claims = decodePart(token, 1);
    assert.equal(claims.iss, DEFAULT_ISSUER);
    assert.equal(claims.aud, DEFAULT_AUDIENCE);
    assert.equal(claims.tid, DEFAULT_TENANT_ID);
    assert.equal(claims.oid, DEFAULT_SUBJECT);
    assert.equal(claims.sub, DEFAULT_SUBJECT);
    assert.equal(claims.name, DEFAULT_NAME);
    assert.deepEqual(claims.roles, ["capture"]);
    const { iat, nbf, exp } = claims as { iat: number; nbf: number; exp: number };
    const now = Math.floor(Date.now() / 1000);
    assert.ok(Math.abs(iat - now) <= 5, "iat is now");
    assert.ok(nbf <= iat + 1);
    assert.ok(exp > now);
    assert.ok(exp - iat <= MAX_TOKEN_LIFETIME_SECONDS);
    assert.equal(body.expires_in, exp - iat);
    assert.ok((body.expires_in as number) <= 3600);
  });

  it("serves a JWKS with only the public RSA key", async () => {
    const response = await fetch(`${main.url}/keys`);
    assert.equal(response.status, 200);
    const jwks = (await response.json()) as { keys: Record<string, unknown>[] };
    assert.equal(jwks.keys.length, 1);
    const [key] = jwks.keys;
    assert.ok(key !== undefined);
    assert.deepEqual(Object.keys(key).sort(), ["alg", "e", "kid", "kty", "n", "use"]);
    assert.equal(key.kty, "RSA");
    assert.equal(key.alg, "RS256");
    assert.equal(key.use, "sig");
    assert.equal(key.kid, main.idp.kid);
    assert.ok((key.n as string).length >= 342, "RSA modulus is at least 2048 bits");
  });

  it("expired tokens are refused", async () => {
    const now = Math.floor(Date.now() / 1000);
    const token = main.idp.mint({ roles: ["capture"] }, now - 2 * MAX_TOKEN_LIFETIME_SECONDS);
    const response = await probe(app, "capture", token);
    assert.equal(response.statusCode, 401);
    assert.ok(logs.lines.some((line) => line.includes('"auth":"token expired"')));
  });

  it("a token from another dev-idp key is refused", async () => {
    const other = await startIdp();
    try {
      const token = await requestToken(other.url, { roles: ["capture"] });
      assert.equal((await probe(app, "capture", token)).statusCode, 401);
    } finally {
      await other.idp.close();
    }
  });

  for (const [what, env, reason] of [
    ["audience", { DEV_IDP_AUDIENCE: "api://some-other-app" }, "claim check failed: aud"],
    ["issuer", { DEV_IDP_ISSUER: "http://localhost:9999/" }, "claim check failed: iss"],
    ["tenant", { DEV_IDP_TENANT_ID: OTHER_TENANT_ID }, "token tenant does not match"],
  ] as const) {
    it(`a token with the wrong ${what} is refused`, async () => {
      const wrong = await startIdp(env);
      const wrongLogs = logCollector();
      const wrongApp = await stationApp(wrong.url, wrongLogs.stream);
      try {
        const token = await requestToken(wrong.url, { roles: ["capture"] });
        const response = await probe(wrongApp, "capture", token);
        assert.equal(response.statusCode, 401);
        assert.ok(
          wrongLogs.lines.some((line) => line.includes(`"auth":"${reason}"`)),
          wrongLogs.lines.join("\n"),
        );
      } finally {
        await wrongApp.close();
        await wrong.idp.close();
      }
    });
  }

  it("the station never logs the token", async () => {
    const token = await requestToken(main.url, { roles: ["capture"] });
    await probe(app, "bim", token);
    assert.ok(!logs.lines.some((line) => line.includes(token)));
  });
});

describe("POST /token input", () => {
  let main: { idp: DevIdp; url: string };

  before(async () => {
    main = await startIdp();
  });

  after(async () => {
    await main.idp.close();
  });

  const invalidBodies: [string, string][] = [
    ["no roles", JSON.stringify({})],
    ["empty roles", JSON.stringify({ roles: [] })],
    ["roles not an array", JSON.stringify({ roles: "capture" })],
    ["unknown role", JSON.stringify({ roles: ["capture", "owner"] })],
    ["role with other case", JSON.stringify({ roles: ["Capture"] })],
    ["non-string role", JSON.stringify({ roles: [1] })],
    ["duplicate role", JSON.stringify({ roles: ["bim", "bim"] })],
    ["unknown property", JSON.stringify({ roles: ["capture"], tid: OTHER_TENANT_ID })],
    ["lifetime request", JSON.stringify({ roles: ["capture"], expires_in: 86400 })],
    ["empty sub", JSON.stringify({ roles: ["capture"], sub: "" })],
    ["sub with a space", JSON.stringify({ roles: ["capture"], sub: "a b" })],
    ["sub too long", JSON.stringify({ roles: ["capture"], sub: "a".repeat(129) })],
    ["sub not a string", JSON.stringify({ roles: ["capture"], sub: 42 })],
    ["empty name", JSON.stringify({ roles: ["capture"], name: "" })],
    ["blank name", JSON.stringify({ roles: ["capture"], name: "   " })],
    ["name with a control character", JSON.stringify({ roles: ["capture"], name: "a\u0000b" })],
    ["name with a bidi override", JSON.stringify({ roles: ["capture"], name: "a‮b" })],
    ["name too long", JSON.stringify({ roles: ["capture"], name: "a".repeat(201) })],
    ["array body", JSON.stringify([{ roles: ["capture"] }])],
    ["null body", "null"],
    ["not JSON", "roles=capture"],
    ["empty body", ""],
    ["oversized body", JSON.stringify({ roles: ["capture"], name: "a".repeat(10_000) })],
  ];

  for (const [what, body] of invalidBodies) {
    it(`rejects ${what} with 400`, async () => {
      const response = await fetch(`${main.url}/token`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body,
      });
      assert.equal(response.status, 400);
      const json = (await response.json()) as Record<string, unknown>;
      assert.equal(json.error, "invalid_request");
      assert.equal(json.access_token, undefined);
    });
  }

  it("rejects a non-JSON content type with 400", async () => {
    const response = await fetch(`${main.url}/token`, {
      method: "POST",
      headers: { "content-type": "text/plain" },
      body: JSON.stringify({ roles: ["capture"] }),
    });
    assert.equal(response.status, 400);
  });

  it("accepts a name with letters outside ASCII", async () => {
    const response = await fetch(`${main.url}/token`, {
      method: "POST",
      headers: { "content-type": "application/json; charset=utf-8" },
      body: JSON.stringify({ roles: ["capture"], name: "Dana Fíeld דנה" }),
    });
    assert.equal(response.status, 200);
  });

  it("answers 405 for other methods and 404 for other paths", async () => {
    const getToken = await fetch(`${main.url}/token`);
    assert.equal(getToken.status, 405);
    assert.equal(getToken.headers.get("allow"), "POST");
    const postKeys = await fetch(`${main.url}/keys`, { method: "POST" });
    assert.equal(postKeys.status, 405);
    assert.equal(postKeys.headers.get("allow"), "GET, HEAD");
    const missing = await fetch(`${main.url}/authorize`);
    assert.equal(missing.status, 404);
  });
});

describe("dev-idp configuration", () => {
  it("defaults match the local stack's .env.example values", () => {
    const config = loadDevIdpConfig({});
    assert.equal(config.tenantId, "00000000-0000-0000-0000-000000000000");
    assert.equal(config.audience, "api://chapter-capture-station-local");
    assert.equal(config.issuer, DEFAULT_ISSUER);
    assert.equal(config.port, 8090);
    assert.equal(config.host, "127.0.0.1");
  });

  it("the station accepts the default issuer string", () => {
    const config = loadConfig({
      NODE_ENV: "development",
      DATABASE_URL: "postgres://station@127.0.0.1:1/station",
      ENTRA_TENANT_ID: DEFAULT_TENANT_ID,
      ENTRA_AUDIENCE: DEFAULT_AUDIENCE,
      ENTRA_ISSUER: DEFAULT_ISSUER,
      ENTRA_JWKS_URL: "http://localhost:8090/keys",
    });
    assert.equal(config.auth.issuer, DEFAULT_ISSUER);
  });

  for (const [what, env] of [
    ["a tenant that is not a GUID", { DEV_IDP_TENANT_ID: "chapter" }],
    ["an issuer that is not a URL", { DEV_IDP_ISSUER: "dev-idp" }],
    ["an empty audience", { DEV_IDP_AUDIENCE: " " }],
    ["a bad port", { PORT: "80a" }],
    ["a port out of range", { PORT: "70000" }],
  ] as const) {
    it(`refuses ${what}`, () => {
      assert.throws(() => loadDevIdpConfig(env), /dev-idp/);
    });
  }

  for (const value of ["production", "Production", " production "]) {
    it(`refuses NODE_ENV=${JSON.stringify(value)}`, () => {
      assert.throws(() => loadDevIdpConfig({ NODE_ENV: value }), /production/);
    });
  }
});

interface ChildResult {
  readonly code: number | null;
  readonly stdout: string;
  readonly stderr: string;
}

function runServer(env: Record<string, string>, timeoutMs = 10_000): Promise<ChildResult> {
  const child = spawn(process.execPath, [SERVER_PATH], {
    env: { PATH: process.env.PATH ?? "", ...env },
    stdio: ["ignore", "pipe", "pipe"],
  });
  let stdout = "";
  let stderr = "";
  child.stdout.on("data", (chunk: Buffer) => (stdout += chunk.toString("utf8")));
  child.stderr.on("data", (chunk: Buffer) => (stderr += chunk.toString("utf8")));
  const timer = setTimeout(() => child.kill("SIGKILL"), timeoutMs);
  return once(child, "exit").then(([code]) => {
    clearTimeout(timer);
    return { code: code as number | null, stdout, stderr };
  });
}

describe("dev-idp process", () => {
  it("refuses to start when NODE_ENV is production", async () => {
    const result = await runServer({ NODE_ENV: "production", PORT: "0" });
    assert.notEqual(result.code, 0);
    assert.notEqual(result.code, null, "exited by itself, not by the timeout");
    assert.match(result.stderr, /refus.*production/i);
    assert.doesNotMatch(result.stdout, /listening/);
  });

  it("refuses to start with an invalid configuration", async () => {
    const result = await runServer({ NODE_ENV: "development", DEV_IDP_TENANT_ID: "x" });
    assert.notEqual(result.code, 0);
    assert.match(result.stderr, /DEV_IDP_TENANT_ID/);
  });

  it("starts, issues tokens, never logs them or the key, and stops on SIGTERM", async () => {
    const child = spawn(process.execPath, [SERVER_PATH], {
      env: { PATH: process.env.PATH ?? "", NODE_ENV: "development", PORT: "0" },
      stdio: ["ignore", "pipe", "pipe"],
    });
    let output = "";
    child.stdout.on("data", (chunk: Buffer) => (output += chunk.toString("utf8")));
    child.stderr.on("data", (chunk: Buffer) => (output += chunk.toString("utf8")));
    try {
      const port = await new Promise<number>((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error(`no listening line: ${output}`)), 10_000);
        child.stdout.on("data", () => {
          const match = /listening on http:\/\/127\.0\.0\.1:(\d+)/.exec(output);
          if (match?.[1] !== undefined) {
            clearTimeout(timer);
            resolve(Number(match[1]));
          }
        });
      });
      const url = `http://127.0.0.1:${port}`;
      const token = await requestToken(url, { roles: ["capture"], name: "Log Probe" });
      const jwks = (await (await fetch(`${url}/keys`)).json()) as { keys: { n: string }[] };
      const modulus = jwks.keys[0]?.n ?? "";
      assert.ok(modulus.length > 0);
      const exit = once(child, "exit");
      child.kill("SIGTERM");
      const [code] = await exit;
      assert.equal(code, 0);
      assert.ok(!output.includes(token), "token logged");
      assert.ok(!output.includes(token.split(".")[2] ?? "-"), "signature logged");
      assert.ok(!output.includes(modulus.slice(0, 40)), "key logged");
      assert.doesNotMatch(output, /PRIVATE KEY|"d":/);
    } finally {
      child.kill("SIGKILL");
    }
  });
});

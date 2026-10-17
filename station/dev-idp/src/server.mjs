// @ts-check
// dev-idp: local test sign-in for the station stack. LOCAL STACK ONLY.
//
// Issues short-lived RS256 access tokens shaped like Microsoft Entra v2.0 tokens, with every
// claim the station auth plugin checks (station/api/src/core/auth.ts): iss, aud, tid, oid, sub,
// name, roles, iat, nbf, exp and the kid header. The station API accepts them when its
// ENTRA_ISSUER, ENTRA_AUDIENCE, ENTRA_TENANT_ID and ENTRA_JWKS_URL point at this service.
//
//   GET  /keys    JWKS with the public signing key
//   POST /token   {"roles": ["capture"|"bim"|"admin", ...], "sub"?: string, "name"?: string}
//                 -> {"access_token", "token_type": "Bearer", "expires_in"}
//
// Rules:
// - Plain Node, built-ins only (node:http, node:crypto), so the compose file runs this file
//   directly with the pinned Node image: no build, no npm install.
// - A fresh 2048-bit RSA key is generated at start and kept in memory only (never on disk).
// - Refuses to start when NODE_ENV is production.
// - Tokens live at most MAX_TOKEN_LIFETIME_SECONDS (1 hour). The lifetime cannot be requested.
// - Tokens, keys and request bodies are never logged.
// - Binds 127.0.0.1 unless HOST says otherwise (the compose file sets HOST=0.0.0.0 inside the
//   container and publishes the port on 127.0.0.1 only).
//
// Environment (defaults in brackets; the defaults match station/api/.env.example):
// - NODE_ENV [unset]; "production" is refused
// - DEV_IDP_ISSUER [http://localhost:8090/] the `iss` value (ENTRA_ISSUER on the station)
// - DEV_IDP_AUDIENCE [api://chapter-capture-station-local] the `aud` value
// - DEV_IDP_TENANT_ID [00000000-0000-0000-0000-000000000000] the `tid` value
// - HOST [127.0.0.1], PORT [8090]

import { createHash, generateKeyPairSync, sign } from "node:crypto";
import { createServer } from "node:http";
import { pathToFileURL } from "node:url";

/** Station app roles (station/api/src/core/auth.ts ROLES). */
export const ROLES = /** @type {const} */ (["capture", "bim", "admin"]);

/** @typedef {(typeof ROLES)[number]} Role */

export const MAX_TOKEN_LIFETIME_SECONDS = 3600;
export const DEFAULT_ISSUER = "http://localhost:8090/";
export const DEFAULT_AUDIENCE = "api://chapter-capture-station-local";
export const DEFAULT_TENANT_ID = "00000000-0000-0000-0000-000000000000";
export const DEFAULT_PORT = 8090;
export const DEFAULT_HOST = "127.0.0.1";
/** Object id used when a token request names no `sub`. */
export const DEFAULT_SUBJECT = "00000000-0000-4000-8000-00000000d001";
export const DEFAULT_NAME = "Dev Test User";

/** Largest accepted POST /token body in bytes. */
const MAX_BODY_BYTES = 4096;
/** The station rejects an oid longer than 128 characters. */
const MAX_SUBJECT_LENGTH = 128;
/** The station truncates names to 200 characters. */
const MAX_NAME_LENGTH = 200;
const GUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
/** Printable ASCII without spaces. */
const SUBJECT_PATTERN = /^[\x21-\x7e]+$/;
/** No control, format (bidi), line or paragraph separator characters. */
const NAME_FORBIDDEN = /[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]/u;

/**
 * @typedef {object} DevIdpConfig
 * @property {string} issuer
 * @property {string} audience
 * @property {string} tenantId
 * @property {string} host
 * @property {number} port
 */

/**
 * @typedef {object} TokenRequest
 * @property {Role[]} roles
 * @property {string} [sub]
 * @property {string} [name]
 */

export class DevIdpConfigError extends Error {
  /** @param {string[]} issues */
  constructor(issues) {
    super(`dev-idp: invalid configuration:\n${issues.map((issue) => `- ${issue}`).join("\n")}`);
    this.name = "DevIdpConfigError";
    this.issues = issues;
  }
}

/**
 * Reads and validates the configuration. Throws DevIdpConfigError (variable names only, never
 * values) and always refuses NODE_ENV=production.
 * @param {Readonly<Record<string, string | undefined>>} env
 * @returns {DevIdpConfig}
 */
export function loadDevIdpConfig(env) {
  /** @param {string} name */
  const raw = (name) => {
    const value = env[name]?.trim();
    return value === undefined || value === "" ? undefined : value;
  };

  if (raw("NODE_ENV")?.toLowerCase() === "production") {
    throw new DevIdpConfigError([
      "dev-idp refuses to start when NODE_ENV is production: it issues test tokens for the local stack only",
    ]);
  }

  /** @type {string[]} */
  const issues = [];

  const issuer = raw("DEV_IDP_ISSUER") ?? DEFAULT_ISSUER;
  try {
    const parsed = new URL(issuer);
    if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
      issues.push("DEV_IDP_ISSUER must be an absolute http(s) URL");
    }
  } catch {
    issues.push("DEV_IDP_ISSUER must be an absolute http(s) URL");
  }
  if (issuer.length > 200) {
    issues.push("DEV_IDP_ISSUER must be at most 200 characters");
  }

  const audienceSet = env.DEV_IDP_AUDIENCE !== undefined;
  const audience = raw("DEV_IDP_AUDIENCE") ?? (audienceSet ? "" : DEFAULT_AUDIENCE);
  if (audience === "" || audience.length > 200 || audience.includes(",")) {
    issues.push("DEV_IDP_AUDIENCE must be one non-empty value of at most 200 characters");
  }

  const tenantId = (raw("DEV_IDP_TENANT_ID") ?? DEFAULT_TENANT_ID).toLowerCase();
  if (!GUID.test(tenantId)) {
    issues.push("DEV_IDP_TENANT_ID must be a GUID");
  }

  const host = raw("HOST") ?? DEFAULT_HOST;
  const portText = raw("PORT") ?? String(DEFAULT_PORT);
  const port = Number(portText);
  if (!/^\d{1,5}$/.test(portText) || port > 65535) {
    issues.push("PORT must be an integer from 0 to 65535");
  }

  if (issues.length > 0) {
    throw new DevIdpConfigError(issues);
  }
  return { issuer, audience, tenantId, host, port };
}

/**
 * @param {unknown} value
 * @returns {value is Role}
 */
function isRole(value) {
  return typeof value === "string" && /** @type {readonly string[]} */ (ROLES).includes(value);
}

/**
 * Validates a POST /token body. Returns the request or a token-free error message.
 * @param {unknown} body
 * @returns {{ ok: true, value: TokenRequest } | { ok: false, error: string }}
 */
export function parseTokenRequest(body) {
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return { ok: false, error: "the body must be a JSON object" };
  }
  const record = /** @type {Record<string, unknown>} */ (body);
  const unknown = Object.keys(record).filter((key) => !["roles", "sub", "name"].includes(key));
  if (unknown.length > 0) {
    return { ok: false, error: "only roles, sub and name are accepted" };
  }

  const roles = record.roles;
  if (!Array.isArray(roles) || roles.length === 0) {
    return { ok: false, error: `roles must be a non-empty array of ${ROLES.join(", ")}` };
  }
  if (!roles.every(isRole)) {
    return { ok: false, error: `roles must be a non-empty array of ${ROLES.join(", ")}` };
  }
  if (new Set(roles).size !== roles.length) {
    return { ok: false, error: "roles must not repeat" };
  }

  /** @type {TokenRequest} */
  const value = { roles: [...roles] };

  if (record.sub !== undefined) {
    const sub = record.sub;
    if (typeof sub !== "string" || sub.length > MAX_SUBJECT_LENGTH || !SUBJECT_PATTERN.test(sub)) {
      return {
        ok: false,
        error: `sub must be 1 to ${MAX_SUBJECT_LENGTH} printable ASCII characters without spaces`,
      };
    }
    value.sub = sub;
  }

  if (record.name !== undefined) {
    const name = record.name;
    if (
      typeof name !== "string" ||
      name.trim().length === 0 ||
      name.length > MAX_NAME_LENGTH ||
      NAME_FORBIDDEN.test(name)
    ) {
      return {
        ok: false,
        error: `name must be 1 to ${MAX_NAME_LENGTH} printable characters`,
      };
    }
    value.name = name;
  }

  return { ok: true, value };
}

/** @param {unknown} value */
function base64urlJson(value) {
  return Buffer.from(JSON.stringify(value), "utf8").toString("base64url");
}

/**
 * The dev-idp: a fresh in-memory signing key, token minting and the HTTP server.
 * @param {DevIdpConfig} config
 */
export function createDevIdp(config) {
  const { publicKey, privateKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
  const exported = /** @type {{ kty: string, n: string, e: string }} */ (
    publicKey.export({ format: "jwk" })
  );
  // RFC 7638 thumbprint as the key id: changes with every start.
  const kid = createHash("sha256")
    .update(JSON.stringify({ e: exported.e, kty: exported.kty, n: exported.n }))
    .digest("base64url");
  const jwksBody = JSON.stringify({
    keys: [{ kty: exported.kty, n: exported.n, e: exported.e, kid, alg: "RS256", use: "sig" }],
  });

  /**
   * Signs a token for a validated request. nowSeconds is for tests (expired tokens); the HTTP
   * API always uses the current time.
   * @param {TokenRequest} request
   * @param {number} [nowSeconds]
   * @returns {string}
   */
  function mint(request, nowSeconds = Math.floor(Date.now() / 1000)) {
    const subject = request.sub ?? DEFAULT_SUBJECT;
    const header = { alg: "RS256", typ: "JWT", kid };
    const payload = {
      iss: config.issuer,
      aud: config.audience,
      tid: config.tenantId,
      oid: subject,
      sub: subject,
      name: request.name ?? DEFAULT_NAME,
      roles: [...request.roles],
      iat: nowSeconds,
      nbf: nowSeconds,
      exp: nowSeconds + MAX_TOKEN_LIFETIME_SECONDS,
    };
    const signingInput = `${base64urlJson(header)}.${base64urlJson(payload)}`;
    const signature = sign("sha256", Buffer.from(signingInput, "ascii"), privateKey);
    return `${signingInput}.${signature.toString("base64url")}`;
  }

  /**
   * @param {import("node:http").ServerResponse} response
   * @param {number} status
   * @param {unknown} body
   * @param {Record<string, string>} [headers]
   */
  function sendJson(response, status, body, headers = {}) {
    const text = JSON.stringify(body);
    response.writeHead(status, {
      "content-type": "application/json; charset=utf-8",
      "content-length": Buffer.byteLength(text),
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
      ...headers,
    });
    response.end(text);
  }

  /**
   * @param {import("node:http").ServerResponse} response
   * @param {string} detail
   */
  function badRequest(response, detail) {
    sendJson(response, 400, { error: "invalid_request", error_description: detail });
  }

  /**
   * @param {import("node:http").IncomingMessage} request
   * @param {import("node:http").ServerResponse} response
   */
  function handleToken(request, response) {
    const contentType = String(request.headers["content-type"] ?? "")
      .split(";")[0]
      ?.trim()
      .toLowerCase();
    if (contentType !== "application/json") {
      request.resume();
      badRequest(response, "the body must be application/json");
      return;
    }
    /** @type {Buffer[]} */
    const chunks = [];
    let size = 0;
    let rejected = false;
    request.on("data", (/** @type {Buffer} */ chunk) => {
      if (rejected) {
        return;
      }
      size += chunk.length;
      if (size > MAX_BODY_BYTES) {
        rejected = true;
        badRequest(response, `the body must be at most ${MAX_BODY_BYTES} bytes`);
        return;
      }
      chunks.push(chunk);
    });
    request.on("end", () => {
      if (rejected) {
        return;
      }
      /** @type {unknown} */
      let body;
      try {
        body = JSON.parse(Buffer.concat(chunks).toString("utf8"));
      } catch {
        badRequest(response, "the body must be valid JSON");
        return;
      }
      const parsed = parseTokenRequest(body);
      if (!parsed.ok) {
        badRequest(response, parsed.error);
        return;
      }
      const now = Math.floor(Date.now() / 1000);
      sendJson(response, 200, {
        access_token: mint(parsed.value, now),
        token_type: "Bearer",
        expires_in: MAX_TOKEN_LIFETIME_SECONDS,
      });
    });
    request.on("error", () => {
      response.destroy();
    });
  }

  const server = createServer((request, response) => {
    const path = new URL(request.url ?? "/", "http://dev-idp.invalid").pathname;
    response.on("finish", () => {
      // Method, path and status only: never bodies, tokens or keys.
      console.log(`dev-idp: ${request.method} ${path} ${response.statusCode}`);
    });

    if (path === "/keys") {
      if (request.method !== "GET" && request.method !== "HEAD") {
        request.resume();
        sendJson(response, 405, { error: "method_not_allowed" }, { allow: "GET, HEAD" });
        return;
      }
      request.resume();
      sendJson(response, 200, JSON.parse(jwksBody));
      return;
    }
    if (path === "/token") {
      if (request.method !== "POST") {
        request.resume();
        sendJson(response, 405, { error: "method_not_allowed" }, { allow: "POST" });
        return;
      }
      handleToken(request, response);
      return;
    }
    request.resume();
    sendJson(response, 404, { error: "not_found" });
  });
  server.requestTimeout = 10_000;
  server.headersTimeout = 5_000;

  return {
    kid,
    mint,
    server,
    /**
     * Starts listening. Resolves with the bound port (useful with port 0).
     * @param {number} [port]
     * @param {string} [host]
     * @returns {Promise<{ port: number, host: string }>}
     */
    listen(port = config.port, host = config.host) {
      return new Promise((resolve, reject) => {
        server.once("error", reject);
        server.listen(port, host, () => {
          server.off("error", reject);
          const address = server.address();
          const bound = typeof address === "object" && address !== null ? address.port : port;
          resolve({ port: bound, host });
        });
      });
    },
    /** @returns {Promise<void>} */
    close() {
      return new Promise((resolve, reject) => {
        server.closeAllConnections();
        server.close((error) => (error ? reject(error) : resolve()));
      });
    },
  };
}

async function main() {
  /** @type {DevIdpConfig} */
  let config;
  try {
    config = loadDevIdpConfig(process.env);
  } catch (error) {
    console.error(error instanceof Error ? error.message : "dev-idp: invalid configuration");
    process.exit(1);
  }
  const idp = createDevIdp(config);
  const { port, host } = await idp.listen();
  const shown = host.includes(":") ? `[${host}]` : host;
  console.log(
    `dev-idp: listening on http://${shown}:${port} (local test sign-in only; issuer ${config.issuer}, audience ${config.audience}, tenant ${config.tenantId})`,
  );
  const stop = () => {
    idp.close().then(
      () => process.exit(0),
      () => process.exit(1),
    );
  };
  process.once("SIGTERM", stop);
  process.once("SIGINT", stop);
}

const entry = process.argv[1];
if (entry !== undefined && import.meta.url === pathToFileURL(entry).href) {
  main().catch((error) => {
    console.error(
      `dev-idp: failed to start: ${error instanceof Error ? error.message : "unknown error"}`,
    );
    process.exit(1);
  });
}

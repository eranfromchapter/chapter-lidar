// Test helpers: an in-process Entra stand-in (RSA key + JWKS on 127.0.0.1), token minting,
// a test configuration and a fake database. No network beyond loopback, no Docker.

import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { Writable } from "node:stream";
import {
  exportJWK,
  generateKeyPair,
  SignJWT,
  type CryptoKey,
  type JWK,
  type JWTPayload,
} from "jose";
import type { QueryResult, QueryResultRow } from "pg";
import { type StationConfig, loadConfig } from "../../src/core/config.js";
import type { Database, Queryable } from "../../src/core/db.js";

export const TENANT_ID = "4f1c2b8a-1d2e-4c3b-9a8f-0123456789ab";
export const OTHER_TENANT_ID = "9e8d7c6b-5a49-4382-8170-fedcba987654";
export const AUDIENCE = "api://chapter-capture-station-test";
export const SECOND_AUDIENCE = "6a1e0c55-0f7e-4f0a-8f43-1c2d3e4f5a6b";
export const ISSUER = `https://login.microsoftonline.com/${TENANT_ID}/v2.0`;
export const USER_OID = "0c7f5e2a-3b4d-4e6f-8a9b-1c2d3e4f5a6b";

export interface TestIssuer {
  readonly jwksUrl: string;
  readonly kid: string;
  /** Signs a token with the issuer key. Claims override the valid defaults; null removes one. */
  mint(claims?: Record<string, unknown>, options?: MintOptions): Promise<string>;
  /** Signs with a key that is not in the JWKS. */
  mintWithForeignKey(claims?: Record<string, unknown>, kid?: string): Promise<string>;
  close(): Promise<void>;
}

export interface MintOptions {
  readonly expiresInSeconds?: number;
  readonly notBeforeSeconds?: number;
  readonly issuedAtSeconds?: number;
}

function defaultClaims(): Record<string, unknown> {
  return {
    iss: ISSUER,
    aud: AUDIENCE,
    tid: TENANT_ID,
    oid: USER_OID,
    name: "Dana Field",
    preferred_username: "dana@hellochapter.com",
    roles: ["capture"],
    ver: "2.0",
  };
}

async function sign(
  privateKey: CryptoKey,
  kid: string,
  claims: Record<string, unknown> = {},
  options: MintOptions = {},
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const merged: Record<string, unknown> = { ...defaultClaims(), ...claims };
  for (const [key, value] of Object.entries(merged)) {
    if (value === null) {
      delete merged[key];
    }
  }
  const jwt = new SignJWT(merged as JWTPayload)
    .setProtectedHeader({ alg: "RS256", kid, typ: "JWT" })
    .setIssuedAt(now + (options.issuedAtSeconds ?? -10))
    .setExpirationTime(now + (options.expiresInSeconds ?? 3600));
  if (options.notBeforeSeconds !== undefined) {
    jwt.setNotBefore(now + options.notBeforeSeconds);
  }
  return jwt.sign(privateKey);
}

export async function startTestIssuer(): Promise<TestIssuer> {
  const kid = "test-key-1";
  const { publicKey, privateKey } = await generateKeyPair("RS256", { extractable: true });
  const foreign = await generateKeyPair("RS256");
  const jwk: JWK = { ...(await exportJWK(publicKey)), kid, alg: "RS256", use: "sig" };

  const server: Server = createServer((request, response) => {
    if (request.url === "/discovery/v2.0/keys") {
      response.writeHead(200, { "content-type": "application/json" });
      response.end(JSON.stringify({ keys: [jwk] }));
      return;
    }
    response.writeHead(404).end();
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address() as AddressInfo;

  return {
    jwksUrl: `http://127.0.0.1:${port}/discovery/v2.0/keys`,
    kid,
    mint: (claims, options) => sign(privateKey, kid, claims, options),
    mintWithForeignKey: (claims, foreignKid = kid) =>
      sign(foreign.privateKey, foreignKid, claims, {}),
    close: () =>
      new Promise<void>((resolve, reject) => {
        server.closeAllConnections();
        server.close((error) => (error ? reject(error) : resolve()));
      }),
  };
}

export function testEnv(
  overrides: Record<string, string | undefined> = {},
): Record<string, string> {
  const env: Record<string, string | undefined> = {
    NODE_ENV: "test",
    LOG_LEVEL: "info",
    DATABASE_URL: "postgres://station@127.0.0.1:1/station_test",
    ENTRA_TENANT_ID: TENANT_ID,
    ENTRA_AUDIENCE: `${AUDIENCE},${SECOND_AUDIENCE}`,
    ENTRA_JWKS_URL: "http://127.0.0.1:1/discovery/v2.0/keys",
    STATION_VERSION: "1.0.0-test",
    ...overrides,
  };
  return Object.fromEntries(
    Object.entries(env).filter((entry): entry is [string, string] => entry[1] !== undefined),
  );
}

export function testConfig(overrides: Record<string, string | undefined> = {}): StationConfig {
  return loadConfig(testEnv(overrides));
}

export interface RecordedQuery {
  readonly text: string;
  readonly values: readonly unknown[];
}

export interface FakeDatabase extends Database {
  readonly queries: RecordedQuery[];
  pingFails: boolean;
}

/** In-memory Database: records queries and answers each with one row {audit_id: n}. */
export function fakeDatabase(): FakeDatabase {
  const queries: RecordedQuery[] = [];
  const query = async <R extends QueryResultRow>(text: string, values: readonly unknown[] = []) => {
    queries.push({ text, values });
    return {
      rows: [{ audit_id: queries.length }],
      rowCount: 1,
      command: "INSERT",
      oid: 0,
      fields: [],
    } as unknown as QueryResult<R>;
  };
  const db: FakeDatabase = {
    queries,
    pingFails: false,
    query,
    async transaction<T>(fn: (tx: Queryable) => Promise<T>): Promise<T> {
      return fn({ query });
    },
    async ping() {
      if (db.pingFails) {
        throw new Error("connect ECONNREFUSED 127.0.0.1:1");
      }
    },
    async close() {},
  };
  return db;
}

/** Collects log lines written by the app's logger. */
export function logCollector(): { lines: string[]; stream: Writable } {
  const lines: string[] = [];
  const stream = new Writable({
    write(chunk: Buffer, _encoding, callback) {
      lines.push(...chunk.toString("utf8").split("\n").filter(Boolean));
      callback();
    },
  });
  return { lines, stream };
}

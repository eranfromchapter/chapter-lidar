// Postgres sign-in: Entra access tokens for the managed identity used as the pg password
// (DB_AUTH=entra), or a connection string (DB_AUTH=url). A fake credential stands in for the
// managed identity; no network.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import type { AccessToken, GetTokenOptions, TokenCredential } from "@azure/identity";
import { ManagedIdentityCredential } from "@azure/identity";
import { loadDatabaseConfig, type DatabaseConnection } from "../../src/core/config.js";
import {
  POSTGRES_ENTRA_SCOPE,
  createDatabaseCredential,
  createEntraTokenProvider,
  pgConnectionConfig,
} from "../../src/core/db.js";
import { runMigrations } from "../../src/core/migrate.js";

const ENTRA: DatabaseConnection = {
  auth: "entra",
  host: "chapter-station.postgres.database.azure.com",
  port: 5432,
  database: "station",
  user: "id-chapter-station-api",
  sslMode: "require",
};

class FakeCredential implements TokenCredential {
  calls: string[][] = [];
  tokens: (AccessToken | null | Error)[];

  constructor(...tokens: (AccessToken | null | Error)[]) {
    this.tokens = tokens;
  }

  async getToken(
    scopes: string | string[],
    _options?: GetTokenOptions,
  ): Promise<AccessToken | null> {
    this.calls.push(Array.isArray(scopes) ? scopes : [scopes]);
    const next = this.tokens.shift();
    if (next instanceof Error) {
      throw next;
    }
    return next ?? null;
  }
}

function token(value: string, expiresInMs: number, now: number): AccessToken {
  return { token: value, expiresOnTimestamp: now + expiresInMs };
}

describe("createEntraTokenProvider", () => {
  it("asks for the Azure Database for PostgreSQL scope", async () => {
    const now = 1_000_000;
    const credential = new FakeCredential(token("tok-1", 3_600_000, now));
    const provider = createEntraTokenProvider(credential, { now: () => now });
    assert.equal(await provider(), "tok-1");
    assert.deepEqual(credential.calls, [[POSTGRES_ENTRA_SCOPE]]);
    assert.equal(POSTGRES_ENTRA_SCOPE, "https://ossrdbms-aad.database.windows.net/.default");
  });

  it("reuses the token until shortly before it expires, then refreshes it", async () => {
    let now = 1_000_000;
    const credential = new FakeCredential(
      token("tok-1", 60 * 60_000, now),
      token("tok-2", 60 * 60_000 + 56 * 60_000, now),
    );
    const provider = createEntraTokenProvider(credential, { now: () => now });
    assert.equal(await provider(), "tok-1");
    now += 50 * 60_000; // 10 minutes left: still fresh
    assert.equal(await provider(), "tok-1");
    assert.equal(credential.calls.length, 1);
    now += 6 * 60_000; // 4 minutes left: inside the 5-minute refresh margin
    assert.equal(await provider(), "tok-2");
    assert.equal(credential.calls.length, 2);
  });

  it("shares one request between concurrent connections", async () => {
    const now = 1_000_000;
    const credential = new FakeCredential(token("tok-1", 3_600_000, now));
    const provider = createEntraTokenProvider(credential, { now: () => now });
    const values = await Promise.all([provider(), provider(), provider()]);
    assert.deepEqual(values, ["tok-1", "tok-1", "tok-1"]);
    assert.equal(credential.calls.length, 1);
  });

  it("fails (no fallback) when the credential fails or returns nothing, then retries", async () => {
    const now = 1_000_000;
    const credential = new FakeCredential(
      new Error("ManagedIdentityCredential: no managed identity endpoint"),
      null,
      token("tok-3", 3_600_000, now),
    );
    const provider = createEntraTokenProvider(credential, { now: () => now });
    await assert.rejects(provider(), /Postgres Entra token.*no managed identity endpoint/);
    await assert.rejects(provider(), /returned no token/);
    assert.equal(await provider(), "tok-3");
  });
});

describe("pgConnectionConfig", () => {
  it("connects with the managed identity's role, verified TLS and the token as password", async () => {
    const now = 1_000_000;
    const credential = new FakeCredential(token("secret-token-value", 3_600_000, now));
    const provider = createEntraTokenProvider(credential, { now: () => now });
    const config = pgConnectionConfig(ENTRA, provider);
    assert.equal(config.host, ENTRA.host);
    assert.equal(config.port, 5432);
    assert.equal(config.database, "station");
    assert.equal(config.user, "id-chapter-station-api");
    assert.equal(config.connectionString, undefined);
    assert.deepEqual(config.ssl, { rejectUnauthorized: true });
    assert.equal(typeof config.password, "function");
    const password = config.password as () => Promise<string>;
    assert.equal(await password(), "secret-token-value");
    assert.ok(!JSON.stringify(config).includes("secret-token-value"));
  });

  it("verifies the server certificate for sslmode verify-full too", () => {
    const config = pgConnectionConfig({ ...ENTRA, sslMode: "verify-full" }, async () => "t");
    assert.deepEqual(config.ssl, { rejectUnauthorized: true });
  });

  it("refuses Entra mode without a token provider", () => {
    assert.throws(() => pgConnectionConfig(ENTRA), /token provider/);
  });

  it("uses the connection string in url mode", () => {
    const url = "postgres://station@127.0.0.1:55432/station";
    assert.deepEqual(pgConnectionConfig({ auth: "url", url }), { connectionString: url });
  });

  it("builds the server and migration connection from the same database config", async () => {
    const { database } = loadDatabaseConfig({
      NODE_ENV: "production",
      DB_AUTH: "entra",
      PGHOST: ENTRA.host,
      PGDATABASE: "station",
      PGUSER: "id-chapter-station-api",
      PGSSLMODE: "require",
    });
    assert.deepEqual(database.connection, { ...ENTRA });
    const config = pgConnectionConfig(database.connection, async () => "t");
    assert.equal(config.user, "id-chapter-station-api");
  });

  it("does not attempt a migration connection in Entra mode without a token provider", async () => {
    await assert.rejects(runMigrations({ connection: ENTRA }), /token provider/);
  });
});

describe("createDatabaseCredential", () => {
  it("uses the managed identity (user-assigned when a client id is set)", () => {
    assert.ok(createDatabaseCredential(ENTRA) instanceof ManagedIdentityCredential);
    assert.ok(
      createDatabaseCredential({
        ...ENTRA,
        managedIdentityClientId: "6a1e0c55-0f7e-4f0a-8f43-1c2d3e4f5a6b",
      }) instanceof ManagedIdentityCredential,
    );
  });
});

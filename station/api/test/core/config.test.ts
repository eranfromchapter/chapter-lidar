import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import { ConfigError, describeConfig, loadConfig } from "../../src/core/config.js";
import { AUDIENCE, SECOND_AUDIENCE, TENANT_ID, testEnv } from "./helpers.js";

function issuesOf(env: Record<string, string | undefined>): readonly string[] {
  try {
    loadConfig(env);
  } catch (error) {
    assert.ok(error instanceof ConfigError);
    return error.issues;
  }
  assert.fail("expected a ConfigError");
}

describe("loadConfig", () => {
  it("applies defaults and derives the Entra endpoints from the tenant", () => {
    const config = loadConfig({
      DATABASE_URL: "postgres://station@localhost:5432/station",
      ENTRA_TENANT_ID: TENANT_ID.toUpperCase(),
      ENTRA_AUDIENCE: ` ${AUDIENCE} , ${SECOND_AUDIENCE} `,
    });
    const version = (
      JSON.parse(readFileSync(new URL("../../package.json", import.meta.url), "utf8")) as {
        version: string;
      }
    ).version;
    assert.equal(config.env, "development");
    assert.equal(config.version, version);
    assert.deepEqual(config.server, {
      host: "0.0.0.0",
      port: 8080,
      logLevel: "info",
      bodyLimitBytes: 4 * 1024 * 1024,
    });
    assert.equal(config.database.migrateOnStart, false);
    assert.equal(config.auth.tenantId, TENANT_ID);
    assert.deepEqual(config.auth.audiences, [AUDIENCE, SECOND_AUDIENCE]);
    assert.equal(config.auth.issuer, `https://login.microsoftonline.com/${TENANT_ID}/v2.0`);
    assert.equal(
      config.auth.jwksUrl,
      `https://login.microsoftonline.com/${TENANT_ID}/discovery/v2.0/keys`,
    );
    assert.equal(config.hub.mode, "fake");
    assert.equal(config.storage.originalsContainer, "originals");
  });

  it("reports every missing required variable at once", () => {
    const issues = issuesOf({});
    assert.ok(issues.some((issue) => issue.startsWith("DATABASE_URL")));
    assert.ok(issues.some((issue) => issue.startsWith("ENTRA_TENANT_ID")));
    assert.ok(issues.some((issue) => issue.startsWith("ENTRA_AUDIENCE")));
  });

  it("never puts a variable value in the error", () => {
    const secret = "postgres-but-not-really-hunter2";
    let message = "";
    try {
      loadConfig(testEnv({ DATABASE_URL: secret, PORT: "nope" }));
    } catch (error) {
      message = (error as Error).message;
    }
    assert.match(message, /DATABASE_URL/);
    assert.match(message, /PORT/);
    assert.ok(!message.includes(secret));
  });

  it("validates formats", () => {
    const issues = issuesOf(
      testEnv({
        ENTRA_TENANT_ID: "chapter-main",
        PORT: "70000",
        LOG_LEVEL: "loud",
        MIGRATE_ON_START: "yes",
        HUB_MODE: "sandbox",
        STORAGE_ORIGINALS_CONTAINER: "Originals_Bad",
      }),
    );
    for (const name of [
      "ENTRA_TENANT_ID",
      "PORT",
      "LOG_LEVEL",
      "MIGRATE_ON_START",
      "HUB_MODE",
      "STORAGE_ORIGINALS_CONTAINER",
    ]) {
      assert.ok(
        issues.some((issue) => issue.startsWith(name)),
        `${name} not reported: ${issues.join("; ")}`,
      );
    }
  });

  it("requires https for Entra endpoints except on loopback", () => {
    assert.ok(
      issuesOf(testEnv({ ENTRA_JWKS_URL: "http://login.example.com/keys" })).some((issue) =>
        issue.startsWith("ENTRA_JWKS_URL"),
      ),
    );
    assert.ok(
      issuesOf(testEnv({ ENTRA_ISSUER: "not a url" })).some((issue) =>
        issue.startsWith("ENTRA_ISSUER"),
      ),
    );
    const local = loadConfig(testEnv({ ENTRA_JWKS_URL: "http://localhost:9999/keys" }));
    assert.equal(local.auth.jwksUrl, "http://localhost:9999/keys");
  });

  it("refuses the fake HUB in production", () => {
    assert.ok(
      issuesOf(testEnv({ NODE_ENV: "production", HUB_MODE: "fake" })).some((issue) =>
        issue.startsWith("HUB_MODE"),
      ),
    );
    assert.equal(
      loadConfig(testEnv({ NODE_ENV: "production", HUB_MODE: "live" })).hub.mode,
      "live",
    );
  });

  it("parses booleans and integers", () => {
    const config = loadConfig(
      testEnv({ MIGRATE_ON_START: "TRUE", PORT: "9090", DB_POOL_MAX: "3", LOG_LEVEL: "silent" }),
    );
    assert.equal(config.database.migrateOnStart, true);
    assert.equal(config.server.port, 9090);
    assert.equal(config.database.poolMax, 3);
    assert.equal(config.server.logLevel, "silent");
  });

  it("describeConfig leaves out connection strings", () => {
    const config = loadConfig(
      testEnv({
        // Fake credentials, assembled at runtime so secret scanners do not flag the test.
        DATABASE_URL: ["postgres://station", "pw-123@db.internal:5432/station"].join(":"),
        AZURE_STORAGE_CONNECTION_STRING: "AccountName=x;AccountKey=abc123==",
      }),
    );
    const text = JSON.stringify(describeConfig(config));
    assert.ok(!text.includes("pw-123"));
    assert.ok(!text.includes("abc123"));
    assert.match(text, /connection-string/);
  });
});

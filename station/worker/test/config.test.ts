import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { ConfigError, describeConfig, loadConfig } from "../src/config.js";

const CREDENTIAL = "hub-credential-value-123";
// Built from parts so the secret scanner does not flag test values.
const DB_URL = ["postgres://station", ":pw-secret", "@127.0.0.1:5432/station"].join("");
const MYSQL_URL = ["mysql://x", ":pw-secret", "@h/db"].join("");
const CONN =
  "DefaultEndpointsProtocol=http;AccountName=a;AccountKey=key-secret;BlobEndpoint=http://127.0.0.1:10000/a;";

const LOCAL = {
  NODE_ENV: "development",
  DB_AUTH: "url",
  DATABASE_URL: DB_URL,
  AZURE_STORAGE_CONNECTION_STRING: CONN,
  HUB_MODE: "live",
  HUB_BASE_URL: "http://127.0.0.1:9999",
  HUB_SERVICE_CREDENTIAL: CREDENTIAL,
  REVIEW_BASE_URL: "http://localhost:3000",
};

const AZURE = {
  NODE_ENV: "production",
  DB_AUTH: "entra",
  PGHOST: "pg-chapter.postgres.database.azure.com",
  PGPORT: "5432",
  PGDATABASE: "station",
  PGUSER: "ca-capture-worker-prod",
  PGSSLMODE: "require",
  AZURE_STORAGE_ACCOUNT_URL: "https://stchapter.blob.core.windows.net",
  STORAGE_ORIGINALS_CONTAINER: "originals",
  HUB_MODE: "live",
  HUB_BASE_URL: "https://hub.hellochapter.example",
  HUB_SERVICE_CREDENTIAL: CREDENTIAL,
  REVIEW_BASE_URL: "https://review.capture.example",
  // Set by infra for every app; the worker ignores them.
  MIGRATE_ON_START: "false",
  ENTRA_TENANT_ID: "00000000-0000-0000-0000-000000000000",
  ENTRA_AUDIENCE: "api://x",
};

function issues(env: Record<string, string | undefined>): readonly string[] {
  try {
    loadConfig(env);
  } catch (error) {
    if (error instanceof ConfigError) {
      return error.issues;
    }
    throw error;
  }
  return [];
}

describe("worker config", () => {
  it("accepts the local stack settings", () => {
    const config = loadConfig(LOCAL);
    assert.equal(config.database.connection.auth, "url");
    assert.equal(config.hub.mode, "live");
    assert.equal(config.storage.originalsContainer, "originals");
    assert.equal(config.worker.lockTimeoutSeconds, 900);
  });

  it("accepts the Azure settings infra provides plus REVIEW_BASE_URL", () => {
    const config = loadConfig(AZURE);
    assert.equal(config.database.connection.auth, "entra");
    assert.equal(config.storage.accountUrl, "https://stchapter.blob.core.windows.net");
  });

  it("refuses to start without REVIEW_BASE_URL (no default)", () => {
    const { REVIEW_BASE_URL: _unused, ...env } = AZURE;
    assert.ok(issues(env).some((issue) => issue.startsWith("REVIEW_BASE_URL is required")));
    assert.ok(
      issues({ ...LOCAL, REVIEW_BASE_URL: "http://review.example" }).some((i) =>
        i.startsWith("REVIEW_BASE_URL"),
      ),
    );
    assert.ok(
      issues({ ...LOCAL, REVIEW_BASE_URL: "https://review.example/?x=1" }).some((i) =>
        i.startsWith("REVIEW_BASE_URL"),
      ),
    );
  });

  it("refuses the fake HUB, url sign-in and http HUB in production", () => {
    assert.ok(
      issues({ ...AZURE, HUB_MODE: "fake" }).includes(
        "HUB_MODE must be live when NODE_ENV is production",
      ),
    );
    assert.ok(
      issues({ ...AZURE, HUB_BASE_URL: "http://hub.example" }).some((i) =>
        i.startsWith("HUB_BASE_URL"),
      ),
    );
    const { PGHOST: _a, PGDATABASE: _b, PGUSER: _c, ...noPg } = AZURE;
    assert.ok(
      issues({ ...noPg, DB_AUTH: "url", DATABASE_URL: DB_URL }).includes(
        "DB_AUTH must be entra when NODE_ENV is production",
      ),
    );
    assert.ok(
      issues({ ...AZURE, DATABASE_URL: DB_URL }).includes(
        "DATABASE_URL must not be set when DB_AUTH is entra",
      ),
    );
  });

  it("requires storage and the live HUB settings", () => {
    const { AZURE_STORAGE_CONNECTION_STRING: _s, ...noStorage } = LOCAL;
    assert.ok(
      issues(noStorage).some((i) =>
        i.includes("AZURE_STORAGE_ACCOUNT_URL or AZURE_STORAGE_CONNECTION_STRING"),
      ),
    );
    const { HUB_SERVICE_CREDENTIAL: _h, ...noCredential } = LOCAL;
    assert.ok(
      issues(noCredential).includes("HUB_SERVICE_CREDENTIAL is required when HUB_MODE is live"),
    );
  });

  it("never exposes secrets in errors, JSON or the summary", () => {
    const config = loadConfig(LOCAL);
    const json = JSON.stringify(config) + JSON.stringify(describeConfig(config));
    for (const secret of [CREDENTIAL, "pw-secret", "key-secret"]) {
      assert.ok(!json.includes(secret), secret);
    }
    assert.equal(config.hub.serviceCredential, CREDENTIAL);
    assert.equal({ ...config.hub }.serviceCredential, undefined);
    const problems = issues({
      ...LOCAL,
      HUB_SERVICE_CREDENTIAL: "bad credential with spaces",
      DATABASE_URL: MYSQL_URL,
    });
    assert.ok(problems.length >= 2);
    assert.ok(!problems.join("\n").includes("pw-secret"));
    assert.ok(!problems.join("\n").includes("bad credential"));
  });

  it("validates the worker timings", () => {
    assert.ok(
      issues({ ...LOCAL, WORKER_LOCK_TIMEOUT_SECONDS: "60", HUB_PUBLISH_RETRY_MAX_MS: "30000" })
        .length > 0,
    );
    assert.ok(issues({ ...LOCAL, WORKER_POLL_INTERVAL_MS: "abc" }).length > 0);
  });
});

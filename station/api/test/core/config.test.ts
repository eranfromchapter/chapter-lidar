import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import {
  ConfigError,
  describeConfig,
  loadConfig,
  loadDatabaseConfig,
  loadMaintenanceConfig,
} from "../../src/core/config.js";
import { AUDIENCE, SECOND_AUDIENCE, TENANT_ID, testEnv } from "./helpers.js";

const HUB_CREDENTIAL = "hub-credential-not-a-real-one-7f3a";

/** A valid production environment: Entra database sign-in and the live HUB. */
function productionEnv(overrides: Record<string, string | undefined> = {}) {
  return testEnv({
    NODE_ENV: "production",
    DATABASE_URL: undefined,
    DB_AUTH: "entra",
    PGHOST: "chapter-station.postgres.database.azure.com",
    PGDATABASE: "station",
    PGUSER: "id-chapter-station-api",
    PGSSLMODE: "require",
    HUB_MODE: "live",
    HUB_BASE_URL: "https://hub.hellochapter.com",
    HUB_SERVICE_CREDENTIAL: HUB_CREDENTIAL,
    ...overrides,
  });
}

function issuesOf(
  env: Record<string, string | undefined>,
  load: (env: Record<string, string | undefined>) => unknown = loadConfig,
): readonly string[] {
  try {
    load(env);
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
      issuesOf(productionEnv({ HUB_MODE: "fake" })).some((issue) => issue.startsWith("HUB_MODE")),
    );
    assert.equal(loadConfig(productionEnv()).hub.mode, "live");
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

  it("keeps secrets out of JSON and describeConfig", () => {
    const local = loadConfig(
      testEnv({
        DATABASE_URL: ["postgres://station", "pw-123@db.internal:5432/station"].join(":"),
        AZURE_STORAGE_CONNECTION_STRING: "AccountName=x;AccountKey=abc123==",
        HUB_MODE: "live",
        HUB_BASE_URL: "http://localhost:4010",
        HUB_SERVICE_CREDENTIAL: HUB_CREDENTIAL,
      }),
    );
    assert.equal(local.hub.serviceCredential, HUB_CREDENTIAL);
    assert.equal(local.storage.connectionString, "AccountName=x;AccountKey=abc123==");
    assert.equal(local.database.connection.auth, "url");
    for (const text of [JSON.stringify(local), JSON.stringify(describeConfig(local))]) {
      assert.ok(!text.includes("pw-123"), text);
      assert.ok(!text.includes("abc123"), text);
      assert.ok(!text.includes(HUB_CREDENTIAL), text);
    }
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

describe("database sign-in (DB_AUTH)", () => {
  it("defaults to url mode with DATABASE_URL", () => {
    const { database } = loadDatabaseConfig({ DATABASE_URL: "postgres://station@db:5432/station" });
    assert.equal(database.connection.auth, "url");
    assert.equal(
      database.connection.auth === "url" ? database.connection.url : "",
      "postgres://station@db:5432/station",
    );
    assert.ok(issuesOf({}, loadDatabaseConfig).some((issue) => issue.startsWith("DATABASE_URL")));
  });

  it("reads only database variables for the migration entrypoint", () => {
    const { env, database } = loadDatabaseConfig(productionEnv({ ENTRA_TENANT_ID: undefined }));
    assert.equal(env, "production");
    assert.deepEqual(database.connection, {
      auth: "entra",
      host: "chapter-station.postgres.database.azure.com",
      port: 5432,
      database: "station",
      user: "id-chapter-station-api",
      sslMode: "require",
    });
  });

  it("requires Entra sign-in in production", () => {
    const issues = issuesOf(
      productionEnv({ DB_AUTH: "url", DATABASE_URL: "postgres://station@db:5432/station" }),
    );
    assert.ok(
      issues.some((issue) => issue.startsWith("DB_AUTH must be entra")),
      issues.join(),
    );
    assert.ok(
      issuesOf(productionEnv({ DB_AUTH: undefined })).some((issue) => issue.startsWith("DB_AUTH")),
    );
  });

  it("requires host, database and role, and verified TLS, in Entra mode", () => {
    const issues = issuesOf(
      productionEnv({
        PGHOST: undefined,
        PGDATABASE: undefined,
        PGUSER: undefined,
        PGSSLMODE: "disable",
        PGPORT: "0",
        AZURE_CLIENT_ID: "not-a-guid",
      }),
      loadDatabaseConfig,
    );
    for (const name of [
      "PGHOST",
      "PGDATABASE",
      "PGUSER",
      "PGSSLMODE",
      "PGPORT",
      "AZURE_CLIENT_ID",
    ]) {
      assert.ok(
        issues.some((issue) => issue.startsWith(name)),
        `${name}: ${issues.join("; ")}`,
      );
    }
  });

  it("never accepts a password or connection string in Entra mode", () => {
    const password = "do-not-accept-me-42";
    let message = "";
    try {
      loadDatabaseConfig(
        productionEnv({
          PGPASSWORD: password,
          DATABASE_URL: ["postgres://station", `${password}@db:5432/station`].join(":"),
        }),
      );
    } catch (error) {
      assert.ok(error instanceof ConfigError);
      message = error.message;
    }
    assert.match(message, /PGPASSWORD must not be set/);
    assert.match(message, /DATABASE_URL must not be set/);
    assert.ok(!message.includes(password));
  });

  it("accepts a user-assigned managed identity client id and sslmode verify-full", () => {
    const { database } = loadDatabaseConfig(
      productionEnv({
        AZURE_CLIENT_ID: "6A1E0C55-0F7E-4F0A-8F43-1C2D3E4F5A6B",
        PGSSLMODE: "verify-full",
        PGPORT: "6432",
      }),
    );
    assert.equal(database.connection.auth, "entra");
    if (database.connection.auth === "entra") {
      assert.equal(
        database.connection.managedIdentityClientId,
        "6a1e0c55-0f7e-4f0a-8f43-1c2d3e4f5a6b",
      );
      assert.equal(database.connection.sslMode, "verify-full");
      assert.equal(database.connection.port, 6432);
    }
  });
});

describe("HUB live client settings", () => {
  it("requires HUB_BASE_URL and HUB_SERVICE_CREDENTIAL when HUB_MODE is live", () => {
    const issues = issuesOf(testEnv({ HUB_MODE: "live" }));
    assert.ok(
      issues.some((issue) => issue.startsWith("HUB_BASE_URL")),
      issues.join(),
    );
    assert.ok(
      issues.some((issue) => issue.startsWith("HUB_SERVICE_CREDENTIAL")),
      issues.join(),
    );
  });

  it("requires https for the HUB in production and allows http locally", () => {
    assert.ok(
      issuesOf(productionEnv({ HUB_BASE_URL: "http://hub.hellochapter.com" })).some((issue) =>
        issue.startsWith("HUB_BASE_URL"),
      ),
    );
    const local = loadConfig(
      testEnv({
        HUB_MODE: "live",
        HUB_BASE_URL: "http://fake-hub:4010",
        HUB_SERVICE_CREDENTIAL: "x",
      }),
    );
    assert.equal(local.hub.baseUrl, "http://fake-hub:4010");
    const prod = loadConfig(productionEnv());
    assert.equal(prod.hub.baseUrl, "https://hub.hellochapter.com");
    assert.equal(prod.hub.serviceCredential, HUB_CREDENTIAL);
  });

  it("never puts the HUB credential in errors", () => {
    let message = "";
    try {
      loadConfig(productionEnv({ HUB_BASE_URL: "ftp://x", PORT: "nope" }));
    } catch (error) {
      message = (error as Error).message;
    }
    assert.match(message, /HUB_BASE_URL/);
    assert.ok(!message.includes(HUB_CREDENTIAL));
  });

  it("leaves the fake HUB without live settings", () => {
    const config = loadConfig(testEnv());
    assert.equal(config.hub.mode, "fake");
    assert.equal(config.hub.baseUrl, undefined);
    assert.equal(config.hub.serviceCredential, undefined);
  });
});

describe("links and the reports container (OpenAPI 1.1.0)", () => {
  it("leaves the links unset and the reports container at its default", () => {
    const config = loadConfig(testEnv());
    assert.deepEqual(config.links, {});
    assert.equal(config.storage.reportsContainer, "reports");
  });

  it("reads REVIEW_BASE_URL, HUB_WEB_DEAL_URL_TEMPLATE and STORAGE_REPORTS_CONTAINER", () => {
    const config = loadConfig(
      testEnv({
        REVIEW_BASE_URL: "https://review.hellochapter.com",
        HUB_WEB_DEAL_URL_TEMPLATE: "https://hub.hellochapter.com/deals/{dealId}",
        STORAGE_REPORTS_CONTAINER: "station-reports",
      }),
    );
    assert.deepEqual(config.links, {
      reviewBaseUrl: "https://review.hellochapter.com",
      hubDealUrlTemplate: "https://hub.hellochapter.com/deals/{dealId}",
    });
    assert.equal(config.storage.reportsContainer, "station-reports");
    const described = describeConfig(config);
    assert.equal(described.reportsContainer, "station-reports");
    assert.equal(described.reviewBaseUrl, "https://review.hellochapter.com");
  });

  it("refuses non-https links (except loopback), a template without {dealId} and a bad container", () => {
    const issues = issuesOf(
      testEnv({
        REVIEW_BASE_URL: "http://review.example.com",
        HUB_WEB_DEAL_URL_TEMPLATE: "https://hub.example.com/deals",
        STORAGE_REPORTS_CONTAINER: "Reports_Bad",
      }),
    );
    for (const name of [
      "REVIEW_BASE_URL",
      "HUB_WEB_DEAL_URL_TEMPLATE must contain {dealId}",
      "STORAGE_REPORTS_CONTAINER",
    ]) {
      assert.ok(
        issues.some((issue) => issue.startsWith(name)),
        `${name} not reported: ${issues.join("; ")}`,
      );
    }
    assert.ok(
      issuesOf(testEnv({ HUB_WEB_DEAL_URL_TEMPLATE: "http://hub.example.com/{dealId}" })).some(
        (issue) => issue.startsWith("HUB_WEB_DEAL_URL_TEMPLATE"),
      ),
    );
    const local = loadConfig(
      testEnv({
        REVIEW_BASE_URL: "http://localhost:3000",
        HUB_WEB_DEAL_URL_TEMPLATE: "http://localhost:4010/deals/{dealId}",
      }),
    );
    assert.equal(local.links.reviewBaseUrl, "http://localhost:3000");
  });
});

describe("maintenance scripts (loadMaintenanceConfig)", () => {
  it("reads the database and storage settings only, and requires storage", () => {
    const config = loadMaintenanceConfig({
      DATABASE_URL: "postgres://station@localhost:5432/station",
      AZURE_STORAGE_CONNECTION_STRING: "AccountName=x;AccountKey=abc123==",
    });
    assert.equal(config.database.connection.auth, "url");
    assert.equal(config.storage.originalsContainer, "originals");
    assert.ok(!JSON.stringify(config).includes("abc123"));
    const issues = issuesOf(
      { DATABASE_URL: "postgres://station@localhost:5432/station" },
      loadMaintenanceConfig,
    );
    assert.deepEqual(issues, [
      "AZURE_STORAGE_ACCOUNT_URL or AZURE_STORAGE_CONNECTION_STRING is required",
    ]);
  });
});

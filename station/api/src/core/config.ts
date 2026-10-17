// Station API configuration, read from environment variables and validated at startup.
//
// In Azure Container Apps every secret (DATABASE_URL, storage credentials) is a Key Vault
// reference exposed as a plain environment variable (secretRef), so the service only ever
// reads the environment. Validation collects every problem and reports variable names only,
// never values, so a misconfigured secret never reaches a log.

import { readFileSync } from "node:fs";

export type StationEnv = "development" | "test" | "production";
export type LogLevel = "fatal" | "error" | "warn" | "info" | "debug" | "trace" | "silent";
export type HubMode = "fake" | "live";

export interface StationConfig {
  readonly env: StationEnv;
  /** Station build version, returned by GET /health. */
  readonly version: string;
  readonly server: {
    readonly host: string;
    readonly port: number;
    readonly logLevel: LogLevel;
    /** Largest accepted request body in bytes. */
    readonly bodyLimitBytes: number;
  };
  readonly database: {
    /** Postgres connection string. Secret: never log it. */
    readonly url: string;
    readonly poolMax: number;
    /** Apply pending migrations before the server starts listening. */
    readonly migrateOnStart: boolean;
  };
  readonly auth: {
    /** Entra ID tenant id ("Chapter Main"); tokens must carry it in `tid`. */
    readonly tenantId: string;
    /** Accepted `aud` values (the station app registration's client id and/or App ID URI). */
    readonly audiences: readonly string[];
    readonly issuer: string;
    readonly jwksUrl: string;
    readonly clockToleranceSeconds: number;
  };
  readonly hub: {
    readonly mode: HubMode;
  };
  readonly storage: {
    /** Storage connection string (Azurite locally). Secret: never log it. */
    readonly connectionString?: string;
    /** Blob service URL for managed-identity access in Azure. */
    readonly accountUrl?: string;
    /** Container that holds the immutable originals. */
    readonly originalsContainer: string;
    /** Blob endpoint as seen by clients, when it differs from the one the service uses. */
    readonly publicBlobEndpoint?: string;
  };
}

export class ConfigError extends Error {
  readonly issues: readonly string[];

  constructor(issues: readonly string[]) {
    super(`Invalid station configuration:\n${issues.map((issue) => `- ${issue}`).join("\n")}`);
    this.name = "ConfigError";
    this.issues = issues;
  }
}

type Env = Readonly<Record<string, string | undefined>>;

const GUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const LOG_LEVELS: readonly LogLevel[] = [
  "fatal",
  "error",
  "warn",
  "info",
  "debug",
  "trace",
  "silent",
];
const LOOPBACK_HOSTS = new Set(["localhost", "127.0.0.1", "[::1]"]);
const CONTAINER_NAME = /^[a-z0-9](?!.*--)[a-z0-9-]{1,61}[a-z0-9]$/;

/** Version from package.json; resolves from both src/core and dist/core. */
function packageVersion(): string {
  const raw = readFileSync(new URL("../../package.json", import.meta.url), "utf8");
  const version = (JSON.parse(raw) as { version?: unknown }).version;
  return typeof version === "string" && version.length > 0 ? version : "0.0.0";
}

class Reader {
  readonly issues: string[] = [];

  constructor(private readonly env: Env) {}

  /** Trimmed value, or undefined when unset or blank. */
  raw(name: string): string | undefined {
    const value = this.env[name]?.trim();
    return value === undefined || value === "" ? undefined : value;
  }

  required(name: string): string {
    const value = this.raw(name);
    if (value === undefined) {
      this.issues.push(`${name} is required`);
      return "";
    }
    return value;
  }

  oneOf<T extends string>(name: string, allowed: readonly T[], fallback: T): T {
    const value = this.raw(name);
    if (value === undefined) {
      return fallback;
    }
    if (!(allowed as readonly string[]).includes(value)) {
      this.issues.push(`${name} must be one of ${allowed.join(", ")}`);
      return fallback;
    }
    return value as T;
  }

  integer(name: string, fallback: number, min: number, max: number): number {
    const value = this.raw(name);
    if (value === undefined) {
      return fallback;
    }
    if (!/^\d+$/.test(value) || Number(value) < min || Number(value) > max) {
      this.issues.push(`${name} must be an integer from ${min} to ${max}`);
      return fallback;
    }
    return Number(value);
  }

  boolean(name: string, fallback: boolean): boolean {
    const value = this.raw(name)?.toLowerCase();
    if (value === undefined) {
      return fallback;
    }
    if (value === "true" || value === "1") {
      return true;
    }
    if (value === "false" || value === "0") {
      return false;
    }
    this.issues.push(`${name} must be true or false`);
    return fallback;
  }

  /** Absolute http(s) URL; https is required unless the host is loopback. */
  url(name: string, value: string | undefined): string | undefined {
    if (value === undefined) {
      return undefined;
    }
    let parsed: URL;
    try {
      parsed = new URL(value);
    } catch {
      this.issues.push(`${name} must be an absolute URL`);
      return undefined;
    }
    const loopback = LOOPBACK_HOSTS.has(parsed.hostname);
    if (parsed.protocol !== "https:" && !(parsed.protocol === "http:" && loopback)) {
      this.issues.push(`${name} must use https (http is allowed only for localhost)`);
      return undefined;
    }
    return value;
  }

  /** Absolute http(s) URL without the https rule (local emulator endpoints). */
  httpUrl(name: string): string | undefined {
    const value = this.raw(name);
    if (value === undefined) {
      return undefined;
    }
    try {
      const parsed = new URL(value);
      if (parsed.protocol === "http:" || parsed.protocol === "https:") {
        return value;
      }
    } catch {
      // reported below
    }
    this.issues.push(`${name} must be an absolute http(s) URL`);
    return undefined;
  }
}

/**
 * Reads and validates the configuration. Throws ConfigError listing every problem.
 *
 * Variables (defaults in brackets):
 * - NODE_ENV development|test|production [development]
 * - STATION_VERSION [package.json version]
 * - HOST [0.0.0.0], PORT [8080], LOG_LEVEL [info], BODY_LIMIT_BYTES [4194304]
 * - DATABASE_URL (required, secret), DB_POOL_MAX [10], MIGRATE_ON_START [false]
 * - ENTRA_TENANT_ID (required), ENTRA_AUDIENCE (required, comma-separated),
 *   ENTRA_ISSUER [https://login.microsoftonline.com/<tenant>/v2.0],
 *   ENTRA_JWKS_URL [https://login.microsoftonline.com/<tenant>/discovery/v2.0/keys],
 *   ENTRA_CLOCK_TOLERANCE_SECONDS [60]
 * - HUB_MODE fake|live [fake]; fake is refused when NODE_ENV is production
 * - AZURE_STORAGE_CONNECTION_STRING (secret), AZURE_STORAGE_ACCOUNT_URL,
 *   STORAGE_ORIGINALS_CONTAINER [originals], STORAGE_PUBLIC_BLOB_ENDPOINT
 */
export function loadConfig(env: Env = process.env): StationConfig {
  const read = new Reader(env);

  const stationEnv = read.oneOf<StationEnv>(
    "NODE_ENV",
    ["development", "test", "production"],
    "development",
  );

  const version = read.raw("STATION_VERSION") ?? packageVersion();
  if (version.length > 50) {
    read.issues.push("STATION_VERSION must be at most 50 characters");
  }

  const databaseUrl = read.required("DATABASE_URL");
  if (databaseUrl !== "" && !/^postgres(?:ql)?:\/\//.test(databaseUrl)) {
    read.issues.push("DATABASE_URL must be a postgres:// or postgresql:// connection string");
  }

  const tenantId = read.required("ENTRA_TENANT_ID").toLowerCase();
  if (tenantId !== "" && !GUID.test(tenantId)) {
    read.issues.push("ENTRA_TENANT_ID must be a GUID");
  }
  const audiences = (read.raw("ENTRA_AUDIENCE") ?? "")
    .split(",")
    .map((audience) => audience.trim())
    .filter((audience) => audience.length > 0);
  if (audiences.length === 0) {
    read.issues.push("ENTRA_AUDIENCE is required (one or more values, comma-separated)");
  }
  const tenantPath = tenantId === "" ? "<tenant>" : tenantId;
  const issuer =
    read.url(
      "ENTRA_ISSUER",
      read.raw("ENTRA_ISSUER") ?? `https://login.microsoftonline.com/${tenantPath}/v2.0`,
    ) ?? "";
  const jwksUrl =
    read.url(
      "ENTRA_JWKS_URL",
      read.raw("ENTRA_JWKS_URL") ??
        `https://login.microsoftonline.com/${tenantPath}/discovery/v2.0/keys`,
    ) ?? "";

  const hubMode = read.oneOf<HubMode>("HUB_MODE", ["fake", "live"], "fake");
  if (stationEnv === "production" && hubMode === "fake") {
    read.issues.push("HUB_MODE must be live when NODE_ENV is production");
  }

  const originalsContainer = read.raw("STORAGE_ORIGINALS_CONTAINER") ?? "originals";
  if (!CONTAINER_NAME.test(originalsContainer)) {
    read.issues.push("STORAGE_ORIGINALS_CONTAINER must be a valid Azure Blob container name");
  }
  const connectionString = read.raw("AZURE_STORAGE_CONNECTION_STRING");
  const accountUrl = read.url("AZURE_STORAGE_ACCOUNT_URL", read.raw("AZURE_STORAGE_ACCOUNT_URL"));
  const publicBlobEndpoint = read.httpUrl("STORAGE_PUBLIC_BLOB_ENDPOINT");

  const config: StationConfig = {
    env: stationEnv,
    version,
    server: {
      host: read.raw("HOST") ?? "0.0.0.0",
      port: read.integer("PORT", 8080, 1, 65535),
      logLevel: read.oneOf<LogLevel>("LOG_LEVEL", LOG_LEVELS, "info"),
      bodyLimitBytes: read.integer("BODY_LIMIT_BYTES", 4 * 1024 * 1024, 1024, 64 * 1024 * 1024),
    },
    database: {
      url: databaseUrl,
      poolMax: read.integer("DB_POOL_MAX", 10, 1, 100),
      migrateOnStart: read.boolean("MIGRATE_ON_START", false),
    },
    auth: {
      tenantId,
      audiences,
      issuer,
      jwksUrl,
      clockToleranceSeconds: read.integer("ENTRA_CLOCK_TOLERANCE_SECONDS", 60, 0, 300),
    },
    hub: { mode: hubMode },
    storage: {
      ...(connectionString === undefined ? {} : { connectionString }),
      ...(accountUrl === undefined ? {} : { accountUrl }),
      originalsContainer,
      ...(publicBlobEndpoint === undefined ? {} : { publicBlobEndpoint }),
    },
  };

  if (read.issues.length > 0) {
    throw new ConfigError(read.issues);
  }
  return config;
}

/** Configuration summary that is safe to log: no connection strings or credentials. */
export function describeConfig(config: StationConfig): Record<string, unknown> {
  return {
    env: config.env,
    version: config.version,
    host: config.server.host,
    port: config.server.port,
    logLevel: config.server.logLevel,
    migrateOnStart: config.database.migrateOnStart,
    tenantId: config.auth.tenantId,
    audiences: config.auth.audiences,
    issuer: config.auth.issuer,
    jwksUrl: config.auth.jwksUrl,
    hubMode: config.hub.mode,
    originalsContainer: config.storage.originalsContainer,
    storage: config.storage.accountUrl
      ? "account-url"
      : config.storage.connectionString
        ? "connection-string"
        : "unset",
  };
}

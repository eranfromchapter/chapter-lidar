// Station API configuration, read from environment variables and validated at startup.
//
// In Azure Container Apps every secret (HUB_SERVICE_CREDENTIAL, storage credentials) is a Key
// Vault reference exposed as a plain environment variable (secretRef), so the service only ever
// reads the environment. Postgres in Azure is Entra-only: the service signs in with a token for
// its managed identity (DB_AUTH=entra) and never holds a database password.
//
// Validation collects every problem and reports variable names only, never values, so a
// misconfigured secret never reaches a log. Secret values are non-enumerable properties of the
// config object, so JSON.stringify or a logger never prints them (and object spread drops
// them: read them from the config object itself).

import { readFileSync } from "node:fs";

export type StationEnv = "development" | "test" | "production";
export type LogLevel = "fatal" | "error" | "warn" | "info" | "debug" | "trace" | "silent";
export type HubMode = "fake" | "live";
export type DatabaseSslMode = "require" | "verify-full";

/** How the station signs in to Postgres. */
export type DatabaseConnection =
  | {
      /** Connection string (local stack, tests). */
      readonly auth: "url";
      /** Secret (may hold a password): non-enumerable, never log it. */
      readonly url: string;
    }
  | {
      /** Microsoft Entra access token of the managed identity as the password (Azure). */
      readonly auth: "entra";
      readonly host: string;
      readonly port: number;
      readonly database: string;
      /** Postgres role name of the managed identity. */
      readonly user: string;
      /** TLS is always on and the server certificate is always verified (a token is sent). */
      readonly sslMode: DatabaseSslMode;
      /** Client id of a user-assigned managed identity; omitted for system-assigned. */
      readonly managedIdentityClientId?: string;
    };

export interface DatabaseConfig {
  readonly connection: DatabaseConnection;
  readonly poolMax: number;
  /** Apply pending migrations before the server starts listening. */
  readonly migrateOnStart: boolean;
}

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
  readonly database: DatabaseConfig;
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
    /** HUB REST API base URL (required when mode is live; https in production). */
    readonly baseUrl?: string;
    /** HUB service credential (required when mode is live). Secret: non-enumerable. */
    readonly serviceCredential?: string;
  };
  readonly storage: {
    /** Storage connection string (Azurite locally). Secret: non-enumerable. */
    readonly connectionString?: string;
    /** Blob service URL for managed-identity access in Azure. */
    readonly accountUrl?: string;
    /** Container that holds the immutable originals. */
    readonly originalsContainer: string;
    /** Container of the station's spatial reports (written by the worker). */
    readonly reportsContainer: string;
    /** Blob endpoint as seen by clients, when it differs from the one the service uses. */
    readonly publicBlobEndpoint?: string;
  };
  /** Web pages the API links to (PackageLinks). Optional: links are omitted when unset. */
  readonly links: {
    /** Web review screen base URL (same value as the worker's REVIEW_BASE_URL). */
    readonly reviewBaseUrl?: string;
    /** HUB page of a deal, with the placeholder {dealId}. */
    readonly hubDealUrlTemplate?: string;
  };
}

/** Placeholder of HUB_WEB_DEAL_URL_TEMPLATE. */
export const DEAL_ID_PLACEHOLDER = "{dealId}";

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
const HOSTNAME =
  /^(?=.{1,253}$)[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$/;

/** Makes a secret property non-enumerable so serializers and loggers skip it. */
function hideSecret<T extends object>(target: T, key: keyof T & string): T {
  const value = (target as Record<string, unknown>)[key];
  if (value !== undefined) {
    Object.defineProperty(target, key, { value, enumerable: false, writable: false });
  }
  return target;
}

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
  httpUrl(name: string, requireHttps = false): string | undefined {
    const value = this.raw(name);
    if (value === undefined) {
      return undefined;
    }
    try {
      const parsed = new URL(value);
      if (parsed.protocol === "https:" || (parsed.protocol === "http:" && !requireHttps)) {
        return value;
      }
    } catch {
      // reported below
    }
    this.issues.push(
      requireHttps
        ? `${name} must be an absolute https URL`
        : `${name} must be an absolute http(s) URL`,
    );
    return undefined;
  }
}

function readDatabase(read: Reader, stationEnv: StationEnv): DatabaseConfig {
  const auth = read.oneOf<"url" | "entra">("DB_AUTH", ["url", "entra"], "url");
  if (stationEnv === "production" && auth !== "entra") {
    read.issues.push("DB_AUTH must be entra when NODE_ENV is production");
  }

  let connection: DatabaseConnection;
  if (auth === "entra") {
    // A password must never be configured: the managed identity's token is the password.
    for (const name of ["DATABASE_URL", "PGPASSWORD"]) {
      if (read.raw(name) !== undefined) {
        read.issues.push(`${name} must not be set when DB_AUTH is entra`);
      }
    }
    const host = read.required("PGHOST");
    if (host !== "" && !HOSTNAME.test(host)) {
      read.issues.push("PGHOST must be a host name");
    }
    const database = read.required("PGDATABASE");
    if (database.length > 63) {
      read.issues.push("PGDATABASE must be at most 63 characters");
    }
    const user = read.required("PGUSER");
    if (user.length > 63) {
      read.issues.push("PGUSER must be at most 63 characters");
    }
    const sslMode = read.oneOf<DatabaseSslMode>("PGSSLMODE", ["require", "verify-full"], "require");
    const clientId = read.raw("AZURE_CLIENT_ID")?.toLowerCase();
    if (clientId !== undefined && !GUID.test(clientId)) {
      read.issues.push("AZURE_CLIENT_ID must be a GUID");
    }
    connection = {
      auth,
      host,
      port: read.integer("PGPORT", 5432, 1, 65535),
      database,
      user,
      sslMode,
      ...(clientId === undefined ? {} : { managedIdentityClientId: clientId }),
    };
  } else {
    const url = read.required("DATABASE_URL");
    if (url !== "" && !/^postgres(?:ql)?:\/\//.test(url)) {
      read.issues.push("DATABASE_URL must be a postgres:// or postgresql:// connection string");
    }
    connection = hideSecret({ auth, url }, "url");
  }

  return {
    connection,
    poolMax: read.integer("DB_POOL_MAX", 10, 1, 100),
    migrateOnStart: read.boolean("MIGRATE_ON_START", false),
  };
}

function readStationEnv(read: Reader): StationEnv {
  return read.oneOf<StationEnv>("NODE_ENV", ["development", "test", "production"], "development");
}

function readStorage(read: Reader): StationConfig["storage"] {
  const originalsContainer = read.raw("STORAGE_ORIGINALS_CONTAINER") ?? "originals";
  if (!CONTAINER_NAME.test(originalsContainer)) {
    read.issues.push("STORAGE_ORIGINALS_CONTAINER must be a valid Azure Blob container name");
  }
  const reportsContainer = read.raw("STORAGE_REPORTS_CONTAINER") ?? "reports";
  if (!CONTAINER_NAME.test(reportsContainer)) {
    read.issues.push("STORAGE_REPORTS_CONTAINER must be a valid Azure Blob container name");
  }
  const connectionString = read.raw("AZURE_STORAGE_CONNECTION_STRING");
  const accountUrl = read.url("AZURE_STORAGE_ACCOUNT_URL", read.raw("AZURE_STORAGE_ACCOUNT_URL"));
  const publicBlobEndpoint = read.httpUrl("STORAGE_PUBLIC_BLOB_ENDPOINT");
  return hideSecret(
    {
      ...(connectionString === undefined ? {} : { connectionString }),
      ...(accountUrl === undefined ? {} : { accountUrl }),
      originalsContainer,
      reportsContainer,
      ...(publicBlobEndpoint === undefined ? {} : { publicBlobEndpoint }),
    },
    "connectionString",
  );
}

/**
 * Reads only NODE_ENV and the database variables (for the migration entrypoint, which needs
 * no Entra API or HUB settings). Throws ConfigError listing every problem.
 */
export function loadDatabaseConfig(env: Env = process.env): {
  env: StationEnv;
  database: DatabaseConfig;
} {
  const read = new Reader(env);
  const stationEnv = readStationEnv(read);
  const database = readDatabase(read, stationEnv);
  if (read.issues.length > 0) {
    throw new ConfigError(read.issues);
  }
  return { env: stationEnv, database };
}

/**
 * Reads only NODE_ENV, the database and the storage variables (for one-off maintenance
 * scripts such as the review read model backfill). Throws ConfigError listing every problem.
 */
export function loadMaintenanceConfig(env: Env = process.env): {
  env: StationEnv;
  database: DatabaseConfig;
  storage: StationConfig["storage"];
} {
  const read = new Reader(env);
  const stationEnv = readStationEnv(read);
  const database = readDatabase(read, stationEnv);
  const storage = readStorage(read);
  if (storage.accountUrl === undefined && storage.connectionString === undefined) {
    read.issues.push("AZURE_STORAGE_ACCOUNT_URL or AZURE_STORAGE_CONNECTION_STRING is required");
  }
  if (read.issues.length > 0) {
    throw new ConfigError(read.issues);
  }
  return { env: stationEnv, database, storage };
}

/**
 * Reads and validates the configuration. Throws ConfigError listing every problem.
 *
 * Variables (defaults in brackets):
 * - NODE_ENV development|test|production [development]
 * - STATION_VERSION [package.json version]
 * - HOST [0.0.0.0], PORT [8080], LOG_LEVEL [info], BODY_LIMIT_BYTES [4194304]
 * - DB_AUTH url|entra [url]; production requires entra
 *   - url: DATABASE_URL (required, secret)
 *   - entra: PGHOST, PGDATABASE, PGUSER (the managed identity's Postgres role) required,
 *     PGPORT [5432], PGSSLMODE require|verify-full [require], AZURE_CLIENT_ID (user-assigned
 *     identity); DATABASE_URL and PGPASSWORD must not be set
 * - DB_POOL_MAX [10], MIGRATE_ON_START [false]
 * - ENTRA_TENANT_ID (required), ENTRA_AUDIENCE (required, comma-separated),
 *   ENTRA_ISSUER [https://login.microsoftonline.com/<tenant>/v2.0],
 *   ENTRA_JWKS_URL [https://login.microsoftonline.com/<tenant>/discovery/v2.0/keys],
 *   ENTRA_CLOCK_TOLERANCE_SECONDS [60]
 * - HUB_MODE fake|live [fake]; fake is refused when NODE_ENV is production
 * - HUB_BASE_URL (https in production), HUB_SERVICE_CREDENTIAL (secret); both required when
 *   HUB_MODE is live
 * - AZURE_STORAGE_CONNECTION_STRING (secret), AZURE_STORAGE_ACCOUNT_URL,
 *   STORAGE_ORIGINALS_CONTAINER [originals], STORAGE_REPORTS_CONTAINER [reports],
 *   STORAGE_PUBLIC_BLOB_ENDPOINT
 * - REVIEW_BASE_URL (https unless loopback): the web review screen, for links.review; links are
 *   omitted while unset. HUB_WEB_DEAL_URL_TEMPLATE (https unless loopback, contains {dealId}):
 *   the HUB page of a deal, for links.hub; omitted while unset.
 */
export function loadConfig(env: Env = process.env): StationConfig {
  const read = new Reader(env);

  const stationEnv = readStationEnv(read);

  const version = read.raw("STATION_VERSION") ?? packageVersion();
  if (version.length > 50) {
    read.issues.push("STATION_VERSION must be at most 50 characters");
  }

  const database = readDatabase(read, stationEnv);

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
  const hubBaseUrl = read.httpUrl("HUB_BASE_URL", stationEnv === "production");
  const hubCredential = read.raw("HUB_SERVICE_CREDENTIAL");
  if (hubMode === "live") {
    if (read.raw("HUB_BASE_URL") === undefined) {
      read.issues.push("HUB_BASE_URL is required when HUB_MODE is live");
    }
    if (hubCredential === undefined) {
      read.issues.push("HUB_SERVICE_CREDENTIAL is required when HUB_MODE is live");
    }
  }

  const storage = readStorage(read);

  const reviewBaseUrl = read.url("REVIEW_BASE_URL", read.raw("REVIEW_BASE_URL"));
  const hubDealTemplate = read.raw("HUB_WEB_DEAL_URL_TEMPLATE");
  let hubDealUrlTemplate: string | undefined;
  if (hubDealTemplate !== undefined) {
    if (!hubDealTemplate.includes(DEAL_ID_PLACEHOLDER)) {
      read.issues.push(`HUB_WEB_DEAL_URL_TEMPLATE must contain ${DEAL_ID_PLACEHOLDER}`);
    } else {
      // Checked with a sample deal id in place of the placeholder.
      const sample = hubDealTemplate.split(DEAL_ID_PLACEHOLDER).join("1001");
      hubDealUrlTemplate =
        read.url("HUB_WEB_DEAL_URL_TEMPLATE", sample) === undefined ? undefined : hubDealTemplate;
    }
  }

  const config: StationConfig = {
    env: stationEnv,
    version,
    server: {
      host: read.raw("HOST") ?? "0.0.0.0",
      port: read.integer("PORT", 8080, 1, 65535),
      logLevel: read.oneOf<LogLevel>("LOG_LEVEL", LOG_LEVELS, "info"),
      bodyLimitBytes: read.integer("BODY_LIMIT_BYTES", 4 * 1024 * 1024, 1024, 64 * 1024 * 1024),
    },
    database,
    auth: {
      tenantId,
      audiences,
      issuer,
      jwksUrl,
      clockToleranceSeconds: read.integer("ENTRA_CLOCK_TOLERANCE_SECONDS", 60, 0, 300),
    },
    hub: hideSecret(
      {
        mode: hubMode,
        ...(hubBaseUrl === undefined ? {} : { baseUrl: hubBaseUrl }),
        ...(hubCredential === undefined ? {} : { serviceCredential: hubCredential }),
      },
      "serviceCredential",
    ),
    storage,
    links: {
      ...(reviewBaseUrl === undefined ? {} : { reviewBaseUrl }),
      ...(hubDealUrlTemplate === undefined ? {} : { hubDealUrlTemplate }),
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
    database:
      config.database.connection.auth === "entra"
        ? {
            auth: "entra",
            host: config.database.connection.host,
            port: config.database.connection.port,
            database: config.database.connection.database,
            user: config.database.connection.user,
            sslMode: config.database.connection.sslMode,
            managedIdentity:
              config.database.connection.managedIdentityClientId ?? "system-assigned",
          }
        : { auth: "url" },
    tenantId: config.auth.tenantId,
    audiences: config.auth.audiences,
    issuer: config.auth.issuer,
    jwksUrl: config.auth.jwksUrl,
    hubMode: config.hub.mode,
    hubBaseUrl: config.hub.baseUrl,
    hubCredential: config.hub.serviceCredential === undefined ? "unset" : "set",
    originalsContainer: config.storage.originalsContainer,
    reportsContainer: config.storage.reportsContainer,
    reviewBaseUrl: config.links.reviewBaseUrl ?? "unset",
    hubDealUrlTemplate: config.links.hubDealUrlTemplate ?? "unset",
    storage: config.storage.accountUrl
      ? "account-url"
      : config.storage.connectionString
        ? "connection-string"
        : "unset",
  };
}

// Worker configuration, read from environment variables and validated at start.
//
// Mirrors station/api/src/core/config.ts (same variable names and rules for the shared
// settings) without importing it. Validation collects every problem and reports variable names
// only, never values. Secret values (DATABASE_URL, AZURE_STORAGE_CONNECTION_STRING,
// HUB_SERVICE_CREDENTIAL) are non-enumerable properties, so JSON.stringify or a logger never
// prints them (and object spread drops them: read them from the config object itself).
//
// Variables (defaults in brackets):
// - NODE_ENV development|test|production [development]; LOG_LEVEL [info]
// - DB_AUTH url|entra [url]; production requires entra
//   - url: DATABASE_URL (required, secret)
//   - entra: PGHOST, PGDATABASE, PGUSER required, PGPORT [5432], PGSSLMODE require|verify-full
//     [require], AZURE_CLIENT_ID (user-assigned identity); DATABASE_URL and PGPASSWORD must not
//     be set
// - DB_POOL_MAX [4]
// - AZURE_STORAGE_ACCOUNT_URL (managed identity, Azure) or AZURE_STORAGE_CONNECTION_STRING
//   (secret, Azurite locally): one is required; the account URL wins.
//   STORAGE_ORIGINALS_CONTAINER [originals], STORAGE_REPORTS_CONTAINER [reports] (the
//   spatial report PDFs the worker writes for the web review)
// - REPORT_TIME_ZONE [America/New_York]: IANA zone of the dates and times printed in the
//   spatial report (the plan sheet prints in the same zone)
// - HUB_MODE fake|live [fake]; fake (the in-process fake HUB) is refused in production
// - HUB_BASE_URL (https in production), HUB_SERVICE_CREDENTIAL (secret): required when live
// - REVIEW_BASE_URL (required, no default): web review screen base URL for the station links in
//   the verdict report (https unless loopback)
// - WORKER_ID [hostname-pid], WORKER_POLL_INTERVAL_MS [2000], WORKER_LOCK_TIMEOUT_SECONDS [900],
//   WORKER_RETRY_BASE_SECONDS [30], WORKER_RETRY_MAX_SECONDS [900],
//   HUB_PUBLISH_RETRY_BASE_MS [2000], HUB_PUBLISH_RETRY_MAX_MS [30000]

import { hostname } from "node:os";
import { DEFAULT_REPORT_TIME_ZONE } from "@chapter/station-hub";

export type WorkerEnv = "development" | "test" | "production";
export type LogLevel = "fatal" | "error" | "warn" | "info" | "debug" | "trace" | "silent";
export type HubMode = "fake" | "live";
export type DatabaseSslMode = "require" | "verify-full";

export type DatabaseConnection =
  | {
      readonly auth: "url";
      /** Secret (may hold a password): non-enumerable, never log it. */
      readonly url: string;
    }
  | {
      readonly auth: "entra";
      readonly host: string;
      readonly port: number;
      readonly database: string;
      readonly user: string;
      readonly sslMode: DatabaseSslMode;
      readonly managedIdentityClientId?: string;
    };

export interface WorkerConfig {
  readonly env: WorkerEnv;
  readonly logLevel: LogLevel;
  readonly database: { readonly connection: DatabaseConnection; readonly poolMax: number };
  readonly storage: {
    /** Secret: non-enumerable. */
    readonly connectionString?: string;
    readonly accountUrl?: string;
    readonly originalsContainer: string;
    readonly reportsContainer: string;
  };
  /** IANA zone of the spatial report's printed dates. */
  readonly reportTimeZone: string;
  readonly hub: {
    readonly mode: HubMode;
    readonly baseUrl?: string;
    /** Secret: non-enumerable. */
    readonly serviceCredential?: string;
  };
  readonly reviewBaseUrl: string;
  readonly worker: {
    readonly id: string;
    readonly pollIntervalMs: number;
    readonly lockTimeoutSeconds: number;
    readonly retryBaseSeconds: number;
    readonly retryMaxSeconds: number;
    readonly publishRetryBaseMs: number;
    readonly publishRetryMaxMs: number;
  };
}

export class ConfigError extends Error {
  readonly issues: readonly string[];

  constructor(issues: readonly string[]) {
    super(`Invalid worker configuration:\n${issues.map((issue) => `- ${issue}`).join("\n")}`);
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
const WORKER_ID = /^[A-Za-z0-9._:-]{1,120}$/;

function hideSecret<T extends object>(target: T, key: keyof T & string): T {
  const value = (target as Record<string, unknown>)[key];
  if (value !== undefined) {
    Object.defineProperty(target, key, { value, enumerable: false, writable: false });
  }
  return target;
}

class Reader {
  readonly issues: string[] = [];

  constructor(private readonly env: Env) {}

  raw(name: string): string | undefined {
    const value = this.env[name]?.trim();
    return value === undefined || value === "" ? undefined : value;
  }

  required(name: string, why = ""): string {
    const value = this.raw(name);
    if (value === undefined) {
      this.issues.push(`${name} is required${why}`);
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

  /** Absolute http(s) URL without credentials, query or fragment; https unless loopback (or allowHttp). */
  url(name: string, value: string | undefined, allowHttp: boolean): string | undefined {
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
    if (parsed.protocol !== "https:" && !(parsed.protocol === "http:" && (loopback || allowHttp))) {
      this.issues.push(`${name} must use https (http is allowed only for localhost)`);
      return undefined;
    }
    if (
      parsed.username !== "" ||
      parsed.password !== "" ||
      parsed.search !== "" ||
      parsed.hash !== ""
    ) {
      this.issues.push(`${name} must not carry credentials, a query or a fragment`);
      return undefined;
    }
    return value;
  }
}

function readDatabase(read: Reader, env: WorkerEnv): WorkerConfig["database"] {
  const auth = read.oneOf<"url" | "entra">("DB_AUTH", ["url", "entra"], "url");
  if (env === "production" && auth !== "entra") {
    read.issues.push("DB_AUTH must be entra when NODE_ENV is production");
  }
  let connection: DatabaseConnection;
  if (auth === "entra") {
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
      sslMode: read.oneOf<DatabaseSslMode>("PGSSLMODE", ["require", "verify-full"], "require"),
      ...(clientId === undefined ? {} : { managedIdentityClientId: clientId }),
    };
  } else {
    const url = read.required("DATABASE_URL");
    if (url !== "" && !/^postgres(?:ql)?:\/\//.test(url)) {
      read.issues.push("DATABASE_URL must be a postgres:// or postgresql:// connection string");
    }
    connection = hideSecret({ auth, url }, "url");
  }
  return { connection, poolMax: read.integer("DB_POOL_MAX", 4, 1, 50) };
}

/** Reads and validates the configuration. Throws ConfigError listing every problem. */
export function loadConfig(env: Env = process.env): WorkerConfig {
  const read = new Reader(env);
  const workerEnv = read.oneOf<WorkerEnv>(
    "NODE_ENV",
    ["development", "test", "production"],
    "development",
  );
  const production = workerEnv === "production";
  const database = readDatabase(read, workerEnv);

  const originalsContainer = read.raw("STORAGE_ORIGINALS_CONTAINER") ?? "originals";
  if (!CONTAINER_NAME.test(originalsContainer)) {
    read.issues.push("STORAGE_ORIGINALS_CONTAINER must be a valid Azure Blob container name");
  }
  const reportsContainer = read.raw("STORAGE_REPORTS_CONTAINER") ?? "reports";
  if (!CONTAINER_NAME.test(reportsContainer)) {
    read.issues.push("STORAGE_REPORTS_CONTAINER must be a valid Azure Blob container name");
  } else if (reportsContainer === originalsContainer) {
    read.issues.push("STORAGE_REPORTS_CONTAINER must not be the originals container");
  }
  const reportTimeZone = read.raw("REPORT_TIME_ZONE") ?? DEFAULT_REPORT_TIME_ZONE;
  if (!Intl.supportedValuesOf("timeZone").includes(reportTimeZone) && reportTimeZone !== "UTC") {
    read.issues.push("REPORT_TIME_ZONE must be an IANA time zone, for example America/New_York");
  }
  const connectionString = read.raw("AZURE_STORAGE_CONNECTION_STRING");
  const accountUrl = read.url(
    "AZURE_STORAGE_ACCOUNT_URL",
    read.raw("AZURE_STORAGE_ACCOUNT_URL"),
    false,
  );
  if (read.raw("AZURE_STORAGE_ACCOUNT_URL") === undefined && connectionString === undefined) {
    read.issues.push(
      "AZURE_STORAGE_ACCOUNT_URL or AZURE_STORAGE_CONNECTION_STRING is required (the worker reads the originals)",
    );
  }

  const hubMode = read.oneOf<HubMode>("HUB_MODE", ["fake", "live"], "fake");
  if (production && hubMode === "fake") {
    read.issues.push("HUB_MODE must be live when NODE_ENV is production");
  }
  const hubBaseUrl = read.url("HUB_BASE_URL", read.raw("HUB_BASE_URL"), !production);
  const hubCredential = read.raw("HUB_SERVICE_CREDENTIAL");
  if (hubMode === "live") {
    if (read.raw("HUB_BASE_URL") === undefined) {
      read.issues.push("HUB_BASE_URL is required when HUB_MODE is live");
    }
    if (hubCredential === undefined) {
      read.issues.push("HUB_SERVICE_CREDENTIAL is required when HUB_MODE is live");
    } else if (!/^[\x21-\x7e]+$/.test(hubCredential)) {
      read.issues.push("HUB_SERVICE_CREDENTIAL must be visible ASCII without spaces");
    }
  }

  // No default: a wrong review link in a report sent to the HUB is worse than not starting.
  const reviewRaw = read.required(
    "REVIEW_BASE_URL",
    " (web review screen base URL for the station links in the verdict report)",
  );
  const reviewBaseUrl =
    reviewRaw === "" ? "" : (read.url("REVIEW_BASE_URL", reviewRaw, false) ?? "");

  const workerId = read.raw("WORKER_ID") ?? `${hostname()}-${process.pid}`.slice(0, 120);
  if (!WORKER_ID.test(workerId)) {
    read.issues.push("WORKER_ID must be 1 to 120 characters of letters, digits and . _ : -");
  }
  const retryBaseSeconds = read.integer("WORKER_RETRY_BASE_SECONDS", 30, 1, 3600);
  const retryMaxSeconds = read.integer("WORKER_RETRY_MAX_SECONDS", 900, 1, 86_400);
  const publishRetryBaseMs = read.integer("HUB_PUBLISH_RETRY_BASE_MS", 2000, 1, 60_000);
  const publishRetryMaxMs = read.integer("HUB_PUBLISH_RETRY_MAX_MS", 30_000, 1, 600_000);
  const lockTimeoutSeconds = read.integer("WORKER_LOCK_TIMEOUT_SECONDS", 900, 30, 86_400);
  // Five publish attempts with backoff must fit well inside the lock (it is also refreshed).
  if (publishRetryMaxMs * 4 >= lockTimeoutSeconds * 1000) {
    read.issues.push("WORKER_LOCK_TIMEOUT_SECONDS must exceed 4 x HUB_PUBLISH_RETRY_MAX_MS");
  }

  const config: WorkerConfig = {
    env: workerEnv,
    logLevel: read.oneOf<LogLevel>("LOG_LEVEL", LOG_LEVELS, "info"),
    database,
    storage: hideSecret(
      {
        ...(connectionString === undefined ? {} : { connectionString }),
        ...(accountUrl === undefined ? {} : { accountUrl }),
        originalsContainer,
        reportsContainer,
      },
      "connectionString",
    ),
    reportTimeZone,
    hub: hideSecret(
      {
        mode: hubMode,
        ...(hubBaseUrl === undefined ? {} : { baseUrl: hubBaseUrl }),
        ...(hubCredential === undefined ? {} : { serviceCredential: hubCredential }),
      },
      "serviceCredential",
    ),
    reviewBaseUrl,
    worker: {
      id: workerId,
      pollIntervalMs: read.integer("WORKER_POLL_INTERVAL_MS", 2000, 50, 60_000),
      lockTimeoutSeconds,
      retryBaseSeconds,
      retryMaxSeconds,
      publishRetryBaseMs,
      publishRetryMaxMs,
    },
  };
  if (read.issues.length > 0) {
    throw new ConfigError(read.issues);
  }
  return config;
}

/** Configuration summary that is safe to log: no connection strings or credentials. */
export function describeConfig(config: WorkerConfig): Record<string, unknown> {
  const connection = config.database.connection;
  return {
    env: config.env,
    logLevel: config.logLevel,
    database:
      connection.auth === "entra"
        ? {
            auth: "entra",
            host: connection.host,
            port: connection.port,
            database: connection.database,
            user: connection.user,
            sslMode: connection.sslMode,
            managedIdentity: connection.managedIdentityClientId ?? "system-assigned",
          }
        : { auth: "url" },
    storage: config.storage.accountUrl ? "account-url" : "connection-string",
    originalsContainer: config.storage.originalsContainer,
    reportsContainer: config.storage.reportsContainer,
    reportTimeZone: config.reportTimeZone,
    hubMode: config.hub.mode,
    hubBaseUrl: config.hub.baseUrl,
    hubCredential: config.hub.serviceCredential === undefined ? "unset" : "set",
    reviewBaseUrl: config.reviewBaseUrl,
    worker: config.worker,
  };
}

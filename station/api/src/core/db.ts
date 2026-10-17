// Postgres access: a pooled Database with a transaction helper, and the sign-in used by both
// the server and the migration entrypoint.
//
// DB_AUTH=entra (Azure): Postgres Flexible Server accepts only Microsoft Entra sign-in. Each new
// connection uses an access token of the station's managed identity (scope
// https://ossrdbms-aad.database.windows.net/.default) as its password. Tokens are cached and
// refreshed 5 minutes before they expire; a failure to get one fails the connection (no
// fallback). TLS is always on with server certificate verification, because the password is a
// bearer token. Tokens are never logged.
//
// DB_AUTH=url (local stack, tests): the DATABASE_URL connection string.
//
// int8 (bigint) columns such as package_files.bytes and count(*) are parsed to JS numbers;
// a value outside the safe integer range raises instead of losing precision.

import { ManagedIdentityCredential, type TokenCredential } from "@azure/identity";
import pg, { type ClientConfig, type QueryResult, type QueryResultRow } from "pg";
import type { DatabaseConnection } from "./config.js";

/** Entra scope of Azure Database for PostgreSQL. */
export const POSTGRES_ENTRA_SCOPE = "https://ossrdbms-aad.database.windows.net/.default";
const TOKEN_REFRESH_MARGIN_MS = 5 * 60_000;

/** Returns a current Postgres access token. */
export type TokenProvider = () => Promise<string>;

export interface EntraTokenProviderOptions {
  readonly scope?: string;
  /** Refresh this long before expiry. Defaults to 5 minutes. */
  readonly refreshMarginMs?: number;
  /** Clock, for tests. */
  readonly now?: () => number;
}

/** Caching token provider over an Azure credential; concurrent callers share one request. */
export function createEntraTokenProvider(
  credential: TokenCredential,
  options: EntraTokenProviderOptions = {},
): TokenProvider {
  const scope = options.scope ?? POSTGRES_ENTRA_SCOPE;
  const margin = options.refreshMarginMs ?? TOKEN_REFRESH_MARGIN_MS;
  const now = options.now ?? Date.now;
  let cached: { token: string; expiresOnTimestamp: number } | undefined;
  let pending: Promise<string> | undefined;

  const fetchToken = async (): Promise<string> => {
    let accessToken;
    try {
      accessToken = await credential.getToken(scope);
    } catch (error) {
      const reason = error instanceof Error ? error.message : String(error);
      throw new Error(`Could not get a Postgres Entra token for the managed identity: ${reason}`, {
        cause: error,
      });
    }
    if (!accessToken?.token) {
      throw new Error("The managed identity credential returned no token for Postgres");
    }
    cached = { token: accessToken.token, expiresOnTimestamp: accessToken.expiresOnTimestamp };
    return accessToken.token;
  };

  return async () => {
    if (cached && now() < cached.expiresOnTimestamp - margin) {
      return cached.token;
    }
    pending ??= fetchToken().finally(() => {
      pending = undefined;
    });
    return pending;
  };
}

/** The managed identity credential for Entra sign-in (user-assigned when a client id is set). */
export function createDatabaseCredential(
  connection: Extract<DatabaseConnection, { auth: "entra" }>,
): TokenCredential {
  return connection.managedIdentityClientId === undefined
    ? new ManagedIdentityCredential()
    : new ManagedIdentityCredential({ clientId: connection.managedIdentityClientId });
}

/** Token provider for a connection: the managed identity in entra mode, none in url mode. */
export function tokenProviderFor(connection: DatabaseConnection): TokenProvider | undefined {
  return connection.auth === "entra"
    ? createEntraTokenProvider(createDatabaseCredential(connection))
    : undefined;
}

/** node-postgres connection settings for the server pool and the migration runner. */
export function pgConnectionConfig(
  connection: DatabaseConnection,
  tokenProvider?: TokenProvider,
): ClientConfig {
  if (connection.auth === "url") {
    return { connectionString: connection.url };
  }
  if (tokenProvider === undefined) {
    throw new Error("Entra database sign-in needs a token provider");
  }
  return {
    host: connection.host,
    port: connection.port,
    database: connection.database,
    user: connection.user,
    // Called by node-postgres for every new connection.
    password: () => tokenProvider(),
    // sslmode require and verify-full both verify the server certificate: the password is a
    // bearer token and must not reach an unverified server.
    ssl: { rejectUnauthorized: true },
  };
}

/** Anything that can run a query: the pool or a transaction client. */
export interface Queryable {
  query<R extends QueryResultRow = QueryResultRow>(
    text: string,
    values?: readonly unknown[],
  ): Promise<QueryResult<R>>;
}

export interface Database extends Queryable {
  /** Runs fn in one transaction: COMMIT when it resolves, ROLLBACK when it throws. */
  transaction<T>(fn: (tx: Queryable) => Promise<T>): Promise<T>;
  /** Resolves when the database answers within timeoutMs. */
  ping(timeoutMs?: number): Promise<void>;
  close(): Promise<void>;
}

export interface DatabaseOptions {
  readonly connection: DatabaseConnection;
  /** Required for entra connections; see tokenProviderFor. */
  readonly tokenProvider?: TokenProvider;
  readonly poolMax?: number;
  readonly applicationName?: string;
  /** Called for errors on idle pooled connections (otherwise they would crash the process). */
  readonly onPoolError?: (error: Error) => void;
}

const INT8_OID = 20;

function parseInt8(value: string): number {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed)) {
    throw new RangeError("bigint value outside the safe integer range");
  }
  return parsed;
}

const types = {
  getTypeParser: ((oid: number, format?: "text" | "binary") =>
    oid === INT8_OID && format !== "binary"
      ? parseInt8
      : pg.types.getTypeParser(oid, format ?? "text")) as typeof pg.types.getTypeParser,
};

/** A url connection, for scripts and tests. */
export function urlConnection(url: string): DatabaseConnection {
  return { auth: "url", url };
}

export function createDatabase(options: DatabaseOptions): Database {
  const pool = new pg.Pool({
    ...pgConnectionConfig(options.connection, options.tokenProvider),
    max: options.poolMax ?? 10,
    connectionTimeoutMillis: 5_000,
    idleTimeoutMillis: 30_000,
    application_name: options.applicationName ?? "chapter-station-api",
    types,
  });
  pool.on("error", (error) => options.onPoolError?.(error));

  const query = <R extends QueryResultRow>(text: string, values?: readonly unknown[]) =>
    pool.query<R>(text, values as unknown[] | undefined);

  return {
    query,

    async transaction<T>(fn: (tx: Queryable) => Promise<T>): Promise<T> {
      const client = await pool.connect();
      let broken = false;
      try {
        await client.query("BEGIN");
        const tx: Queryable = {
          query: <R extends QueryResultRow>(text: string, values?: readonly unknown[]) =>
            client.query<R>(text, values as unknown[] | undefined),
        };
        const result = await fn(tx);
        await client.query("COMMIT");
        return result;
      } catch (error) {
        try {
          await client.query("ROLLBACK");
        } catch {
          broken = true;
        }
        throw error;
      } finally {
        client.release(broken);
      }
    },

    async ping(timeoutMs = 2_000): Promise<void> {
      let timer: NodeJS.Timeout | undefined;
      const timeout = new Promise<never>((_, reject) => {
        timer = setTimeout(() => reject(new Error("database ping timed out")), timeoutMs);
      });
      try {
        await Promise.race([pool.query("SELECT 1"), timeout]);
      } finally {
        clearTimeout(timer);
      }
    },

    async close(): Promise<void> {
      await pool.end();
    },
  };
}

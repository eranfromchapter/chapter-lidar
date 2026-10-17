// Postgres access for the worker: a pool with a transaction helper and the Entra sign-in.
//
// Same rules as station/api/src/core/db.ts (implemented here, not imported):
// - DB_AUTH=entra: each new connection uses an access token of the worker's managed identity
//   (scope https://ossrdbms-aad.database.windows.net/.default) as its password. Tokens are cached
//   and refreshed 5 minutes before expiry; failing to get one fails the connection (no
//   fallback). TLS is always on with certificate verification. Tokens are never logged.
// - DB_AUTH=url: the DATABASE_URL connection string (local stack, tests).
// - int8 columns are parsed to numbers; a value outside the safe range raises.

import { ManagedIdentityCredential, type TokenCredential } from "@azure/identity";
import pg, { type ClientConfig, type QueryResult, type QueryResultRow } from "pg";
import type { DatabaseConnection } from "./config.js";

export const POSTGRES_ENTRA_SCOPE = "https://ossrdbms-aad.database.windows.net/.default";
const TOKEN_REFRESH_MARGIN_MS = 5 * 60_000;

export type TokenProvider = () => Promise<string>;

/** Caching token provider over an Azure credential; concurrent callers share one request. */
export function createEntraTokenProvider(
  credential: TokenCredential,
  now: () => number = Date.now,
): TokenProvider {
  let cached: { token: string; expiresOnTimestamp: number } | undefined;
  let pending: Promise<string> | undefined;
  const fetchToken = async (): Promise<string> => {
    let accessToken;
    try {
      accessToken = await credential.getToken(POSTGRES_ENTRA_SCOPE);
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
    if (cached && now() < cached.expiresOnTimestamp - TOKEN_REFRESH_MARGIN_MS) {
      return cached.token;
    }
    pending ??= fetchToken().finally(() => {
      pending = undefined;
    });
    return pending;
  };
}

/** node-postgres settings for a connection. */
export function pgConnectionConfig(
  connection: DatabaseConnection,
  tokenProvider?: TokenProvider,
): ClientConfig {
  if (connection.auth === "url") {
    return { connectionString: connection.url };
  }
  const provider =
    tokenProvider ??
    createEntraTokenProvider(
      connection.managedIdentityClientId === undefined
        ? new ManagedIdentityCredential()
        : new ManagedIdentityCredential({ clientId: connection.managedIdentityClientId }),
    );
  return {
    host: connection.host,
    port: connection.port,
    database: connection.database,
    user: connection.user,
    password: () => provider(),
    // require and verify-full both verify the certificate: the password is a bearer token.
    ssl: { rejectUnauthorized: true },
  };
}

export interface Queryable {
  query<R extends QueryResultRow = QueryResultRow>(
    text: string,
    values?: readonly unknown[],
  ): Promise<QueryResult<R>>;
}

export interface Database extends Queryable {
  transaction<T>(fn: (tx: Queryable) => Promise<T>): Promise<T>;
  close(): Promise<void>;
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

export interface DatabaseOptions {
  readonly connection: DatabaseConnection;
  readonly tokenProvider?: TokenProvider;
  readonly poolMax?: number;
  readonly onPoolError?: (error: Error) => void;
}

export function createDatabase(options: DatabaseOptions): Database {
  const pool = new pg.Pool({
    ...pgConnectionConfig(options.connection, options.tokenProvider),
    max: options.poolMax ?? 4,
    connectionTimeoutMillis: 10_000,
    idleTimeoutMillis: 30_000,
    application_name: "chapter-station-worker",
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
    async close(): Promise<void> {
      await pool.end();
    },
  };
}

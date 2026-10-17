// Postgres access: a pooled Database with a transaction helper.
//
// int8 (bigint) columns such as package_files.bytes and count(*) are parsed to JS numbers;
// a value outside the safe integer range raises instead of losing precision.

import pg, { type QueryResult, type QueryResultRow } from "pg";

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
  /** Connection string. Secret: never log it. */
  readonly url: string;
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

export function createDatabase(options: DatabaseOptions): Database {
  const pool = new pg.Pool({
    connectionString: options.url,
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

// A throwaway Postgres database for migrate:check and test:db.
//
// - DATABASE_URL set: creates a uniquely named database on that server (needs CREATEDB) and
//   drops it afterwards. The database named in DATABASE_URL itself is never modified.
// - DATABASE_URL unset: starts a disposable postgres container (Docker), bound to 127.0.0.1 on
//   a random port, and removes it afterwards.

import { spawnSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import pg from "pg";

export const POSTGRES_IMAGE = "postgres:16.15-bookworm";

export interface ThrowawayDatabase {
  /** Connection string of the empty database. */
  readonly url: string;
  readonly description: string;
}

function docker(args: string[]): string {
  const result = spawnSync("docker", args, { encoding: "utf8" });
  if (result.error) {
    throw new Error(`docker ${args[0]} failed: ${result.error.message}`);
  }
  if (result.status !== 0) {
    throw new Error(`docker ${args[0]} failed: ${result.stderr.trim()}`);
  }
  return result.stdout.trim();
}

async function waitForPostgres(url: string, timeoutMs: number): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  let lastError: unknown;
  // The image's init phase runs a temporary server on the unix socket only and then restarts,
  // so require two successful connections in a row a moment apart.
  let successes = 0;
  while (Date.now() < deadline) {
    const client = new pg.Client({ connectionString: url, connectionTimeoutMillis: 2_000 });
    try {
      await client.connect();
      await client.query("SELECT 1");
      successes += 1;
      if (successes >= 2) {
        return;
      }
    } catch (error) {
      successes = 0;
      lastError = error;
    } finally {
      await client.end().catch(() => undefined);
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw new Error(
    `Postgres did not become ready: ${lastError instanceof Error ? lastError.message : "timeout"}`,
  );
}

/** Runs fn with an empty database and always cleans up. */
export async function withThrowawayDatabase<T>(
  fn: (db: ThrowawayDatabase) => Promise<T>,
): Promise<T> {
  const suffix = randomBytes(6).toString("hex");
  const serverUrl = process.env.DATABASE_URL?.trim();

  if (serverUrl) {
    const name = `station_check_${suffix}`;
    const admin = new pg.Client({ connectionString: serverUrl });
    await admin.connect();
    try {
      await admin.query(`CREATE DATABASE ${name}`);
    } catch (error) {
      await admin.end();
      throw error;
    }
    const url = new URL(serverUrl);
    url.pathname = `/${name}`;
    try {
      return await fn({ url: url.toString(), description: `database ${name} on DATABASE_URL` });
    } finally {
      await admin.query(`DROP DATABASE IF EXISTS ${name} WITH (FORCE)`).catch(() => undefined);
      await admin.end();
    }
  }

  const container = `station-pg-check-${suffix}`;
  docker([
    "run",
    "--detach",
    "--rm",
    "--name",
    container,
    "--env",
    "POSTGRES_HOST_AUTH_METHOD=trust",
    "--env",
    "POSTGRES_USER=station",
    "--env",
    "POSTGRES_DB=station",
    "--publish",
    "127.0.0.1::5432",
    POSTGRES_IMAGE,
  ]);
  const cleanup = () => {
    spawnSync("docker", ["rm", "--force", container], { stdio: "ignore" });
  };
  const onSignal = () => {
    cleanup();
    process.exit(130);
  };
  process.once("SIGINT", onSignal);
  process.once("SIGTERM", onSignal);
  try {
    const mapping = docker(["port", container, "5432/tcp"]).split("\n")[0] ?? "";
    const port = /:(\d+)$/.exec(mapping)?.[1];
    if (port === undefined) {
      throw new Error(`cannot read the published port of ${container}: ${mapping}`);
    }
    const url = `postgres://station@127.0.0.1:${port}/station`;
    await waitForPostgres(url, 90_000);
    return await fn({ url, description: `container ${container} (${POSTGRES_IMAGE})` });
  } finally {
    process.off("SIGINT", onSignal);
    process.off("SIGTERM", onSignal);
    cleanup();
  }
}

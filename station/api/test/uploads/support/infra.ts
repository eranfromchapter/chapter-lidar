// Real infrastructure for the upload tests: a migrated Postgres database and an Azurite blob
// service. Nothing is skipped: when Docker (or the given services) is unavailable, setup throws
// and the test file fails.
//
// - STATION_TEST_DATABASE_URL set (npm run test:db): that database is used (migrations are
//   applied, a no-op when current). Otherwise a throwaway Postgres container is started
//   (scripts/lib/throwaway-postgres.ts).
// - STATION_TEST_STORAGE_CONNECTION_STRING set: that blob service is used. Otherwise an Azurite
//   container (the image pinned in docker-compose.yml) is started on a random loopback port
//   and removed afterwards.

import { spawnSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { BlobServiceClient } from "@azure/storage-blob";
import { withThrowawayDatabase } from "../../../scripts/lib/throwaway-postgres.js";
import { urlConnection } from "../../../src/core/db.js";
import { runMigrations } from "../../../src/core/migrate.js";

export const AZURITE_IMAGE = "mcr.microsoft.com/azure-storage/azurite:3.35.0";
/** Azurite's published development account key (not a secret). */
const AZURITE_ACCOUNT = "devstoreaccount1";
const AZURITE_KEY = [
  "Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq",
  "/K1SZFPTOtr/KBHBeksoGMGw==",
].join("");

export interface TestDatabase {
  readonly url: string;
  release(): Promise<void>;
}

export interface TestBlobService {
  readonly connectionString: string;
  release(): Promise<void>;
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

/** A migrated database for this test file. */
export async function startTestDatabase(): Promise<TestDatabase> {
  const given = process.env.STATION_TEST_DATABASE_URL?.trim();
  if (given) {
    await runMigrations({ connection: urlConnection(given) });
    return { url: given, release: async () => undefined };
  }

  let release!: () => void;
  const released = new Promise<void>((resolve) => {
    release = resolve;
  });
  let ready!: (url: string) => void;
  let failed!: (error: unknown) => void;
  const readyPromise = new Promise<string>((resolve, reject) => {
    ready = resolve;
    failed = reject;
  });
  const done = withThrowawayDatabase(async (db) => {
    await runMigrations({ connection: urlConnection(db.url) });
    ready(db.url);
    await released;
  }).catch((error: unknown) => {
    failed(error);
  });
  const url = await readyPromise;
  return {
    url,
    release: async () => {
      release();
      await done;
    },
  };
}

async function waitForBlobService(connectionString: string, timeoutMs: number): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  let lastError: unknown;
  while (Date.now() < deadline) {
    try {
      await BlobServiceClient.fromConnectionString(connectionString).getProperties();
      return;
    } catch (error) {
      lastError = error;
    }
    await new Promise((resolve) => setTimeout(resolve, 300));
  }
  throw new Error(
    `Azurite did not become ready: ${lastError instanceof Error ? lastError.message : "timeout"}`,
  );
}

export function azuriteConnectionString(blobEndpoint: string): string {
  return [
    "DefaultEndpointsProtocol=http",
    `AccountName=${AZURITE_ACCOUNT}`,
    `AccountKey=${AZURITE_KEY}`,
    `BlobEndpoint=${blobEndpoint}`,
    "",
  ].join(";");
}

/** A blob service (Azurite) for this test file. */
export async function startTestBlobService(): Promise<TestBlobService> {
  const given = process.env.STATION_TEST_STORAGE_CONNECTION_STRING?.trim();
  if (given) {
    await waitForBlobService(given, 10_000);
    return { connectionString: given, release: async () => undefined };
  }

  const container = `station-azurite-test-${randomBytes(6).toString("hex")}`;
  docker([
    "run",
    "--detach",
    "--rm",
    "--name",
    container,
    "--publish",
    "127.0.0.1::10000",
    AZURITE_IMAGE,
    "azurite-blob",
    "--blobHost",
    "0.0.0.0",
    "--blobPort",
    "10000",
    "--inMemoryPersistence",
    "--skipApiVersionCheck",
  ]);
  const cleanup = () => {
    spawnSync("docker", ["rm", "--force", container], { stdio: "ignore" });
  };
  try {
    const mapping = docker(["port", container, "10000/tcp"]).split("\n")[0] ?? "";
    const port = /:(\d+)$/.exec(mapping)?.[1];
    if (port === undefined) {
      throw new Error(`cannot read the published port of ${container}: ${mapping}`);
    }
    const connectionString = azuriteConnectionString(`http://127.0.0.1:${port}/${AZURITE_ACCOUNT}`);
    await waitForBlobService(connectionString, 60_000);
    return { connectionString, release: async () => cleanup() };
  } catch (error) {
    cleanup();
    throw error;
  }
}

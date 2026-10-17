// A disposable Azurite blob service in Docker for the package tests (download links). Azurite
// checks SAS signatures and permissions, so links are exercised for real.

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { readFileSync } from "node:fs";
import { BlobServiceClient, type ContainerClient } from "@azure/storage-blob";

const AZURITE_IMAGE = "mcr.microsoft.com/azure-storage/azurite:3.35.0";
/** The originals container name of the test config. */
export const ORIGINALS_CONTAINER = "originals";

export interface TestAzurite {
  /** Connection string with the published development account key (local stack). */
  readonly connectionString: string;
  /** Host port of the blob endpoint. */
  readonly blobPort: number;
  readonly service: BlobServiceClient;
  /** The originals container (created). */
  readonly container: ContainerClient;
  /** Uploads a blob into the originals container. */
  put(blobName: string, body: string): Promise<void>;
  stop(): void;
}

/** Azurite's published development account, as used by the local stack (.env.example). */
function azuriteConnectionString(port: number): string {
  const env = readFileSync(new URL("../../.env.example", import.meta.url), "utf8");
  const line = env.split("\n").find((l) => l.startsWith("AZURE_STORAGE_CONNECTION_STRING="));
  assert.ok(line, ".env.example has no AZURE_STORAGE_CONNECTION_STRING");
  return line
    .slice("AZURE_STORAGE_CONNECTION_STRING=".length)
    .replace(/BlobEndpoint=[^;]*/, `BlobEndpoint=http://127.0.0.1:${port}/devstoreaccount1`);
}

function docker(args: string[]): string {
  const result = spawnSync("docker", args, { encoding: "utf8" });
  if (result.status !== 0) {
    throw new Error(`docker ${args[0]} failed: ${result.error?.message ?? result.stderr.trim()}`);
  }
  return result.stdout.trim();
}

/** Starts Azurite and creates the originals container. Call stop() in after(). */
export async function startAzurite(): Promise<TestAzurite> {
  const name = `station-azurite-test-${randomBytes(6).toString("hex")}`;
  docker([
    "run",
    "--detach",
    "--rm",
    "--name",
    name,
    "--publish",
    "127.0.0.1::10000",
    AZURITE_IMAGE,
    "azurite-blob",
    "--blobHost",
    "0.0.0.0",
    "--skipApiVersionCheck",
  ]);
  const stop = () => {
    spawnSync("docker", ["rm", "--force", name], { stdio: "ignore" });
  };
  try {
    const mapping = docker(["port", name, "10000/tcp"]).split("\n")[0] ?? "";
    const blobPort = Number(/:(\d+)$/.exec(mapping)?.[1]);
    const connectionString = azuriteConnectionString(blobPort);
    const service = BlobServiceClient.fromConnectionString(connectionString);
    const container = service.getContainerClient(ORIGINALS_CONTAINER);

    const deadline = Date.now() + 60_000;
    let lastError: unknown;
    let started = false;
    while (!started && Date.now() < deadline) {
      try {
        await container.createIfNotExists();
        started = true;
      } catch (error) {
        lastError = error;
        await new Promise((resolve) => setTimeout(resolve, 500));
      }
    }
    if (!started) {
      throw new Error(`Azurite did not start: ${String(lastError)}`);
    }

    return {
      connectionString,
      blobPort,
      service,
      container,
      async put(blobName, body) {
        await container.getBlockBlobClient(blobName).upload(body, Buffer.byteLength(body));
      },
      stop,
    };
  } catch (error) {
    stop();
    throw error;
  }
}

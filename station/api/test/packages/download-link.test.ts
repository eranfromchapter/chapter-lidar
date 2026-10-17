// Signed download links (src/routes/packages/download.ts): read-only, one blob, 10 minutes,
// bim/admin only, verified files only, audited without the URL. Signed links are exercised
// against a disposable Azurite container (it checks SAS signatures and permissions) and a
// migrated throwaway Postgres.
//
// The OpenAPI document has no download operation yet, so the tests mount issueDownloadLink on
// a test-only route.

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { readFileSync } from "node:fs";
import { after, before, describe, it } from "node:test";
import { BlobServiceClient, type UserDelegationKey } from "@azure/storage-blob";
import type { FastifyInstance } from "fastify";
import {
  CLOCK_SKEW_MS,
  DOWNLOAD_LINK_TTL_MS,
  accountNameFromUrl,
  attachmentDisposition,
  createReadLinkSigner,
  issueDownloadLink,
  readLinkSignerFromConfig,
  type ReadLinkSigner,
} from "../../src/routes/packages/download.js";
import { testConfig } from "../core/helpers.js";
import {
  PACKAGE_ID,
  PLAN_DXF_PATH,
  REVISION_2_ID,
  UNKNOWN_ID,
  MANIFEST,
  seedRegistry,
  startStation,
  type TestStation,
} from "./support.js";

const AZURITE_IMAGE = "mcr.microsoft.com/azure-storage/azurite:3.35.0";
const CONTAINER = "originals";
const LINK_ROUTE = "/v1/test-only/packages/:packageId/download";
const CAPTURE_LINK_ROUTE = "/v1/test-only/capture/packages/:packageId/download";

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

const containerName = `station-azurite-test-${randomBytes(6).toString("hex")}`;
let connectionString: string;
let blobPort: number;
let service: BlobServiceClient;
let station: TestStation;
let signer: ReadLinkSigner;

const BLOB_BODY = "0\nSECTION\n2\nENTITIES\n0\nENDSEC\n0\nEOF\n";
const OTHER_BODY = "other file";

function linkRoutes(app: FastifyInstance): void {
  const handler = async (request: { params: unknown; query: unknown }) => {
    const { packageId } = request.params as { packageId: string };
    const { path } = request.query as { path: string };
    return issueDownloadLink(request as never, packageId, path);
  };
  app.get(LINK_ROUTE, { config: { roles: ["bim", "admin"] } }, handler);
  // Wider route roles, to show issueDownloadLink checks the role itself.
  app.get(CAPTURE_LINK_ROUTE, { config: { roles: ["capture", "bim", "admin"] } }, handler);
}

async function waitForAzurite(): Promise<void> {
  const deadline = Date.now() + 60_000;
  let lastError: unknown;
  while (Date.now() < deadline) {
    try {
      await service.getContainerClient(CONTAINER).createIfNotExists();
      return;
    } catch (error) {
      lastError = error;
      await new Promise((resolve) => setTimeout(resolve, 500));
    }
  }
  throw new Error(`Azurite did not start: ${String(lastError)}`);
}

before(async () => {
  docker([
    "run",
    "--detach",
    "--rm",
    "--name",
    containerName,
    "--publish",
    "127.0.0.1::10000",
    AZURITE_IMAGE,
    "azurite-blob",
    "--blobHost",
    "0.0.0.0",
    "--skipApiVersionCheck",
  ]);
  const mapping = docker(["port", containerName, "10000/tcp"]).split("\n")[0] ?? "";
  blobPort = Number(/:(\d+)$/.exec(mapping)?.[1]);
  connectionString = azuriteConnectionString(blobPort);
  service = BlobServiceClient.fromConnectionString(connectionString);
  await waitForAzurite();

  const container = service.getContainerClient(CONTAINER);
  await container
    .getBlockBlobClient(`${PACKAGE_ID}/${PLAN_DXF_PATH}`)
    .upload(BLOB_BODY, BLOB_BODY.length);
  const otherPath = MANIFEST.files.find((f) => f.role === "rooms_csv")!.path;
  await container
    .getBlockBlobClient(`${PACKAGE_ID}/${otherPath}`)
    .upload(OTHER_BODY, OTHER_BODY.length);

  signer = readLinkSignerFromConfig(
    testConfig({ AZURE_STORAGE_CONNECTION_STRING: connectionString }),
  );
  station = await startStation({ services: { downloadLinks: signer }, routes: linkRoutes });
  await seedRegistry(station.db);
});

after(async () => {
  await station?.close();
  spawnSync("docker", ["rm", "--force", containerName], { stdio: "ignore" });
});

async function requestLink(
  path: string,
  roles: ("capture" | "bim" | "admin")[] = ["bim"],
  route = LINK_ROUTE,
  packageId = PACKAGE_ID,
) {
  return station.app.inject({
    method: "GET",
    url: route.replace(":packageId", packageId),
    query: { path },
    headers: await station.auth(roles),
  });
}

describe("download links for bim and admin", () => {
  it("returns a read-only link to the verified blob that expires in 10 minutes", async () => {
    const started = Date.now();
    const response = await requestLink(PLAN_DXF_PATH);
    assert.equal(response.statusCode, 200, response.body);
    const link = response.json() as { path: string; url: string; expiresAt: string };
    assert.equal(link.path, PLAN_DXF_PATH);
    const expires = Date.parse(link.expiresAt);
    assert.ok(expires <= started + DOWNLOAD_LINK_TTL_MS + 1000);
    assert.ok(expires >= started + DOWNLOAD_LINK_TTL_MS - 2000);

    const url = new URL(link.url);
    assert.equal(url.searchParams.get("sp"), "r");
    assert.equal(url.searchParams.get("sr"), "b");
    const st = Date.parse(url.searchParams.get("st") ?? "");
    const se = Date.parse(url.searchParams.get("se") ?? "");
    assert.equal(se - st, DOWNLOAD_LINK_TTL_MS + CLOCK_SKEW_MS);

    const download = await fetch(link.url);
    assert.equal(download.status, 200);
    assert.equal(await download.text(), BLOB_BODY);
    assert.equal(download.headers.get("content-disposition"), attachmentDisposition("plan.dxf"));
  });

  it("cannot write, delete or read another blob with the link", async () => {
    const response = await requestLink(PLAN_DXF_PATH, ["admin"]);
    const { url } = response.json() as { url: string };

    const put = await fetch(url, {
      method: "PUT",
      headers: { "x-ms-blob-type": "BlockBlob", "content-type": "text/plain" },
      body: "overwritten",
    });
    assert.equal(put.status, 403);
    const del = await fetch(url, { method: "DELETE" });
    assert.equal(del.status, 403);

    const other = new URL(url);
    other.pathname = other.pathname.replace(/plan\.dxf$/, "rooms.csv");
    assert.equal((await fetch(other)).status, 403);

    const still = await fetch(url);
    assert.equal(await still.text(), BLOB_BODY);
  });

  it("is rejected by storage once expired", async () => {
    const past = readLinkSignerFromConfig(
      testConfig({ AZURE_STORAGE_CONNECTION_STRING: connectionString }),
    );
    const expired = createReadLinkSigner({
      kind: "shared-key",
      containerName: CONTAINER,
      serviceUrl: service.url,
      credential: service.credential as never,
      now: () => Date.now() - DOWNLOAD_LINK_TTL_MS - 60_000,
    });
    const fresh = await past.signRead(`${PACKAGE_ID}/${PLAN_DXF_PATH}`);
    assert.equal((await fetch(fresh.url)).status, 200);
    const stale = await expired.signRead(`${PACKAGE_ID}/${PLAN_DXF_PATH}`);
    assert.equal((await fetch(stale.url)).status, 403);
  });

  it("audits every link without the URL or signature", async () => {
    const response = await requestLink(PLAN_DXF_PATH);
    const { url, expiresAt } = response.json() as { url: string; expiresAt: string };
    const signature = new URL(url).searchParams.get("sig") ?? "";
    assert.ok(signature.length > 0);
    const rows = await station.db.query<{
      action: string;
      target_type: string;
      target_id: string;
      details: Record<string, unknown>;
    }>(
      `SELECT action, target_type, target_id, details FROM audit_log
        WHERE action = 'package_file.download_link' ORDER BY audit_id DESC LIMIT 1`,
    );
    assert.deepEqual(rows.rows[0], {
      action: "package_file.download_link",
      target_type: "package",
      target_id: PACKAGE_ID,
      details: { path: PLAN_DXF_PATH, expiresAt },
    });
    const all = await station.db.query("SELECT details::text AS d FROM audit_log");
    assert.ok(!all.rows.some((row) => String(row.d).includes(signature)));
    assert.ok(!station.logs.some((line) => line.includes(signature)), "signature in logs");
  });
});

describe("download links are refused", () => {
  it("for the capture role, by the route and by issueDownloadLink itself", async () => {
    const viaRoute = await requestLink(PLAN_DXF_PATH, ["capture"]);
    assert.equal(viaRoute.statusCode, 403);
    const viaHelper = await requestLink(PLAN_DXF_PATH, ["capture"], CAPTURE_LINK_ROUTE);
    assert.equal(viaHelper.statusCode, 403);
    assert.equal((viaHelper.json() as { code: string }).code, "forbidden");
  });

  it("for a file that is not verified", async () => {
    const pending = MANIFEST.files[0]!.path;
    const response = await requestLink(pending, ["bim"], LINK_ROUTE, REVISION_2_ID);
    assert.equal(response.statusCode, 409);
    assert.equal((response.json() as { code: string }).code, "file_not_verified");
  });

  it("for an unknown file or package", async () => {
    for (const [packageId, path] of [
      [PACKAGE_ID, "Original Exports/none.dxf"],
      [UNKNOWN_ID, PLAN_DXF_PATH],
      ["not-a-uuid", PLAN_DXF_PATH],
    ] as const) {
      const response = await requestLink(path, ["bim"], LINK_ROUTE, packageId);
      assert.equal(response.statusCode, 404, `${packageId} ${path}`);
    }
  });
});

describe("signer configuration", () => {
  it("needs storage settings and an account key in the connection string", () => {
    assert.throws(() => readLinkSignerFromConfig(testConfig()), /AZURE_STORAGE_ACCOUNT_URL or/);
    assert.throws(
      () =>
        readLinkSignerFromConfig(
          testConfig({
            AZURE_STORAGE_CONNECTION_STRING:
              "BlobEndpoint=https://acct.blob.core.windows.net/;SharedAccessSignature=sv=2024-01-01&sig=abc",
          }),
        ),
      /must carry an account key/,
    );
  });

  it("hands out links on the public blob endpoint when one is configured", async () => {
    const local = readLinkSignerFromConfig(
      testConfig({
        AZURE_STORAGE_CONNECTION_STRING: connectionString.replace("127.0.0.1", "azurite"),
        STORAGE_PUBLIC_BLOB_ENDPOINT: `http://localhost:${blobPort}/devstoreaccount1`,
      }),
    );
    const link = await local.signRead(`${PACKAGE_ID}/${PLAN_DXF_PATH}`);
    assert.ok(link.url.startsWith(`http://localhost:${blobPort}/devstoreaccount1/originals/`));
    assert.equal((await fetch(link.url)).status, 200);
  });

  it("signs with a cached user delegation key in Azure, https only", async () => {
    let now = Date.parse("2026-10-17T15:00:00Z");
    const requested: [Date, Date][] = [];
    const signerWithKey = createReadLinkSigner({
      kind: "user-delegation",
      containerName: CONTAINER,
      serviceUrl: "https://chapterstation.blob.core.windows.net/",
      accountName: accountNameFromUrl("https://chapterstation.blob.core.windows.net/"),
      now: () => now,
      getDelegationKey: async (startsOn, expiresOn): Promise<UserDelegationKey> => {
        requested.push([startsOn, expiresOn]);
        return {
          signedObjectId: "0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d",
          signedTenantId: "4f1c2b8a-1d2e-4c3b-9a8f-0123456789ab",
          signedStartsOn: startsOn,
          signedExpiresOn: expiresOn,
          signedService: "b",
          signedVersion: "2025-01-05",
          value: Buffer.from("k".repeat(32)).toString("base64"),
        };
      },
    });
    const first = new URL((await signerWithKey.signRead("p/a b/c.dxf")).url);
    assert.equal(first.origin, "https://chapterstation.blob.core.windows.net");
    assert.equal(first.pathname, "/originals/p/a%20b/c.dxf");
    assert.equal(first.searchParams.get("sp"), "r");
    assert.equal(first.searchParams.get("spr"), "https");
    assert.equal(first.searchParams.get("skoid"), "0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d");
    assert.equal(requested.length, 1);

    now += 30 * 60_000;
    await signerWithKey.signRead("p/x.dxf");
    assert.equal(requested.length, 1, "key reused while it outlives the link");

    now += 25 * 60_000;
    await signerWithKey.signRead("p/x.dxf");
    assert.equal(requested.length, 2, "key refreshed before the link would outlive it");
  });

  it("reads the account name from the account URL", () => {
    assert.equal(
      accountNameFromUrl("https://chapterstation.blob.core.windows.net"),
      "chapterstation",
    );
    assert.equal(accountNameFromUrl("http://127.0.0.1:10000/devstoreaccount1"), "devstoreaccount1");
  });
});

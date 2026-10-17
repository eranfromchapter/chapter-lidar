// A real station for the upload tests: the Fastify app with every route area, Entra tokens from
// an in-process issuer, a migrated Postgres database and Azurite. Uploads go straight to the
// SAS URLs the station hands out, exactly as the app does.

import type { FastifyInstance, LightMyRequestResponse } from "fastify";
import { buildServer } from "../../../src/core/app.js";
import type { Role } from "../../../src/core/auth.js";
import type { StationConfig } from "../../../src/core/config.js";
import { createDatabase, urlConnection, type Database } from "../../../src/core/db.js";
import type { OriginalsStorage } from "../../../src/storage/originals.js";
import { logCollector, startTestIssuer, testConfig, type TestIssuer } from "../../core/helpers.js";
import { startTestBlobService, startTestDatabase } from "./infra.js";
import type { TestPackage } from "./package.js";

export interface UploadTargetView {
  url: string;
  method: "PUT";
  headers: Record<string, string>;
  expiresAt: string;
}

export interface SessionFileView {
  path: string;
  status: string;
  upload?: UploadTargetView;
}

export interface UploadSessionView {
  packageId: string;
  visitId: string;
  dealId: string;
  revision: number;
  status: string;
  files: SessionFileView[];
}

export interface FileCheckView {
  path: string;
  status: string;
  expectedSha256: string;
  actualSha256?: string;
  expectedBytes: number;
  actualBytes?: number;
  checkedAt: string;
}

export interface UploadStation {
  readonly app: FastifyInstance;
  readonly db: Database;
  readonly config: StationConfig;
  readonly storage: OriginalsStorage;
  readonly logs: string[];
  token(roles?: Role[]): Promise<string>;
  inject(
    method: "GET" | "POST" | "PUT" | "DELETE" | "PATCH",
    url: string,
    body?: unknown,
    roles?: Role[],
  ): Promise<LightMyRequestResponse>;
  openSession(pkg: TestPackage, roles?: Role[]): Promise<LightMyRequestResponse>;
  complete(packageId: string, path: string): Promise<LightMyRequestResponse>;
  seal(packageId: string, manifestBytes: Buffer): Promise<LightMyRequestResponse>;
  close(): Promise<void>;
}

/** PUT bytes to an upload target, as the app does (Put Blob). */
export async function putToTarget(target: UploadTargetView, data: Buffer): Promise<Response> {
  return fetch(target.url, {
    method: target.method,
    headers: { ...target.headers, "content-length": String(data.length) },
    body: data,
  });
}

export async function startUploadStation(
  extraEnv: Record<string, string | undefined> = {},
): Promise<UploadStation> {
  const database = await startTestDatabase();
  let blobs: Awaited<ReturnType<typeof startTestBlobService>> | undefined;
  let issuer: TestIssuer | undefined;
  let db: Database | undefined;
  let app: FastifyInstance | undefined;
  try {
    blobs = await startTestBlobService();
    issuer = await startTestIssuer();
    const config = testConfig({
      DATABASE_URL: database.url,
      ENTRA_JWKS_URL: issuer.jwksUrl,
      AZURE_STORAGE_CONNECTION_STRING: blobs.connectionString,
      STORAGE_ORIGINALS_CONTAINER: "originals",
      ...extraEnv,
    });
    db = createDatabase({ connection: urlConnection(database.url), poolMax: 5 });
    const logs = logCollector();
    app = await buildServer({ config, db, logStream: logs.stream });
    await app.ready();
    const storage = app.services.originals;
    if (storage === undefined) {
      throw new Error("the upload routes did not register the originals storage");
    }

    const testIssuer = issuer;
    const server = app;
    const token = (roles: Role[] = ["capture"]) => testIssuer.mint({ roles });
    const inject: UploadStation["inject"] = async (method, url, body, roles) =>
      server.inject({
        method,
        url,
        headers: { authorization: `Bearer ${await token(roles)}` },
        ...(body === undefined ? {} : { payload: body as Record<string, unknown> }),
      });

    const station: UploadStation = {
      app: server,
      db,
      config,
      storage,
      logs: logs.lines,
      token,
      inject,
      openSession: (pkg, roles) => inject("POST", "/v1/packages", pkg.session, roles),
      complete: (packageId, path) =>
        inject("POST", `/v1/packages/${packageId}/files/complete`, { path }),
      seal: async (packageId, manifestBytes) =>
        server.inject({
          method: "POST",
          url: `/v1/packages/${packageId}/seal`,
          headers: {
            authorization: `Bearer ${await token()}`,
            "content-type": "application/json",
          },
          payload: manifestBytes,
        }),
      close: async () => {
        await server.close();
        await db?.close();
        await testIssuer.close();
        await blobs?.release();
        await database.release();
      },
    };
    return station;
  } catch (error) {
    await app?.close().catch(() => undefined);
    await db?.close().catch(() => undefined);
    await issuer?.close().catch(() => undefined);
    await blobs?.release().catch(() => undefined);
    await database.release().catch(() => undefined);
    throw error;
  }
}

/** Uploads every file of a session that has a target (optionally with other bytes) and reports it. */
export async function uploadAll(
  station: UploadStation,
  pkg: TestPackage,
  session: UploadSessionView,
  replace: ReadonlyMap<string, Buffer | null> = new Map(),
): Promise<Map<string, FileCheckView>> {
  const results = new Map<string, FileCheckView>();
  for (const file of session.files) {
    if (file.upload === undefined) {
      continue;
    }
    const override = replace.get(file.path);
    if (override !== null) {
      const data = override ?? pkg.files.get(file.path);
      if (data === undefined) {
        throw new Error(`no bytes for ${file.path}`);
      }
      const put = await putToTarget(file.upload, data);
      if (put.status !== 201) {
        throw new Error(`upload of ${file.path} failed: ${put.status} ${await put.text()}`);
      }
    }
    const response = await station.complete(pkg.packageId, file.path);
    if (response.statusCode !== 200) {
      throw new Error(`complete ${file.path}: ${response.statusCode} ${response.body}`);
    }
    results.set(file.path, response.json() as FileCheckView);
  }
  return results;
}

/** Opens a session, uploads every file correctly and checks it; returns the session. */
export async function uploadVerifiedPackage(
  station: UploadStation,
  pkg: TestPackage,
): Promise<UploadSessionView> {
  const opened = await station.openSession(pkg);
  if (opened.statusCode !== 201) {
    throw new Error(`open session: ${opened.statusCode} ${opened.body}`);
  }
  const session = opened.json() as UploadSessionView;
  const results = await uploadAll(station, pkg, session);
  for (const [path, result] of results) {
    if (result.status !== "verified") {
      throw new Error(`${path} was not verified: ${result.status}`);
    }
  }
  return session;
}

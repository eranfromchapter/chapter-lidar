// Fast unit tests of the upload area (no Docker): cross-field rules, blob naming, storage
// configuration, and the 503 answer when no storage is configured.

import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";
import type { FastifyInstance } from "fastify";
import { buildServer } from "../../src/core/app.js";
import {
  MAX_FILE_PATH_LENGTH,
  MAX_FILE_PATH_SEGMENTS,
  manifestMismatchErrors,
  sessionRequestErrors,
} from "../../src/routes/uploads/rules.js";
import type { UploadSessionRequest } from "../../src/routes/uploads/schemas.js";
import { createAzureOriginalsStorage } from "../../src/storage/azure-blob.js";
import {
  OriginalsStorageError,
  attemptBlobName,
  attemptOf,
  firstBlobName,
  manifestBlobName,
  nextAttemptBlobName,
  unconfiguredOriginals,
} from "../../src/storage/originals.js";
import {
  fakeDatabase,
  logCollector,
  startTestIssuer,
  testConfig,
  type TestIssuer,
} from "../core/helpers.js";
import { makePackage } from "./support/package.js";

const PACKAGE_ID = "3f2a1b4c-5d6e-4f70-8a9b-0c1d2e3f4a5b";

describe("sessionRequestErrors", () => {
  it("accepts the fixture session", () => {
    assert.deepEqual(sessionRequestErrors(makePackage().session), []);
  });

  it("enforces supersedesPackageId exactly when revision > 1, and never itself", () => {
    const session = makePackage().session;
    assert.deepEqual(
      sessionRequestErrors({ ...session, revision: 2 }).map((e) => e.pointer),
      ["/supersedesPackageId"],
    );
    assert.deepEqual(
      sessionRequestErrors({ ...session, supersedesPackageId: PACKAGE_ID }).map((e) => e.pointer),
      ["/supersedesPackageId"],
    );
    const self: UploadSessionRequest = {
      ...session,
      revision: 2,
      supersedesPackageId: session.packageId,
    };
    assert.deepEqual(
      sessionRequestErrors(self).map((e) => e.message),
      ["must differ from packageId"],
    );
  });

  it("reports duplicate paths, the reserved manifest path and capture fields by role", () => {
    const session = makePackage().session;
    const [record, controls, capture, ...rest] = session.files;
    assert.ok(record && controls && capture);
    const body: UploadSessionRequest = {
      ...session,
      files: [
        { ...record, captureId: PACKAGE_ID, areaKey: "floor-1" },
        { ...controls, path: `Source Register/${session.visitId}/manifest.json` },
        { path: capture.path, role: capture.role, sha256: capture.sha256, bytes: capture.bytes },
        { ...capture },
        ...rest,
      ],
    };
    assert.deepEqual(
      sessionRequestErrors(body).map((e) => e.pointer),
      [
        "/files/0/captureId",
        "/files/0/areaKey",
        "/files/1/path",
        "/files/2/captureId",
        "/files/2/areaKey",
        "/files/3/path",
      ],
    );
  });
});

describe("blob name limits", () => {
  it("refuses paths that cannot become blob names", () => {
    const session = makePackage().session;
    const [first, ...rest] = session.files;
    assert.ok(first);
    const tooLong = `Original Exports/${"a".repeat(MAX_FILE_PATH_LENGTH)}`;
    const tooDeep = `Original Exports/${Array.from({ length: MAX_FILE_PATH_SEGMENTS }, () => "d").join("/")}`;
    for (const path of [tooLong, tooDeep]) {
      const errors = sessionRequestErrors({ ...session, files: [{ ...first, path }, ...rest] });
      assert.deepEqual(
        errors.map((e) => e.pointer),
        ["/files/0/path"],
        path.slice(0, 40),
      );
    }
    const longest = `${"a".repeat(MAX_FILE_PATH_LENGTH)}`;
    assert.ok(`${PACKAGE_ID}.retry-999999/${longest}`.length <= 1024);
  });
});

describe("manifestMismatchErrors", () => {
  const pkg = makePackage();
  const session = {
    packageId: pkg.packageId,
    visitId: pkg.visitId,
    revision: 1,
  };

  it("accepts the manifest of the session", () => {
    assert.deepEqual(manifestMismatchErrors(pkg.manifest, session, pkg.session.files), []);
  });

  it("reports changed fields, unlisted and undeclared files", () => {
    const manifest = structuredClone(pkg.manifest);
    manifest.files[1]!.sha256 = "0".repeat(64);
    manifest.files[2]!.captureId = PACKAGE_ID;
    const dropped = manifest.files.pop();
    manifest.files.push({ ...manifest.files[3]!, path: "Original Exports/new.bin" });
    manifest.supersedesPackageId = PACKAGE_ID;
    const errors = manifestMismatchErrors(manifest, session, pkg.session.files);
    const last = manifest.files.length - 1;
    assert.deepEqual(
      errors.map((e) => e.pointer),
      [
        "/supersedesPackageId",
        "/files/1/sha256",
        "/files/2/captureId",
        `/files/${last}/path`,
        "/files",
      ],
    );
    assert.match(errors.at(-1)?.message ?? "", new RegExp(dropped?.path.split("/").at(-1) ?? "x"));
  });

  it("reports a path listed twice", () => {
    const manifest = structuredClone(pkg.manifest);
    manifest.files.push(structuredClone(manifest.files[0]!));
    const errors = manifestMismatchErrors(manifest, session, pkg.session.files);
    assert.deepEqual(
      errors.map((e) => e.message),
      ["is listed more than once"],
    );
  });
});

describe("blob names", () => {
  const path = "Original Exports/floor-1/abc/points.las";

  it("puts attempt 1 under <packageId>/<path> and retries under <packageId>.retry-<n>/", () => {
    assert.equal(firstBlobName(PACKAGE_ID, path), `${PACKAGE_ID}/${path}`);
    assert.equal(attemptBlobName(PACKAGE_ID, path, 1), `${PACKAGE_ID}/${path}`);
    assert.equal(attemptBlobName(PACKAGE_ID, path, 3), `${PACKAGE_ID}.retry-3/${path}`);
    assert.equal(
      nextAttemptBlobName(PACKAGE_ID, path, `${PACKAGE_ID}/${path}`),
      `${PACKAGE_ID}.retry-2/${path}`,
    );
    assert.equal(
      nextAttemptBlobName(PACKAGE_ID, path, `${PACKAGE_ID}.retry-9/${path}`),
      `${PACKAGE_ID}.retry-10/${path}`,
    );
    assert.equal(
      manifestBlobName(PACKAGE_ID, "c1b6d1fb-17af-4f4a-877c-2565ef9bdb86"),
      `${PACKAGE_ID}/Source Register/c1b6d1fb-17af-4f4a-877c-2565ef9bdb86/manifest.json`,
    );
  });

  it("refuses blob names of another file or package", () => {
    for (const name of [
      `${PACKAGE_ID}/other.bin`,
      `${PACKAGE_ID}.retry-1/${path}`,
      `${PACKAGE_ID}.retry-x/${path}`,
      `00000000-0000-4000-8000-000000000000/${path}`,
      `${PACKAGE_ID}.retry-2/other.bin`,
    ]) {
      assert.throws(() => attemptOf(PACKAGE_ID, path, name), RangeError, name);
    }
    assert.throws(() => attemptBlobName(PACKAGE_ID, path, 0), RangeError);
  });
});

describe("storage configuration", () => {
  it("returns undefined when no storage is configured", () => {
    assert.equal(createAzureOriginalsStorage({ originalsContainer: "originals" }), undefined);
  });

  it("rejects a connection string without an account key, without quoting it", () => {
    const connectionString =
      "BlobEndpoint=https://example.blob.core.windows.net;SharedAccessSignature=sv=2025&sig=c2VjcmV0";
    assert.throws(
      () => createAzureOriginalsStorage({ originalsContainer: "originals", connectionString }),
      (error: unknown) =>
        error instanceof OriginalsStorageError &&
        !error.message.includes("c2VjcmV0") &&
        error.code === "InvalidConnectionString",
    );
  });

  it("unconfigured storage fails every call with NotConfigured", async () => {
    const storage = unconfiguredOriginals("originals");
    await assert.rejects(storage.grantUpload("a"), { code: "NotConfigured" });
    await assert.rejects(storage.digest("a"), { code: "NotConfigured" });
  });
});

describe("routes without configured storage", () => {
  let issuer: TestIssuer;
  let app: FastifyInstance;
  const logs = logCollector();

  before(async () => {
    issuer = await startTestIssuer();
    app = await buildServer({
      config: testConfig({ ENTRA_JWKS_URL: issuer.jwksUrl }),
      db: fakeDatabase(),
      logStream: logs.stream,
    });
    await app.ready();
  });

  after(async () => {
    await app.close();
    await issuer.close();
  });

  it("start, check tokens, and answer 503 storage_unavailable when a target is needed", async () => {
    const anonymous = await app.inject({ method: "POST", url: "/v1/packages", payload: {} });
    assert.equal(anonymous.statusCode, 401);
    const token = await issuer.mint({ roles: ["capture"] });
    const response = await app.inject({
      method: "POST",
      url: "/v1/packages",
      headers: { authorization: `Bearer ${token}` },
      payload: makePackage().session,
    });
    assert.equal(response.statusCode, 503, response.body);
    assert.equal((response.json() as { code: string }).code, "storage_unavailable");
    assert.ok(logs.lines.some((line) => line.includes("NotConfigured")));
  });

  it("check the contract rules before touching the registry (422)", async () => {
    const token = await issuer.mint({ roles: ["admin"] });
    const response = await app.inject({
      method: "POST",
      url: "/v1/packages",
      headers: { authorization: `Bearer ${token}` },
      payload: { ...makePackage().session, revision: 2 },
    });
    assert.equal(response.statusCode, 422, response.body);
  });
});

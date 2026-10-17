// F7 AC6 for the uploads area: createUploadSession, completeFile and sealPackage are
// implemented with the paths, methods, roles, request schemas and response schemas of
// contract/openapi/station.yaml.
//
// 1. Routes: each operation is registered at its path with exactly its x-roles.
// 2. Request schemas: the route schemas accept and reject the same bodies as station.yaml on a
//    corpus of valid and invalid bodies (the seal body is validated with the contract's
//    validateManifest, which is the schema station.yaml references). Documented, deliberate
//    differences are asserted explicitly.
// 3. Responses: a full flow against Postgres and Azurite; every response status must be
//    documented for its operation and every body must match the documented schema.

import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, before, describe, it } from "node:test";
import { validateManifest } from "@chapter/capture-contract";
import type { FastifyInstance, LightMyRequestResponse } from "fastify";
import { buildServer } from "../../src/core/app.js";
import {
  completeFileRequestSchema,
  packageIdParamsSchema,
  uploadSessionRequestSchema,
} from "../../src/routes/uploads/schemas.js";
import { fakeDatabase, testConfig } from "../core/helpers.js";
import { OpenApiContract } from "./support/openapi.js";
import { makePackage, type TestPackage } from "./support/package.js";
import {
  putToTarget,
  startUploadStation,
  type UploadSessionView,
  type UploadStation,
} from "./support/station.js";

const OPERATIONS = ["createUploadSession", "completeFile", "sealPackage"] as const;

const contract = new OpenApiContract();

describe("routes", () => {
  let app: FastifyInstance;

  before(async () => {
    app = await buildServer({ config: testConfig(), db: fakeDatabase() });
    await app.ready();
  });

  after(async () => {
    await app.close();
  });

  for (const operationId of OPERATIONS) {
    it(`${operationId} is registered at its path with exactly its x-roles`, () => {
      const op = contract.operation(operationId);
      const route = app.routeAccess.find(
        (access) => access.url === op.routeUrl && access.method.split(",").includes(op.method),
      );
      assert.ok(route, `${op.method} ${op.routeUrl} is not registered`);
      assert.deepEqual([...route.roles].sort(), [...op.roles].sort());
    });
  }
});

type Body = Record<string, unknown> & { files: Record<string, unknown>[] };

function sessionCorpus(): [string, unknown][] {
  const valid = () => structuredClone(makePackage().session) as unknown as Body;
  const mutate = (label: string, change: (body: Body) => void): [string, unknown] => {
    const body = valid();
    change(body);
    return [label, body];
  };
  return [
    ["the fixture session", valid()],
    mutate("revision 2 with supersedesPackageId", (b) => {
      b.revision = 2;
      b.supersedesPackageId = randomUUID();
    }),
    mutate("bytes 0", (b) => (b.files[0]!.bytes = 0)),
    mutate("a 64-character dealId", (b) => (b.dealId = "d".repeat(64))),
    mutate("a 1024-character path", (b) => (b.files[0]!.path = `a/${"p".repeat(1022)}`)),
    mutate("missing packageId", (b) => delete b.packageId),
    mutate("missing visitId", (b) => delete b.visitId),
    mutate("missing dealId", (b) => delete b.dealId),
    mutate("missing revision", (b) => delete b.revision),
    mutate("missing files", (b) => delete (b as Partial<Body>).files),
    mutate("empty files", (b) => (b.files = [])),
    mutate("unknown top-level property", (b) => (b.note = "x")),
    mutate("unknown file property", (b) => (b.files[0]!.mime = "application/json")),
    mutate("uppercase uuid", (b) => (b.packageId = String(b.packageId).toUpperCase())),
    mutate("non-uuid visitId", (b) => (b.visitId = "visit-1")),
    mutate("a 65-character dealId", (b) => (b.dealId = "d".repeat(65))),
    mutate("empty dealId", (b) => (b.dealId = "")),
    mutate("revision 0", (b) => (b.revision = 0)),
    mutate("fractional revision", (b) => (b.revision = 1.5)),
    mutate("negative bytes", (b) => (b.files[0]!.bytes = -1)),
    mutate("fractional bytes", (b) => (b.files[0]!.bytes = 1.5)),
    mutate("short sha256", (b) => (b.files[0]!.sha256 = "ab")),
    mutate("uppercase sha256", (b) => (b.files[0]!.sha256 = "A".repeat(64))),
    mutate("unknown role", (b) => (b.files[0]!.role = "selfie")),
    mutate("uppercase areaKey", (b) => (b.files[2]!.areaKey = "Floor-1")),
    mutate("path with ..", (b) => (b.files[0]!.path = "a/../b")),
    mutate("path with leading slash", (b) => (b.files[0]!.path = "/a")),
    mutate("path with trailing slash", (b) => (b.files[0]!.path = "a/")),
    mutate("path with //", (b) => (b.files[0]!.path = "a//b")),
    mutate("path with backslash", (b) => (b.files[0]!.path = "a\\b")),
    mutate("path with a control character", (b) => (b.files[0]!.path = "a\u0007b")),
    mutate("a 1025-character path", (b) => (b.files[0]!.path = "p".repeat(1025))),
    mutate("files not an array", (b) => (b.files = {} as unknown as Body["files"])),
    ["not an object", ["a"]],
  ];
}

describe("request schemas", () => {
  it("createUploadSession: the route schema accepts exactly what station.yaml accepts", () => {
    const openapi = contract.requestBody("createUploadSession");
    const route = contract.compile(uploadSessionRequestSchema);
    for (const [label, body] of sessionCorpus()) {
      assert.equal(route(body), openapi(body), label);
    }
  });

  it("createUploadSession: documented stricter bounds (registry limits) are the only differences", () => {
    const openapi = contract.requestBody("createUploadSession");
    const route = contract.compile(uploadSessionRequestSchema);
    const huge = structuredClone(makePackage().session) as unknown as Body;
    huge.revision = 2_147_483_648;
    huge.supersedesPackageId = randomUUID();
    assert.equal(openapi(huge), true);
    assert.equal(route(huge), false, "revision above Postgres integer range");
    const big = structuredClone(makePackage().session) as unknown as Body;
    big.files[0]!.bytes = Number.MAX_SAFE_INTEGER + 1;
    assert.equal(openapi(big), true);
    assert.equal(route(big), false, "bytes above the safe integer range");
  });

  it("completeFile: the route schema accepts exactly what station.yaml accepts", () => {
    const openapi = contract.requestBody("completeFile");
    const route = contract.compile(completeFileRequestSchema);
    const corpus: unknown[] = [
      { path: "Original Exports/floor-1/a/plan.pdf" },
      {},
      { path: "" },
      { path: "/a" },
      { path: "a/../b" },
      { path: "a", extra: 1 },
      { path: 3 },
      "a",
    ];
    for (const body of corpus) {
      assert.equal(route(body), openapi(body), JSON.stringify(body));
    }
  });

  it("packageId path parameter: same rule as station.yaml", () => {
    const openapi = contract.validatorAt("/components/parameters/PackageId/schema");
    const route = contract.compile(packageIdParamsSchema);
    for (const value of [randomUUID(), randomUUID().toUpperCase(), "x", ""]) {
      assert.equal(route({ packageId: value }), openapi(value), value);
    }
  });

  it("sealPackage: validateManifest accepts exactly what station.yaml accepts", () => {
    const openapi = contract.requestBody("sealPackage");
    const pkg = makePackage();
    const revision2 = makePackage({ revision: 2, supersedesPackageId: randomUUID() }).manifest;
    const corpus: [string, unknown][] = [
      ["fixture manifest", pkg.manifest],
      ["revision 2 manifest", revision2],
      ["revision 2 without supersedes", { ...revision2, supersedesPackageId: undefined }],
      ["unknown property", { ...pkg.manifest, extra: 1 }],
      ["wrong schemaVersion", { ...pkg.manifest, schemaVersion: "2.0.0" }],
      ["no files", { ...pkg.manifest, files: [] }],
      ["fractional seconds", { ...pkg.manifest, sealedAt: "2026-10-17T15:10:00.5Z" }],
      ["array", [pkg.manifest]],
    ];
    for (const [label, body] of corpus) {
      const json = JSON.parse(JSON.stringify(body)) as unknown;
      assert.equal(validateManifest(json).ok, openapi(json), label);
    }
  });
});

describe("responses match station.yaml", () => {
  let station: UploadStation;
  let pkg: TestPackage;
  let session: UploadSessionView;

  before(async () => {
    station = await startUploadStation();
    pkg = makePackage();
  });

  after(async () => {
    await station?.close();
  });

  const check = (operationId: (typeof OPERATIONS)[number], response: LightMyRequestResponse) =>
    contract.assertResponse(operationId, response);

  it("createUploadSession: 201, 200, 400, 401, 403, 409, 422", async () => {
    const created = await station.openSession(pkg);
    assert.equal(created.statusCode, 201);
    check("createUploadSession", created);
    session = created.json() as UploadSessionView;

    const resumed = await station.openSession(pkg);
    assert.equal(resumed.statusCode, 200);
    check("createUploadSession", resumed);

    const bad = await station.inject("POST", "/v1/packages", { ...pkg.session, extra: 1 });
    assert.equal(bad.statusCode, 400);
    check("createUploadSession", bad);

    const anonymous = await station.app.inject({
      method: "POST",
      url: "/v1/packages",
      payload: pkg.session,
    });
    assert.equal(anonymous.statusCode, 401);
    check("createUploadSession", anonymous);

    const bim = await station.openSession(pkg, ["bim"]);
    assert.equal(bim.statusCode, 403);
    check("createUploadSession", bim);

    const conflict = await station.inject("POST", "/v1/packages", {
      ...pkg.session,
      dealId: "other",
    });
    assert.equal(conflict.statusCode, 409);
    check("createUploadSession", conflict);

    const rule = await station.inject("POST", "/v1/packages", {
      ...makePackage().session,
      revision: 3,
    });
    assert.equal(rule.statusCode, 422);
    check("createUploadSession", rule);
  });

  it("completeFile: 200 (verified, mismatch, not uploaded), 400, 401, 403, 404", async () => {
    const [first, second, third] = session.files;
    assert.ok(first?.upload && second?.upload && third);
    assert.equal((await putToTarget(first.upload, pkg.files.get(first.path)!)).status, 201);
    const verified = await station.complete(pkg.packageId, first.path);
    assert.equal((verified.json() as { status: string }).status, "verified");
    check("completeFile", verified);

    assert.equal((await putToTarget(second.upload, Buffer.from("wrong"))).status, 201);
    const mismatch = await station.complete(pkg.packageId, second.path);
    assert.equal((mismatch.json() as { status: string }).status, "bytes_mismatch");
    check("completeFile", mismatch);

    const missing = await station.complete(pkg.packageId, third.path);
    assert.equal((missing.json() as { status: string }).status, "not_uploaded");
    check("completeFile", missing);

    const again = await station.complete(pkg.packageId, first.path);
    check("completeFile", again);

    const bad = await station.inject("POST", `/v1/packages/${pkg.packageId}/files/complete`, {});
    assert.equal(bad.statusCode, 400);
    check("completeFile", bad);

    const anonymous = await station.app.inject({
      method: "POST",
      url: `/v1/packages/${pkg.packageId}/files/complete`,
      payload: { path: first.path },
    });
    assert.equal(anonymous.statusCode, 401);
    check("completeFile", anonymous);

    const bim = await station.inject(
      "POST",
      `/v1/packages/${pkg.packageId}/files/complete`,
      { path: first.path },
      ["bim"],
    );
    assert.equal(bim.statusCode, 403);
    check("completeFile", bim);

    const notFound = await station.complete(randomUUID(), first.path);
    assert.equal(notFound.statusCode, 404);
    check("completeFile", notFound);
  });

  it("sealPackage: 409, 422, 400, 404, 202, 200; then completeFile 409", async () => {
    const early = await station.seal(pkg.packageId, pkg.manifestBytes);
    assert.equal(early.statusCode, 409);
    check("sealPackage", early);

    const invalid = await station.seal(pkg.packageId, Buffer.from(JSON.stringify({ files: [] })));
    assert.equal(invalid.statusCode, 422);
    check("sealPackage", invalid);

    const notJson = await station.seal(pkg.packageId, Buffer.from("[1,"));
    assert.equal(notJson.statusCode, 400);
    check("sealPackage", notJson);

    const other = makePackage();
    const notFound = await station.seal(other.packageId, other.manifestBytes);
    assert.equal(notFound.statusCode, 404);
    check("sealPackage", notFound);

    // Finish the uploads: resume gives new targets for the rejected and missing files.
    const resumed = (await station.openSession(pkg)).json() as UploadSessionView;
    for (const file of resumed.files) {
      if (file.upload !== undefined) {
        assert.equal((await putToTarget(file.upload, pkg.files.get(file.path)!)).status, 201);
        const result = await station.complete(pkg.packageId, file.path);
        assert.equal((result.json() as { status: string }).status, "verified", file.path);
      }
    }

    const sealed = await station.seal(pkg.packageId, pkg.manifestBytes);
    assert.equal(sealed.statusCode, 202);
    check("sealPackage", sealed);

    const again = await station.seal(pkg.packageId, pkg.manifestBytes);
    assert.equal(again.statusCode, 200);
    check("sealPackage", again);

    const resumedSealed = await station.openSession(pkg);
    assert.equal(resumedSealed.statusCode, 200);
    check("createUploadSession", resumedSealed);

    const late = await station.complete(pkg.packageId, pkg.session.files[0]?.path ?? "");
    assert.equal(late.statusCode, 409);
    check("completeFile", late);
  });
});

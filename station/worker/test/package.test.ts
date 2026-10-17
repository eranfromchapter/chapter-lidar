// Loading a sealed package: blob names from the registry, re-hashing, integrity errors.

import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { describe, it } from "node:test";
import { IntegrityError, loadSealedFiles, type FileRow, type PackageRow } from "../src/package.js";
import type { BlobContent, OriginalsReader } from "../src/storage.js";

const PACKAGE_ID = "6a1f2a8e-0b1c-4d2e-8f3a-4b5c6d7e8f90";
const VISIT_ID = "7b2e3f40-1c2d-4e3f-9a4b-5c6d7e8f9a01";

function sha(data: Buffer): string {
  return createHash("sha256").update(data).digest("hex");
}

function reader(blobs: Map<string, Buffer>): OriginalsReader & { reads: string[] } {
  const reads: string[] = [];
  return {
    container: "originals",
    reads,
    async read(blobName: string, maxBytes: number): Promise<BlobContent | "too_large" | undefined> {
      reads.push(blobName);
      const data = blobs.get(blobName);
      if (data === undefined) {
        return undefined;
      }
      if (data.length > maxBytes) {
        return "too_large";
      }
      return { data, sha256: sha(data), bytes: data.length };
    },
  };
}

const manifest = Buffer.from('{"manifest":true}');
const plan = Buffer.from("DXF");
const pkg: PackageRow = {
  package_id: PACKAGE_ID,
  visit_id: VISIT_ID,
  deal_id: "fixture-deal-0001",
  revision: 1,
  status: "checks_queued",
  manifest: {},
  manifest_sha256: sha(manifest),
  capture_record: {},
};
const planPath = "Original Exports/floor-1/c/plan.dxf";
const files: FileRow[] = [
  {
    path: planPath,
    role: "plan_dxf",
    capture_id: "c",
    area_key: "floor-1",
    sha256: sha(plan),
    bytes: plan.length,
    status: "verified",
    // Verified on the second upload attempt: the blob name is not <packageId>/<path>.
    blob_name: `${PACKAGE_ID}.retry-2/${planPath}`,
  },
];
const manifestBlob = `${PACKAGE_ID}/Source Register/${VISIT_ID}/manifest.json`;

describe("loadSealedFiles", () => {
  it("reads each file from its registered blob name and adds the manifest at its layout path", async () => {
    const originals = reader(
      new Map([
        [`${PACKAGE_ID}.retry-2/${planPath}`, plan],
        [manifestBlob, manifest],
        // A stale first attempt that must never be read.
        [`${PACKAGE_ID}/${planPath}`, Buffer.from("OLD")],
      ]),
    );
    const map = await loadSealedFiles(originals, pkg, files);
    assert.deepEqual(
      [...map.keys()].sort(),
      [planPath, `Source Register/${VISIT_ID}/manifest.json`].sort(),
    );
    assert.deepEqual(Buffer.from(map.get(planPath) ?? []), plan);
    assert.ok(!originals.reads.includes(`${PACKAGE_ID}/${planPath}`));
  });

  it("fails with an integrity error when a blob no longer matches its SHA-256", async () => {
    const originals = reader(
      new Map([
        [`${PACKAGE_ID}.retry-2/${planPath}`, Buffer.from("DXG")],
        [manifestBlob, manifest],
      ]),
    );
    await assert.rejects(loadSealedFiles(originals, pkg, files), (error: unknown) => {
      assert.ok(error instanceof IntegrityError);
      assert.equal(error.auditAction, "package.integrity_error");
      assert.equal(error.details.reason, "sha256_mismatch");
      assert.equal(error.details.path, planPath);
      return true;
    });
  });

  it("fails with an integrity error for a missing blob, a bigger blob or a changed manifest", async () => {
    await assert.rejects(
      loadSealedFiles(reader(new Map([[manifestBlob, manifest]])), pkg, files),
      (e: unknown) => e instanceof IntegrityError && e.details.reason === "missing",
    );
    await assert.rejects(
      loadSealedFiles(
        reader(
          new Map([
            [`${PACKAGE_ID}.retry-2/${planPath}`, Buffer.from("DXFX")],
            [manifestBlob, manifest],
          ]),
        ),
        pkg,
        files,
      ),
      (e: unknown) => e instanceof IntegrityError && e.details.reason === "bytes_mismatch",
    );
    await assert.rejects(
      loadSealedFiles(
        reader(
          new Map([
            [`${PACKAGE_ID}.retry-2/${planPath}`, plan],
            [manifestBlob, Buffer.from("{}")],
          ]),
        ),
        pkg,
        files,
      ),
      (e: unknown) => e instanceof IntegrityError && e.details.reason === "sha256_mismatch",
    );
  });

  it("refuses files that are not verified", async () => {
    const pending = files.map((file) => ({ ...file, status: "pending" }));
    await assert.rejects(
      loadSealedFiles(reader(new Map()), pkg, pending),
      (e: unknown) => e instanceof IntegrityError && e.details.reason === "not_verified",
    );
  });
});

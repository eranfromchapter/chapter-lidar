// Manifest 1.1.0 (phone-field 10, phone-package 10.1): readers accept 1.0.0 and 1.1.0. 1.1.0
// adds photo.directionSource and retires spatial_report_pdf: a 1.0.0 package from an older app
// may list the phone's spatial report, a 1.1.0 package never does.

import assert from "node:assert/strict";
import { join } from "node:path";
import { describe, it } from "node:test";
import {
  RETIRED_ROLES,
  ROLES,
  formatErrors,
  isRetiredRole,
  validateManifest,
  type PackageManifest,
} from "../src/index.js";
import { examplesDir, readJson } from "./paths.js";

const v100 = readJson(
  join(examplesDir, "manifest", "valid", "two-captures.json"),
) as PackageManifest;
const v110 = readJson(
  join(examplesDir, "manifest", "valid", "photo-direction-source.json"),
) as PackageManifest;
const legacy = readJson(
  join(examplesDir, "manifest", "valid", "legacy-spatial-report-1.0.0.json"),
) as PackageManifest;

function changed(
  manifest: PackageManifest,
  change: (copy: PackageManifest) => void,
): PackageManifest {
  const copy = structuredClone(manifest);
  change(copy);
  return copy;
}

function assertValid(manifest: unknown): void {
  const result = validateManifest(manifest);
  assert.ok(result.ok, result.ok ? "" : formatErrors(result.errors));
}

/** Fails unless the manifest is rejected with an error at each pointer (and possibly at the root). */
function assertRejectedAt(manifest: unknown, pointers: string[]): void {
  const result = validateManifest(manifest);
  assert.equal(result.ok, false, "expected the manifest to fail the schema");
  const at = new Set(result.errors.map((error) => error.instancePath));
  for (const pointer of pointers) {
    assert.ok(at.has(pointer), `no error at ${pointer}:\n${formatErrors(result.errors)}`);
  }
  const stray = [...at].filter((pointer) => pointer !== "" && !pointers.includes(pointer));
  assert.deepEqual(stray, [], formatErrors(result.errors));
}

function indexOfRole(manifest: PackageManifest, role: string): number {
  const index = manifest.files.findIndex((file) => file.role === role);
  assert.ok(index >= 0, `no ${role} file`);
  return index;
}

describe("manifest schema versions", () => {
  it("accepts 1.0.0 and 1.1.0", () => {
    assert.equal(v100.schemaVersion, "1.0.0");
    assert.equal(v110.schemaVersion, "1.1.0");
    assertValid(v100);
    assertValid(v110);
  });

  it("accepts a 1.0.0 manifest relabelled 1.1.0 when it lists no retired role", () => {
    assertValid(changed(v100, (manifest) => (manifest.schemaVersion = "1.1.0")));
  });

  it("rejects any other version", () => {
    for (const version of ["1.3.0", "2.0.0", "1.1", ""]) {
      assertRejectedAt({ ...v110, schemaVersion: version }, ["/schemaVersion"]);
    }
  });
});

describe("retired role spatial_report_pdf", () => {
  it("is the only retired role, and a role of the closed list", () => {
    assert.deepEqual([...RETIRED_ROLES], ["spatial_report_pdf"]);
    for (const role of ROLES) {
      assert.equal(isRetiredRole(role), role === "spatial_report_pdf", role);
    }
  });

  it("is valid in a 1.0.0 manifest (a package sealed by an app before v2)", () => {
    assert.equal(legacy.schemaVersion, "1.0.0");
    indexOfRole(legacy, "spatial_report_pdf");
    assertValid(legacy);
  });

  it("is refused in a 1.1.0 manifest, at the file's role", () => {
    const index = indexOfRole(legacy, "spatial_report_pdf");
    assertRejectedAt(
      changed(legacy, (manifest) => (manifest.schemaVersion = "1.1.0")),
      [`/files/${index}/role`],
    );
  });
});

describe("photo.directionSource", () => {
  it("is compass or manual in 1.1.0", () => {
    const sources = v110.files.flatMap((file) => (file.photo ? [file.photo.directionSource] : []));
    assert.deepEqual(sources, ["compass", "manual"]);
  });

  it("is optional in 1.1.0", () => {
    assertValid(
      changed(v110, (manifest) => {
        for (const file of manifest.files) {
          delete file.photo?.directionSource;
        }
      }),
    );
  });

  it("rejects other values and types at the field", () => {
    const index = indexOfRole(v110, "photo");
    for (const value of ["gps", true, "Compass", ""]) {
      // The file entry's photo rule (role photo needs a valid photo) also reports the entry.
      assertRejectedAt(
        changed(v110, (manifest) => {
          (manifest.files[index]?.photo as unknown as Record<string, unknown>)["directionSource"] =
            value;
        }),
        [`/files/${index}/photo/directionSource`, `/files/${index}`],
      );
    }
  });

  it("is not carried by a 1.0.0 manifest", () => {
    const index = indexOfRole(v110, "photo");
    assertRejectedAt(
      changed(v110, (manifest) => (manifest.schemaVersion = "1.0.0")),
      [`/files/${index}/photo/directionSource`, `/files/${index + 1}/photo/directionSource`],
    );
  });
});

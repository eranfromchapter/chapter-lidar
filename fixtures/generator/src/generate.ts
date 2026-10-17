// Writes every fixture under an output folder. Deterministic: same inputs, same bytes.

import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { buildBrokenFixtures } from "./broken.js";
import { jsonBytes } from "./json.js";
import { buildManifest, buildPackage, type PackageFile } from "./package.js";
import { fixtureSpecs } from "./shapes.js";

export const GENERATED_FORMAT_VERSION = "1.0.0";

function write(path: string, bytes: Uint8Array): void {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, bytes);
}

async function writePackageFiles(
  packageRoot: string,
  files: readonly PackageFile[],
  visitId: string,
  packageId: string,
  manifestPath: string,
): Promise<void> {
  for (const file of files) {
    write(join(packageRoot, file.path), file.bytes);
  }
  write(join(packageRoot, manifestPath), await jsonBytes(buildManifest(visitId, packageId, files)));
}

/** Generates all good and broken fixtures into `outDir`. Existing files are overwritten. */
export async function generateAll(outDir: string): Promise<void> {
  const index: {
    generatedFormatVersion: string;
    fixtures: unknown[];
    broken: unknown[];
  } = { generatedFormatVersion: GENERATED_FORMAT_VERSION, fixtures: [], broken: [] };
  let boxRoom: Awaited<ReturnType<typeof buildPackage>> | undefined;

  for (const spec of fixtureSpecs()) {
    const pkg = await buildPackage(spec);
    if (spec.name === "box-room") {
      boxRoom = pkg;
    }
    const root = join(outDir, spec.name);
    write(join(root, "truth.json"), await jsonBytes(pkg.truth));
    await writePackageFiles(
      join(root, "package"),
      pkg.files,
      pkg.visitId,
      pkg.packageId,
      pkg.manifestPath,
    );
    index.fixtures.push({
      name: spec.name,
      description: spec.description,
      truth: `${spec.name}/truth.json`,
      packageRoot: `${spec.name}/package`,
      manifest: `${spec.name}/package/${pkg.manifestPath}`,
      visitId: pkg.visitId,
    });
  }

  if (boxRoom === undefined) {
    throw new Error("box-room fixture missing");
  }
  for (const broken of await buildBrokenFixtures(boxRoom)) {
    const root = join(outDir, "broken", broken.defectId);
    write(join(root, "defect.json"), await jsonBytes(broken.defect));
    await writePackageFiles(
      join(root, "package"),
      broken.files,
      broken.visitId,
      broken.packageId,
      broken.manifestPath,
    );
    index.broken.push({
      defectId: broken.defectId,
      title: broken.defect.title,
      baseFixture: broken.defect.baseFixture,
      defect: `broken/${broken.defectId}/defect.json`,
      packageRoot: `broken/${broken.defectId}/package`,
      manifest: `broken/${broken.defectId}/package/${broken.manifestPath}`,
    });
  }
  write(join(outDir, "index.json"), await jsonBytes(index));
}

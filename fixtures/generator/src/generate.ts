// Writes every fixture under an output folder. Deterministic: same inputs, same bytes.

import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { buildBrokenFixtures } from "./broken.js";
import { jsonBytes } from "./json.js";
import { buildManifest, buildPackage, type GeneratedPackage, type PackageFile } from "./package.js";
import { sample424 } from "./sample424.js";
import { fixtureSpecs, legacySpecs } from "./shapes.js";
import type { FixtureSpec } from "./spec.js";
import { buildWalkthrough, WALKTHROUGH_NAME } from "./walkthrough.js";

/**
 * Version of index.json. 1.1.0 adds `legacy` (packages sealed by an app before v2) and
 * `samples` (design samples that are not plain good fixtures).
 */
export const GENERATED_FORMAT_VERSION = "1.1.0";

/** The design samples, in index order. */
export function sampleSpecs(): FixtureSpec[] {
  return [sample424()];
}

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
  manifestVersion: GeneratedPackage["manifestVersion"] = "1.1.0",
): Promise<void> {
  for (const file of files) {
    write(join(packageRoot, file.path), file.bytes);
  }
  write(
    join(packageRoot, manifestPath),
    await jsonBytes(buildManifest(visitId, packageId, files, manifestVersion)),
  );
}

/** Writes one fixture's truth and package and returns its index entry. */
async function writeFixture(
  outDir: string,
  spec: FixtureSpec,
): Promise<GeneratedPackage & { entry: Record<string, unknown> }> {
  const pkg = await buildPackage(spec);
  const root = join(outDir, spec.name);
  write(join(root, "truth.json"), await jsonBytes(pkg.truth));
  await writePackageFiles(
    join(root, "package"),
    pkg.files,
    pkg.visitId,
    pkg.packageId,
    pkg.manifestPath,
    pkg.manifestVersion,
  );
  const entry = {
    name: spec.name,
    description: spec.description,
    ...(spec.legacy === true ? { legacy: true } : {}),
    truth: `${spec.name}/truth.json`,
    packageRoot: `${spec.name}/package`,
    manifest: `${spec.name}/package/${pkg.manifestPath}`,
    visitId: pkg.visitId,
  };
  return { ...pkg, entry };
}

/**
 * Generates every fixture into `outDir`. Existing files are overwritten. index.json lists the
 * good fixtures (complete packages the station accepts as ready), the broken ones (each one
 * defect), the legacy packages and the design samples.
 */
export async function generateAll(outDir: string): Promise<void> {
  const index: {
    generatedFormatVersion: string;
    fixtures: unknown[];
    broken: unknown[];
    legacy: unknown[];
    samples: unknown[];
  } = {
    generatedFormatVersion: GENERATED_FORMAT_VERSION,
    fixtures: [],
    broken: [],
    legacy: [],
    samples: [],
  };
  let boxRoom: GeneratedPackage | undefined;

  for (const spec of fixtureSpecs()) {
    const pkg = await writeFixture(outDir, spec);
    if (spec.name === "box-room") {
      boxRoom = pkg;
    }
    index.fixtures.push(pkg.entry);
  }
  for (const spec of legacySpecs()) {
    index.legacy.push((await writeFixture(outDir, spec)).entry);
  }
  for (const spec of sampleSpecs()) {
    index.samples.push((await writeFixture(outDir, spec)).entry);
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

  // RoomPlan-only fixtures: a raw RoomPlan export and its ground truth, with no package around
  // it. Not listed in index.json, whose readers expect complete packages.
  const walkthrough = buildWalkthrough();
  const walkthroughRoot = join(outDir, "roomplan-only", WALKTHROUGH_NAME);
  write(join(walkthroughRoot, "roomplan.json"), await jsonBytes(walkthrough.roomPlan));
  write(join(walkthroughRoot, "expected.json"), await jsonBytes(walkthrough.expected));
}

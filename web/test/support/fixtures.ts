// Fixture verdicts for the package detail tests:
// - the contract's verdict example with the matching manifest and capture record examples;
// - the verdicts the station checks produce for every generated fixture package.

import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { CaptureRecord, PackageManifest, Verdict } from "@chapter/capture-contract";
import { runChecks } from "@chapter/station-checks";
import { loadPackageFromDirectory } from "@chapter/station-checks/node";
import type { HubProject, StationPackage } from "@/lib/station-types";

/** Repository root, set by vitest.config.ts (import.meta.url is not a file URL under jsdom). */
export const REPO_ROOT = process.env.CHAPTER_REPO_ROOT ?? "";
if (REPO_ROOT.length === 0) {
  throw new Error("CHAPTER_REPO_ROOT is not set; run the tests through vitest.config.ts");
}

function readJson<T>(...parts: string[]): T {
  return JSON.parse(readFileSync(join(REPO_ROOT, ...parts), "utf8")) as T;
}

export interface FixtureCase {
  readonly name: string;
  readonly project: HubProject;
  readonly pkg: StationPackage;
  readonly verdict: Verdict;
}

/** The station's view of a sealed package with a verdict. */
export function sealedPackage(
  manifest: PackageManifest,
  captureRecord: CaptureRecord | undefined,
  dealId: string,
  verdict: Verdict,
): StationPackage {
  return {
    packageId: manifest.packageId,
    visitId: manifest.visitId,
    dealId,
    revision: manifest.revision,
    status: "verdict_ready",
    createdAt: manifest.sealedAt,
    sealedAt: manifest.sealedAt,
    files: manifest.files.map((file) => ({
      path: file.path,
      role: file.role,
      ...(file.captureId === undefined ? {} : { captureId: file.captureId }),
      ...(file.areaKey === undefined ? {} : { areaKey: file.areaKey }),
      sha256: file.sha256,
      bytes: file.bytes,
      status: "verified" as const,
      checkedAt: manifest.sealedAt,
    })),
    manifest,
    ...(captureRecord === undefined ? {} : { captureRecord }),
    verdict: {
      verdictId: verdict.verdictId,
      outcome: verdict.outcome,
      evaluatedAt: verdict.evaluatedAt,
    },
  };
}

/** contract/examples/verdict/valid/limited.json with its manifest and capture record. */
export function contractExampleCase(): FixtureCase {
  const verdict = readJson<Verdict>("contract/examples/verdict/valid/limited.json");
  const manifest = readJson<PackageManifest>("contract/examples/manifest/valid/two-captures.json");
  const record = readJson<CaptureRecord>(
    "contract/examples/capture-record/valid/two-captures.json",
  );
  const project: HubProject = {
    dealId: record.hub.dealId,
    address: { formatted: record.address.formatted },
  };
  return {
    name: "contract example (limited)",
    project,
    pkg: sealedPackage(manifest, record, project.dealId, verdict),
    verdict,
  };
}

interface FixtureIndex {
  fixtures: { name: string; packageRoot: string }[];
  broken: { defectId: string; baseFixture: string; packageRoot: string; defect: string }[];
}

interface Defect {
  details?: { hubAddress?: string };
}

/** Station verdicts for every generated fixture package (good and broken). */
export function generatedFixtureCases(): FixtureCase[] {
  const index = readJson<FixtureIndex>("fixtures/generated/index.json");
  const root = join(REPO_ROOT, "fixtures/generated");
  const addresses = new Map<string, string>();
  const cases: FixtureCase[] = [];

  const add = (name: string, packageRoot: string, hubAddress: string | undefined) => {
    const loaded = loadPackageFromDirectory(join(root, packageRoot));
    const record = loaded.captureRecord;
    const address = hubAddress ?? record?.address.formatted;
    if (address === undefined) {
      throw new Error(`fixture ${name} has no HUB address`);
    }
    const verdict = runChecks(loaded, address);
    const project: HubProject = {
      dealId: record?.hub.dealId ?? `fixture-${name}`,
      address: { formatted: address },
    };
    cases.push({
      name,
      project,
      pkg: sealedPackage(loaded.manifest, record, project.dealId, verdict),
      verdict,
    });
    if (record !== undefined) {
      addresses.set(name, record.address.formatted);
    }
  };

  for (const fixture of index.fixtures) {
    add(fixture.name, fixture.packageRoot, undefined);
  }
  for (const broken of index.broken) {
    const defect = readJson<Defect>("fixtures/generated", broken.defect);
    add(
      `broken/${broken.defectId}`,
      broken.packageRoot,
      defect.details?.hubAddress ?? addresses.get(broken.baseFixture),
    );
  }
  return cases;
}

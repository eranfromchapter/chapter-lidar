// Station data for the review screen's tests and its local end-to-end station:
// - packages built from the generated fixture packages (fixtures/generated) and the contract's
//   examples, in the station API 1.1.0 shapes (Package, PackageSummary) with the station's
//   read-model fields (totals, captures, checks, publication, report, HUB file states);
// - verdicts the station checks produce for every generated fixture package, and the recorded
//   verdicts of the design sample (fixtures/report/424-west-end).
//
// The station-contract test validates what the fake station builds from here against
// contract/openapi/station.yaml, so these builders cannot drift from the API.

import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import type {
  CaptureRecord,
  FieldControls,
  PackageManifest,
  Role,
  Verdict,
} from "@chapter/capture-contract";
import { runChecks } from "@chapter/station-checks";
import { loadPackageFromDirectory } from "@chapter/station-checks/node";
import type {
  HubFileState,
  HubProject,
  NextRevisionNotice,
  PackageFile,
  PackageStatus,
  PackageSummary,
  PublicationSummary,
  ReportSummary,
  StationPackage,
} from "@/lib/station-types";

function repoRoot(): string {
  const fromEnv = process.env.CHAPTER_REPO_ROOT;
  if (fromEnv !== undefined && fromEnv.length > 0) {
    return fromEnv;
  }
  // Outside vitest (the end-to-end station runs under tsx), this file's own location.
  return resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
}

/** Repository root (CHAPTER_REPO_ROOT under vitest, where import.meta.url is not a file URL). */
export const REPO_ROOT = repoRoot();

export function readJson<T>(...parts: string[]): T {
  return JSON.parse(readFileSync(join(REPO_ROOT, ...parts), "utf8")) as T;
}

export function sha256(bytes: Uint8Array): string {
  return createHash("sha256").update(bytes).digest("hex");
}

/** A fixture package as files on disk. */
export interface FixturePackage {
  readonly manifestPath: string;
  readonly manifest: PackageManifest;
  readonly captureRecord?: CaptureRecord;
  readonly fieldControls?: FieldControls;
  readonly files: ReadonlyMap<string, Uint8Array>;
}

/** A package under fixtures/generated (packageRoot as fixtures/generated/index.json names it). */
export function loadFixture(packageRoot: string): FixturePackage {
  const loaded = loadPackageFromDirectory(join(REPO_ROOT, "fixtures/generated", packageRoot));
  return {
    manifestPath: loaded.manifestPath,
    manifest: loaded.manifest,
    ...(loaded.captureRecord === undefined ? {} : { captureRecord: loaded.captureRecord }),
    ...(loaded.fieldControls === undefined ? {} : { fieldControls: loaded.fieldControls }),
    files: loaded.files,
  };
}

/** The station checks' verdict of a fixture package against a HUB address. */
export function checkFixture(fixture: FixturePackage, hubAddress: string): Verdict {
  return runChecks(
    {
      manifestPath: fixture.manifestPath,
      manifest: fixture.manifest,
      ...(fixture.captureRecord === undefined ? {} : { captureRecord: fixture.captureRecord }),
      ...(fixture.fieldControls === undefined ? {} : { fieldControls: fixture.fieldControls }),
      files: fixture.files,
    },
    hubAddress,
  );
}

/** Roles the station's HUB publisher uploads up to 45 MiB (station/hub/src/plan.ts). */
const HUB_UPLOAD_ROLES: readonly Role[] = [
  "plan_dxf",
  "rooms_csv",
  "plan_pdf",
  "spatial_report_pdf",
  "plan_png",
];
const MAX_HUB_UPLOAD_BYTES = 45 * 1024 * 1024;

/** Where the publisher put a file of this role and size. */
export function publishedState(role: Role, bytes: number): HubFileState {
  if (!HUB_UPLOAD_ROLES.includes(role)) {
    return { state: "linked", reason: "not_published" };
  }
  return bytes > MAX_HUB_UPLOAD_BYTES
    ? { state: "linked", reason: "too_large" }
    : { state: "uploaded" };
}

export interface PackageOptions {
  readonly dealId: string;
  /** When the station registered the package (upload session opened). */
  readonly createdAt: string;
  readonly createdBy?: string;
  /** Overrides of the manifest's ids (several revisions built from one fixture). */
  readonly packageId?: string;
  readonly revision?: number;
  readonly supersedesPackageId?: string;
  /** Default: verdict_ready with a verdict, else checks_queued. */
  readonly status?: PackageStatus;
  readonly verdict?: Verdict;
  /** Uploading: the share of the declared bytes verified so far (files in manifest order). */
  readonly uploaded?: number;
  readonly checksStartedAt?: string;
  readonly checksFinishedAt?: string;
  readonly publication?: PublicationSummary["status"];
  readonly publishedAt?: string;
  readonly report?: ReportSummary;
  readonly hubDealUrl?: string;
  readonly reviewBaseUrl?: string;
  readonly nextRevision?: NextRevisionNotice;
  readonly updatedAt?: string;
  /** Manifest bytes, for the manifest file's size and fingerprint. */
  readonly manifestBytes?: Uint8Array;
}

function later(...times: (string | undefined)[]): string {
  return times
    .filter((time): time is string => time !== undefined)
    .reduce((a, b) => (Date.parse(a) >= Date.parse(b) ? a : b));
}

/** Captures of a package before its capture record: first appearance in path order. */
function capturesFromPaths(files: readonly PackageFile[]): StationPackage["captures"] {
  const seen = new Map<string, string>();
  for (const file of [...files].sort((a, b) => (a.path < b.path ? -1 : 1))) {
    if (file.captureId !== undefined && file.areaKey !== undefined && !seen.has(file.captureId)) {
      seen.set(file.captureId, file.areaKey);
    }
  }
  return [...seen.entries()].map(([captureId, areaKey]) => ({ captureId, areaKey }));
}

/** The station's view of a fixture package (OpenAPI Package, 1.1.0). */
export function stationPackage(fixture: FixturePackage, options: PackageOptions): StationPackage {
  const manifest: PackageManifest = {
    ...fixture.manifest,
    ...(options.packageId === undefined ? {} : { packageId: options.packageId }),
    ...(options.revision === undefined ? {} : { revision: options.revision }),
    ...(options.supersedesPackageId === undefined
      ? {}
      : { supersedesPackageId: options.supersedesPackageId }),
  };
  const verdict = options.verdict;
  const status: PackageStatus =
    options.status ?? (verdict === undefined ? "checks_queued" : "verdict_ready");
  const sealed = status !== "uploading";
  const published = sealed && options.publication === "published";
  const record = sealed ? fixture.captureRecord : undefined;

  const declared = manifest.files;
  const totalBytes = declared.reduce((sum, file) => sum + file.bytes, 0);
  const verifiedBytesTarget = sealed
    ? totalBytes
    : Math.floor(totalBytes * (options.uploaded ?? 0));
  let verifiedSoFar = 0;
  const files: PackageFile[] = declared.map((entry) => {
    const verified = sealed || verifiedSoFar + entry.bytes <= verifiedBytesTarget;
    if (verified) {
      verifiedSoFar += entry.bytes;
    }
    return {
      path: entry.path,
      role: entry.role,
      ...(entry.captureId === undefined ? {} : { captureId: entry.captureId }),
      ...(entry.areaKey === undefined ? {} : { areaKey: entry.areaKey }),
      sha256: entry.sha256,
      bytes: entry.bytes,
      status: verified ? ("verified" as const) : ("pending" as const),
      ...(verified ? { checkedAt: sealed ? manifest.sealedAt : options.createdAt } : {}),
      ...(sealed ? { generator: entry.generator, generatorVersion: entry.generatorVersion } : {}),
      ...(published ? { hub: publishedState(entry.role, entry.bytes) } : {}),
    };
  });
  const verifiedFiles = files.filter((file) => file.status === "verified");

  const manifestBytes =
    options.manifestBytes ?? fixture.files.get(fixture.manifestPath) ?? new Uint8Array();
  const publication: PublicationSummary | undefined =
    sealed && options.publication !== undefined
      ? {
          status: options.publication,
          ...(options.publication === "published" && options.publishedAt !== undefined
            ? { publishedAt: options.publishedAt }
            : {}),
          hubFolder: `Capture/${manifest.visitId}/r${manifest.revision}`,
        }
      : undefined;

  let checks: StationPackage["checks"];
  if (sealed) {
    switch (status) {
      case "checks_queued":
        checks = { status: "queued" };
        break;
      case "checking":
        checks = {
          status: "running",
          ...(options.checksStartedAt === undefined ? {} : { startedAt: options.checksStartedAt }),
        };
        break;
      case "check_error":
        checks = {
          status: "failed",
          ...(options.checksStartedAt === undefined ? {} : { startedAt: options.checksStartedAt }),
          ...(options.checksFinishedAt === undefined
            ? {}
            : { finishedAt: options.checksFinishedAt }),
        };
        break;
      default:
        checks = {
          status: "completed",
          ...(options.checksStartedAt === undefined ? {} : { startedAt: options.checksStartedAt }),
          finishedAt: options.checksFinishedAt ?? verdict?.evaluatedAt ?? manifest.sealedAt,
          rules: verdict?.checks.length ?? 0,
        };
    }
  }

  const captures = record
    ? record.captures.map((capture) => ({
        captureId: capture.captureId,
        areaKey: capture.areaKey,
        label: capture.label,
        mode: capture.mode,
      }))
    : capturesFromPaths(files);

  const pkg: StationPackage = {
    packageId: manifest.packageId,
    visitId: manifest.visitId,
    dealId: options.dealId,
    revision: manifest.revision,
    ...(manifest.supersedesPackageId === undefined
      ? {}
      : { supersedesPackageId: manifest.supersedesPackageId }),
    status,
    createdAt: options.createdAt,
    ...(sealed ? { sealedAt: manifest.sealedAt } : {}),
    updatedAt:
      options.updatedAt ??
      later(
        options.createdAt,
        sealed ? manifest.sealedAt : undefined,
        verdict?.evaluatedAt,
        options.publishedAt,
      ),
    ...(options.createdBy === undefined ? {} : { createdBy: { name: options.createdBy } }),
    ...(record === undefined
      ? {}
      : { visitedAt: record.visitedAt, operatorName: record.operator.name }),
    captures,
    totals: {
      files: files.length,
      bytes: totalBytes,
      filesVerified: verifiedFiles.length,
      bytesVerified: verifiedFiles.reduce((sum, file) => sum + file.bytes, 0),
    },
    ...(checks === undefined ? {} : { checks }),
    ...(publication === undefined ? {} : { publication }),
    ...(verdict === undefined ? {} : { report: options.report ?? { status: "pending" as const } }),
    links: {
      review: `${options.reviewBaseUrl ?? "https://review.test"}/packages/${manifest.packageId}`,
      ...(options.hubDealUrl === undefined ? {} : { hub: options.hubDealUrl }),
    },
    ...(verdict === undefined
      ? {}
      : {
          verdict: {
            verdictId: verdict.verdictId,
            outcome: verdict.outcome,
            evaluatedAt: verdict.evaluatedAt,
          },
        }),
    files,
    ...(sealed ? { manifest } : {}),
    ...(sealed
      ? {
          manifestFile: {
            path: fixture.manifestPath,
            sha256: sha256(manifestBytes),
            bytes: manifestBytes.byteLength,
            ...(published ? { hub: { state: "uploaded" as const } } : {}),
          },
        }
      : {}),
    ...(record === undefined ? {} : { captureRecord: record }),
    ...(sealed && fixture.fieldControls !== undefined
      ? { fieldControls: fixture.fieldControls }
      : {}),
    ...(options.nextRevision === undefined ? {} : { nextRevision: options.nextRevision }),
  };
  return pkg;
}

/** The PackageSummary of a package (the fields of Package without files and documents). */
export function summaryOf(pkg: StationPackage): PackageSummary {
  const {
    files: _files,
    manifest: _manifest,
    manifestFile: _manifestFile,
    captureRecord: _captureRecord,
    fieldControls: _fieldControls,
    nextRevision: _nextRevision,
    ...summary
  } = pkg;
  return summary;
}

/** A verdict re-issued for another package or revision of the same files (test data). */
export function verdictFor(
  verdict: Verdict,
  ids: { verdictId: string; packageId: string; revision: number; evaluatedAt?: string },
): Verdict {
  return {
    ...verdict,
    verdictId: ids.verdictId,
    packageId: ids.packageId,
    revision: ids.revision,
    ...(ids.evaluatedAt === undefined ? {} : { evaluatedAt: ids.evaluatedAt }),
  };
}

// ---------------------------------------------------------------------------------------------
// Cases used by the package detail and access tests

export interface FixtureCase {
  readonly name: string;
  readonly project: HubProject;
  readonly pkg: StationPackage;
  readonly verdict: Verdict;
}

interface ContractManifestFixture extends FixturePackage {
  readonly manifestPath: string;
}

/** contract/examples: the two-capture manifest, capture record and field controls. */
export function contractExampleFixture(): ContractManifestFixture {
  const manifest = readJson<PackageManifest>("contract/examples/manifest/valid/two-captures.json");
  const record = readJson<CaptureRecord>(
    "contract/examples/capture-record/valid/two-captures.json",
  );
  const controls = readJson<FieldControls>(
    "contract/examples/field-controls/valid/two-captures.json",
  );
  const bytes = readFileSync(join(REPO_ROOT, "contract/examples/manifest/valid/two-captures.json"));
  const manifestPath = `Source Register/${manifest.visitId}/manifest.json`;
  return {
    manifestPath,
    manifest,
    captureRecord: record,
    fieldControls: controls,
    files: new Map([[manifestPath, new Uint8Array(bytes)]]),
  };
}

/** contract/examples/verdict/valid/limited.json with its manifest and capture record. */
export function contractExampleCase(): FixtureCase {
  const verdict = readJson<Verdict>("contract/examples/verdict/valid/limited.json");
  const fixture = contractExampleFixture();
  const record = fixture.captureRecord as CaptureRecord;
  const project: HubProject = {
    dealId: record.hub.dealId,
    address: { formatted: record.address.formatted },
  };
  return {
    name: "contract example (limited)",
    project,
    pkg: stationPackage(fixture, {
      dealId: project.dealId,
      createdAt: fixture.manifest.sealedAt,
      verdict,
      publication: "published",
      publishedAt: verdict.evaluatedAt,
    }),
    verdict,
  };
}

interface FixtureIndex {
  fixtures: { name: string; packageRoot: string }[];
  broken: { defectId: string; baseFixture: string; packageRoot: string; defect: string }[];
  legacy?: { name: string; packageRoot: string }[];
  samples?: { name: string; packageRoot: string }[];
}

interface Defect {
  details?: { hubAddress?: string };
}

export function fixtureIndex(): FixtureIndex {
  return readJson<FixtureIndex>("fixtures/generated/index.json");
}

/** Station verdicts for every generated fixture package (good, broken and legacy). */
export function generatedFixtureCases(): FixtureCase[] {
  const index = fixtureIndex();
  const addresses = new Map<string, string>();
  const cases: FixtureCase[] = [];

  const add = (name: string, packageRoot: string, hubAddress: string | undefined) => {
    const fixture = loadFixture(packageRoot);
    const record = fixture.captureRecord;
    const address = hubAddress ?? record?.address.formatted;
    if (address === undefined) {
      throw new Error(`fixture ${name} has no HUB address`);
    }
    const verdict = checkFixture(fixture, address);
    const project: HubProject = {
      dealId: record?.hub.dealId ?? `fixture-${name}`,
      address: { formatted: address },
    };
    cases.push({
      name,
      project,
      pkg: stationPackage(fixture, {
        dealId: project.dealId,
        createdAt: fixture.manifest.sealedAt,
        verdict,
      }),
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
  for (const legacy of index.legacy ?? []) {
    add(`legacy/${legacy.name}`, legacy.packageRoot, undefined);
  }
  return cases;
}

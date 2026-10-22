// Package and project data shared by the project and package pages: the project title with its
// fallbacks (web-review §5.5), newer revisions of a visit, and the package states the pages
// word differently from the station's status.

import type { Verdict } from "@chapter/capture-contract";
import { StationError, type StationClient } from "./station";
import type { CaptureRecord, HubProject, PackageSummary, StationPackage } from "./station-types";

/** What the header of a project or package page shows about the project. */
export interface ProjectHeading {
  /** HUB project name, else its address, else the capture record's, else "HUB deal {dealId}". */
  readonly title: string;
  /** The address, shown in the meta line only when the title is a project name. */
  readonly address?: string;
  readonly projectManager?: { name: string };
  /** False when the HUB no longer knows the deal (or did not answer) and a fallback is used. */
  readonly fromHub: boolean;
}

export function headingFromProject(project: HubProject): ProjectHeading {
  return {
    title: project.projectName ?? project.address.formatted,
    ...(project.projectName === undefined ? {} : { address: project.address.formatted }),
    ...(project.projectManager === undefined
      ? {}
      : { projectManager: { name: project.projectManager.name } }),
    fromHub: true,
  };
}

export function headingFromRecord(
  dealId: string,
  record: CaptureRecord | undefined,
): ProjectHeading {
  if (record === undefined) {
    return { title: `HUB deal ${dealId}`, fromHub: false };
  }
  const name = record.hub.projectName;
  return {
    title: name ?? record.address.formatted,
    ...(name === undefined ? {} : { address: record.address.formatted }),
    fromHub: false,
  };
}

/** True for the station errors after which the page falls back to the capture record. */
export function hubCannotAnswer(error: unknown): boolean {
  return error instanceof StationError && (error.status === 404 || error.status === 503);
}

/**
 * The project heading: from the HUB project when the station knows it, else from `fallback`
 * (called only when getProject answers 404 or 503). Other errors propagate.
 */
export async function loadHeading(
  station: StationClient,
  dealId: string,
  fallback: () => Promise<CaptureRecord | undefined>,
): Promise<ProjectHeading> {
  try {
    return headingFromProject(await station.getProject(dealId));
  } catch (error) {
    if (!hubCannotAnswer(error)) {
      throw error;
    }
    return headingFromRecord(dealId, await fallback());
  }
}

/** The verdict once the package reports verdict_ready; null while checks are pending. */
export async function loadVerdict(
  station: StationClient,
  pkg: Pick<StationPackage, "packageId" | "status">,
): Promise<Verdict | null> {
  if (pkg.status !== "verdict_ready") {
    return null;
  }
  return station.getVerdict(pkg.packageId);
}

/** Packages of the same visit with a higher revision, newest first. */
export function newerRevisions(
  packages: readonly PackageSummary[],
  pkg: Pick<PackageSummary, "visitId" | "revision">,
): PackageSummary[] {
  return packages
    .filter((item) => item.visitId === pkg.visitId && item.revision > pkg.revision)
    .sort((a, b) => b.revision - a.revision);
}

/**
 * An upload the phone gave up on: still "uploading" at the station while a newer revision of the
 * same visit exists (the phone re-sealed after "Upload stopped"). Its newest successor, or
 * undefined when the package is not such an upload.
 */
export function replacedBy(
  packages: readonly PackageSummary[],
  pkg: Pick<PackageSummary, "visitId" | "revision" | "status">,
): PackageSummary | undefined {
  if (pkg.status !== "uploading") {
    return undefined;
  }
  return newerRevisions(packages, pkg)[0];
}

/** "replaced by revision {n}", the second half of the upload-stopped wording. */
export function replacedByText(successor: Pick<PackageSummary, "revision">): string {
  return `replaced by revision ${successor.revision}`;
}

/**
 * The one wording of an upload the phone replaced, on every page that lists or shows it:
 * "upload stopped · replaced by revision {n}" (the package page's status card and station card
 * title it "Upload stopped").
 */
export function uploadStoppedText(successor: Pick<PackageSummary, "revision">): string {
  return `upload stopped · ${replacedByText(successor)}`;
}

/** The newest package of each visit, newest visit first (packages come newest first). */
export function newestPerVisit(packages: readonly PackageSummary[]): PackageSummary[] {
  const seen = new Map<string, PackageSummary>();
  for (const pkg of packages) {
    const known = seen.get(pkg.visitId);
    if (known === undefined || pkg.revision > known.revision) {
      seen.set(pkg.visitId, pkg);
    }
  }
  return [...seen.values()];
}

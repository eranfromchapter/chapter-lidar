// Projects and packages lists (web-review §6.1, §6.2): verdict tabs, titles and the table cells
// that every list shares. Pure functions over the station's review lists; no station calls.

import { OUTCOME_WORD } from "@chapter/capture-contract";
import { dayLabel, formatDate } from "./format";
import type { HubProject, PackageSummary, ReviewProject } from "./station-types";

/** Longest accepted search text (OpenAPI listReviewProjects q maxLength). */
export const QUERY_MAX = 200;

export function normalizeQuery(raw: string | string[] | undefined): string {
  const value = Array.isArray(raw) ? raw[0] : raw;
  return (value ?? "").trim().slice(0, QUERY_MAX);
}

export type ProjectTab = "all" | "blocked" | "limited" | "ready" | "progress";

/** The five tabs of the Projects page, in order. */
export const PROJECT_TABS: readonly { id: ProjectTab; label: string }[] = [
  { id: "all", label: "All" },
  { id: "blocked", label: OUTCOME_WORD.blocked },
  { id: "limited", label: OUTCOME_WORD.limited },
  { id: "ready", label: OUTCOME_WORD.ready },
  { id: "progress", label: "Uploading" },
];

export function parseTab(raw: string | string[] | undefined): ProjectTab {
  const value = Array.isArray(raw) ? raw[0] : raw;
  return PROJECT_TABS.some((tab) => tab.id === value) ? (value as ProjectTab) : "all";
}

/**
 * The tab of a project by its newest package: its verdict's outcome, or "progress" while it has
 * no verdict (uploading, checks queued or running, checks that did not finish).
 */
export function tabOf(latest: PackageSummary): Exclude<ProjectTab, "all"> {
  return latest.verdict?.outcome ?? "progress";
}

export function tabCounts(projects: readonly ReviewProject[]): Record<ProjectTab, number> {
  const counts: Record<ProjectTab, number> = {
    all: projects.length,
    blocked: 0,
    limited: 0,
    ready: 0,
    progress: 0,
  };
  for (const project of projects) {
    counts[tabOf(project.latest)] += 1;
  }
  return counts;
}

export function filterByTab(
  projects: readonly ReviewProject[],
  tab: ProjectTab,
): readonly ReviewProject[] {
  return tab === "all" ? projects : projects.filter((project) => tabOf(project.latest) === tab);
}

/** Empty-tab sentence. */
export function emptyTabText(tab: Exclude<ProjectTab, "all">): string {
  return tab === "progress"
    ? "No packages uploading or being checked."
    : `No ${OUTCOME_WORD[tab]} projects.`;
}

/** Project title: the HUB project name, else its address (web-review §5.5). */
export function projectTitle(project: Pick<HubProject, "projectName" | "address">): string {
  return project.projectName ?? project.address.formatted;
}

/** Upload progress of a package, 0 to 100 (whole percent of the declared bytes verified). */
export function uploadPercent(summary: Pick<PackageSummary, "totals">): number {
  const { bytes, bytesVerified } = summary.totals;
  if (bytes <= 0) {
    return 0;
  }
  return Math.min(100, Math.max(0, Math.floor((bytesVerified / bytes) * 100)));
}

/** "Latest package" cell: its words and, while uploading, the progress percent. */
export function latestPackageText(summary: PackageSummary): { text: string; percent?: number } {
  if (summary.status === "uploading") {
    return {
      text: `Revision ${summary.revision} · uploading from the phone`,
      percent: uploadPercent(summary),
    };
  }
  const sealed = summary.sealedAt ?? summary.createdAt;
  return { text: `Revision ${summary.revision} · sealed ${formatDate(sealed)}` };
}

/** "Captured" cell: the visit day and operator once sealed, else when and by whom it opened. */
export function capturedText(summary: PackageSummary, now: Date): string {
  if (summary.visitedAt !== undefined) {
    const day = dayLabel(summary.visitedAt, now);
    return summary.operatorName === undefined ? day : `${day} · ${summary.operatorName}`;
  }
  const day = dayLabel(summary.createdAt, now);
  return summary.createdBy === undefined ? day : `${day} · ${summary.createdBy.name}`;
}

export type CellTone = "normal" | "muted" | "danger";

/** "In the HUB" cell of a package (the station's publication state). */
export function hubText(summary: PackageSummary): { text: string; tone: CellTone } {
  const publication = summary.publication;
  if (publication === undefined) {
    return summary.verdict?.outcome === "blocked"
      ? { text: "Not published · re-seal needed", tone: "normal" }
      : { text: "—", tone: "muted" };
  }
  switch (publication.status) {
    case "published":
      return {
        text:
          publication.publishedAt === undefined
            ? "Published"
            : `Published ${formatDate(publication.publishedAt)}`,
        tone: "normal",
      };
    case "pending":
    case "publishing":
      return { text: "Publishing…", tone: "muted" };
    case "publish_failed":
      return { text: "Publishing failed", tone: "danger" };
  }
}

/** Newest update of a list ("updated 2 min ago"), or undefined for an empty list. */
export function newestUpdate(summaries: readonly PackageSummary[]): string | undefined {
  let newest: string | undefined;
  for (const summary of summaries) {
    if (newest === undefined || Date.parse(summary.updatedAt) > Date.parse(newest)) {
      newest = summary.updatedAt;
    }
  }
  return newest;
}

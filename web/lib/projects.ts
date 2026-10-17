// Project list data for the left column of every review page.

import type { StationClient } from "./station";
import type { HubProject } from "./station-types";
import { areaCount, outcomeLabel, PACKAGE_STATUS } from "./format";

export type StatusTone = "ready" | "limited" | "blocked" | "muted";

export interface ProjectNavItem {
  readonly dealId: string;
  readonly address: string;
  readonly statusText: string;
  readonly tone: StatusTone;
}

export type ProjectNavData =
  | { readonly ok: true; readonly query: string; readonly items: readonly ProjectNavItem[] }
  | { readonly ok: false; readonly query: string; readonly message: string };

/** Longest accepted search text (OpenAPI listProjects q maxLength). */
const QUERY_MAX = 200;

export function normalizeQuery(raw: string | string[] | undefined): string {
  const value = Array.isArray(raw) ? raw[0] : raw;
  return (value ?? "").trim().slice(0, QUERY_MAX);
}

async function statusOf(
  station: StationClient,
  project: HubProject,
): Promise<Pick<ProjectNavItem, "statusText" | "tone">> {
  try {
    const packages = await station.listPackages(project.dealId);
    const latest = packages[0];
    if (latest === undefined) {
      return { statusText: "No packages yet", tone: "muted" };
    }
    const parts: string[] = [];
    let tone: StatusTone = "muted";
    if (latest.verdict !== undefined) {
      parts.push(outcomeLabel(latest.verdict.outcome));
      tone = latest.verdict.outcome;
    } else {
      parts.push(PACKAGE_STATUS[latest.status]);
    }
    parts.push(`r${latest.revision}`);
    const detail = await station.getPackage(latest.packageId);
    if (detail.captureRecord !== undefined) {
      parts.push(areaCount(detail.captureRecord));
    }
    return { statusText: parts.join(" · "), tone };
  } catch {
    return { statusText: "Status unavailable", tone: "muted" };
  }
}

/** Projects for the left column, each with its latest package's status. */
export async function loadProjectNav(
  station: StationClient,
  query: string,
): Promise<ProjectNavData> {
  let projects: HubProject[];
  try {
    projects = await station.listProjects(query.length > 0 ? { q: query } : {});
  } catch {
    return {
      ok: false,
      query,
      message: "Projects could not be loaded from the station. Try again in a moment.",
    };
  }
  const items = await Promise.all(
    projects.map(async (project) => ({
      dealId: project.dealId,
      address: project.address.formatted,
      ...(await statusOf(station, project)),
    })),
  );
  return { ok: true, query, items };
}

// "/" — Projects (web-review §6.1, artboard 2h): every project with packages, its newest
// package and verdict, filtered by verdict tabs and the topbar search.

import type { Metadata } from "next";
import { Tabs } from "@/components/hub/Tabs";
import { VerdictLegend } from "@/components/Legend";
import { ProjectsTable } from "@/components/projects/ProjectsTable";
import { Topbar } from "@/components/shell/Topbar";
import { NoStationRole, stationProblem } from "@/components/StationProblem";
import { plural, updatedAgo } from "@/lib/format";
import {
  filterByTab,
  newestUpdate,
  normalizeQuery,
  parseTab,
  PROJECT_TABS,
  tabCounts,
  type ProjectTab,
} from "@/lib/review";
import { hasStationAccess } from "@/lib/roles";
import type { ReviewProject, StationPage } from "@/lib/station-types";
import { requireViewerSession } from "@/lib/viewer";

export const dynamic = "force-dynamic";

export const metadata: Metadata = { title: "Projects · Capture review" };

interface ProjectsPageProps {
  readonly searchParams: Promise<Record<string, string | string[] | undefined>>;
}

function pageHref(query: string, tab: ProjectTab): string {
  const params = new URLSearchParams();
  if (query.length > 0) {
    params.set("q", query);
  }
  if (tab !== "all") {
    params.set("tab", tab);
  }
  const search = params.toString();
  return search.length === 0 ? "/" : `/?${search}`;
}

export default async function ProjectsPage({ searchParams }: ProjectsPageProps) {
  const params = await searchParams;
  const query = normalizeQuery(params.q);
  const tab = parseTab(params.tab);
  const returnTo = pageHref(query, tab);
  const { viewer, station } = await requireViewerSession(returnTo);
  const topbar = <Topbar title="Capture review" query={query} />;
  if (!hasStationAccess(viewer.roles)) {
    return (
      <>
        {topbar}
        <main className="page" id="main">
          <NoStationRole />
        </main>
      </>
    );
  }

  let page: StationPage<ReviewProject>;
  try {
    page = await station.listReviewProjects(query.length > 0 ? { q: query } : {});
  } catch (error) {
    return (
      <>
        {topbar}
        <main className="page" id="main">
          {stationProblem(error, returnTo)}
        </main>
      </>
    );
  }

  const now = new Date();
  const projects = page.items;
  const counts = tabCounts(projects);
  const updated = newestUpdate(projects.map((project) => project.latest));
  return (
    <>
      {topbar}
      <main className="page" id="main">
        <div className="page-head">
          <div className="page-head__text">
            <h2 className="page-title">Projects</h2>
            <span className="page-sub">
              Capture packages from the station, by project. Verdicts are the station&apos;s;
              re-sealing a Blocked package happens on the phone.
            </span>
          </div>
          {projects.length === 0 ? null : (
            <span className="page-count">
              {plural(projects.length, "project")}
              {updated === undefined ? "" : ` · updated ${updatedAgo(updated, now)}`}
            </span>
          )}
        </div>
        <Tabs
          label="Verdicts"
          value={tab}
          items={PROJECT_TABS.map((item) => ({
            id: item.id,
            label: item.label,
            count: counts[item.id],
            href: pageHref(query, item.id),
          }))}
        />
        <ProjectsTable
          projects={filterByTab(projects, tab)}
          total={projects.length}
          tab={tab}
          query={query}
          truncated={page.truncated}
          now={now}
        />
        <VerdictLegend />
      </main>
    </>
  );
}

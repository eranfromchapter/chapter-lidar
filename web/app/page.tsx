// "/" — project list.

import { PageFrame } from "@/components/PageFrame";
import { NoStationRole } from "@/components/StationProblem";
import { loadProjectNav, normalizeQuery } from "@/lib/projects";
import { hasStationAccess } from "@/lib/roles";
import { requireViewerSession } from "@/lib/viewer";

export const dynamic = "force-dynamic";

interface ProjectsPageProps {
  readonly searchParams: Promise<Record<string, string | string[] | undefined>>;
}

export default async function ProjectsPage({ searchParams }: ProjectsPageProps) {
  const query = normalizeQuery((await searchParams).q);
  const returnTo = query.length > 0 ? `/?q=${encodeURIComponent(query)}` : "/";
  const { viewer, station } = await requireViewerSession(returnTo);
  if (!hasStationAccess(viewer.roles)) {
    return (
      <PageFrame viewer={viewer} nav={null}>
        <NoStationRole />
      </PageFrame>
    );
  }
  const nav = await loadProjectNav(station, query);
  return (
    <PageFrame viewer={viewer} nav={nav}>
      <div className="page-title">
        <h1>Projects</h1>
        <span className="page-title__meta">
          Choose a project to see its capture packages, verdicts and files.
        </span>
      </div>
    </PageFrame>
  );
}

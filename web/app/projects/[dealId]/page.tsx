// "/projects/[dealId]" — packages of one HUB project: revision, status and outcome.

import { PageFrame } from "@/components/PageFrame";
import { NoStationRole, stationProblem } from "@/components/StationProblem";
import { formatDateTime, outcomeLabel, PACKAGE_STATUS } from "@/lib/format";
import { loadProjectNav } from "@/lib/projects";
import { hasStationAccess } from "@/lib/roles";
import type { HubProject, PackageSummary } from "@/lib/station-types";
import { requireViewerSession } from "@/lib/viewer";

export const dynamic = "force-dynamic";

interface ProjectPageProps {
  readonly params: Promise<{ dealId: string }>;
}

function PackagesTable({ packages }: { readonly packages: readonly PackageSummary[] }) {
  return (
    <section className="section" aria-labelledby="packages-title">
      <h2 id="packages-title">Capture packages</h2>
      <div className="table-card">
        <table className="table">
          <thead>
            <tr>
              <th scope="col">Revision</th>
              <th scope="col">Status</th>
              <th scope="col">Outcome</th>
              <th scope="col">Sealed</th>
            </tr>
          </thead>
          <tbody>
            {packages.length === 0 ? (
              <tr>
                <td colSpan={4} className="caption">
                  No capture packages for this project yet.
                </td>
              </tr>
            ) : (
              packages.map((item) => (
                <tr key={item.packageId}>
                  <td>
                    <a href={`/packages/${item.packageId}`}>Revision {item.revision}</a>
                  </td>
                  <td>{PACKAGE_STATUS[item.status]}</td>
                  <td
                    className={
                      item.verdict === undefined
                        ? "tone-muted"
                        : `table__severity tone-${item.verdict.outcome}`
                    }
                  >
                    {item.verdict === undefined
                      ? "No verdict yet"
                      : outcomeLabel(item.verdict.outcome)}
                  </td>
                  <td>
                    {item.sealedAt === undefined ? "Not sealed" : formatDateTime(item.sealedAt)}
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </section>
  );
}

export default async function ProjectPage({ params }: ProjectPageProps) {
  const { dealId } = await params;
  const { viewer, station } = await requireViewerSession(`/projects/${encodeURIComponent(dealId)}`);
  if (!hasStationAccess(viewer.roles)) {
    return (
      <PageFrame viewer={viewer} nav={null}>
        <NoStationRole />
      </PageFrame>
    );
  }

  const navPromise = loadProjectNav(station, "");
  let project: HubProject;
  let packages: PackageSummary[];
  try {
    [project, packages] = await Promise.all([
      station.getProject(dealId),
      station.listPackages(dealId),
    ]);
  } catch (error) {
    const problem = stationProblem(error);
    return (
      <PageFrame viewer={viewer} nav={await navPromise} selectedDealId={dealId}>
        {problem}
      </PageFrame>
    );
  }

  return (
    <PageFrame viewer={viewer} nav={await navPromise} selectedDealId={dealId}>
      <div className="page-title">
        <h1>{project.address.formatted}</h1>
        <span className="page-title__meta">
          {project.projectName === undefined ? "" : `${project.projectName} · `}HUB deal{" "}
          <span className="mono">{project.dealId}</span>
        </span>
      </div>
      <PackagesTable packages={packages} />
    </PageFrame>
  );
}

// "/packages" — Packages (web-review §6.2, sidebar "Packages"): every package revision the
// station has, newest first.

import type { Metadata } from "next";
import { PackagesListTable } from "@/components/packages/PackagesListTable";
import { Topbar } from "@/components/shell/Topbar";
import { NoStationRole, stationProblem } from "@/components/StationProblem";
import { plural } from "@/lib/format";
import { normalizeQuery } from "@/lib/review";
import { hasStationAccess } from "@/lib/roles";
import type { ReviewPackage, StationPage } from "@/lib/station-types";
import { requireViewerSession } from "@/lib/viewer";

export const dynamic = "force-dynamic";

export const metadata: Metadata = { title: "Packages · Capture review" };

interface PackagesPageProps {
  readonly searchParams: Promise<Record<string, string | string[] | undefined>>;
}

export default async function PackagesPage({ searchParams }: PackagesPageProps) {
  const query = normalizeQuery((await searchParams).q);
  const returnTo = query.length > 0 ? `/packages?q=${encodeURIComponent(query)}` : "/packages";
  const { viewer, station } = await requireViewerSession(returnTo);
  const topbar = <Topbar title="Packages" />;
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
  let page: StationPage<ReviewPackage>;
  try {
    page = await station.listReviewPackages(query.length > 0 ? { q: query } : {});
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
  return (
    <>
      {topbar}
      <main className="page" id="main">
        <div className="page-head">
          <div className="page-head__text">
            <h2 className="page-title">Packages</h2>
            <span className="page-sub">Every package revision the station has, newest first.</span>
          </div>
          {page.items.length === 0 ? null : (
            <span className="page-count">{plural(page.items.length, "package")}</span>
          )}
        </div>
        <PackagesListTable
          packages={page.items}
          query={query}
          truncated={page.truncated}
          now={new Date()}
        />
      </main>
    </>
  );
}

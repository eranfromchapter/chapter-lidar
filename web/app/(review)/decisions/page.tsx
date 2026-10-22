// "/decisions" — Decision log (web-review §6.5, sidebar "Decision log"): every modeling decision
// logged against any capture package, newest first, each linked to its package. bim and admin;
// the capture role gets "No access".

import type { Metadata } from "next";
import { Card } from "@/components/hub/Card";
import { DecisionList, type DecisionEntry } from "@/components/DecisionList";
import { Notice } from "@/components/Notice";
import { Topbar } from "@/components/shell/Topbar";
import { NoStationRole, stationProblem } from "@/components/StationProblem";
import type { DecisionContext } from "@/lib/decisions";
import { projectTitle } from "@/lib/review";
import { hasStationAccess } from "@/lib/roles";
import type { StationClient } from "@/lib/station";
import { requireViewerSession } from "@/lib/viewer";

export const dynamic = "force-dynamic";

export const metadata: Metadata = { title: "Decision log · Capture review" };

/** The station's page size for the log. */
const LIMIT = 100;
/** Packages read to word the sources of the listed decisions; others show path names. */
const CONTEXT_PACKAGES = 25;

async function loadEntries(
  station: StationClient,
): Promise<{ entries: DecisionEntry[]; truncated: boolean }> {
  const [page, projects] = await Promise.all([
    station.listAllModelingDecisions({ limit: LIMIT }),
    station.listReviewProjects({ limit: 200 }),
  ]);
  const titles = new Map(projects.items.map((project) => [project.dealId, projectTitle(project)]));
  const packageIds = [...new Set(page.items.map((decision) => decision.packageId))].slice(
    0,
    CONTEXT_PACKAGES,
  );
  const contexts = new Map<string, DecisionContext>();
  await Promise.all(
    packageIds.map(async (packageId) => {
      try {
        const pkg = await station.getPackage(packageId);
        contexts.set(packageId, {
          files: pkg.files,
          ...(pkg.captureRecord === undefined ? {} : { captureRecord: pkg.captureRecord }),
          ...(pkg.fieldControls === undefined ? {} : { fieldControls: pkg.fieldControls }),
        });
      } catch {
        // The entry still lists; its sources are named from their paths.
      }
    }),
  );
  return {
    truncated: page.truncated,
    entries: page.items.map((decision) => {
      const context = contexts.get(decision.packageId);
      return {
        decision,
        ...(context === undefined ? {} : { context }),
        link: {
          text: `${titles.get(decision.dealId) ?? `HUB deal ${decision.dealId}`} · Revision ${decision.revision}`,
          href: `/packages/${encodeURIComponent(decision.packageId)}#decisions`,
        },
      };
    }),
  };
}

export default async function DecisionLogPage() {
  const { viewer, station } = await requireViewerSession("/decisions");
  const topbar = <Topbar title="Decision log" />;
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
  if (!viewer.canReview) {
    return (
      <>
        {topbar}
        <main className="page" id="main">
          <Notice role="alert" title="No access">
            Modeling decisions are read and logged by BIM operators and admins. Your account can see
            the package status only.
          </Notice>
        </main>
      </>
    );
  }
  let loaded: { entries: DecisionEntry[]; truncated: boolean };
  try {
    loaded = await loadEntries(station);
  } catch (error) {
    return (
      <>
        {topbar}
        <main className="page" id="main">
          {stationProblem(error, "/decisions")}
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
            <h2 className="page-title">Decision log</h2>
            <span className="page-sub">
              Every modeling decision logged against a capture package, newest first.
            </span>
          </div>
        </div>
        <Card padding="md" label="Modeling decisions">
          <div className="hub-stack hub-stack--12">
            <DecisionList entries={loaded.entries} label="Modeling decisions" />
            {loaded.truncated ? (
              <span className="text-12 text-muted">Showing the {LIMIT} newest decisions.</span>
            ) : null}
          </div>
        </Card>
      </main>
    </>
  );
}

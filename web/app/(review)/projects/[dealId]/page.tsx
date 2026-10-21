// "/projects/[dealId]" — Project (web-review §6.3, artboard 2i, addendum D7): every revision of
// the project with the one the phone is preparing, what the newest revision adds, the latest
// verdict and the decision log.

import type { Metadata } from "next";
import { notFound } from "next/navigation";
import type { Verdict } from "@chapter/capture-contract";
import { Tabs } from "@/components/hub/Tabs";
import { DecisionSummaryCard } from "@/components/project/DecisionSummaryCard";
import { LatestVerdictCard } from "@/components/project/LatestVerdictCard";
import { PackagesTable } from "@/components/project/PackagesTable";
import { ProjectDecisionLog } from "@/components/project/ProjectDecisionLog";
import { ProjectHeader } from "@/components/project/ProjectHeader";
import { RevisionDiffCard } from "@/components/project/RevisionDiffCard";
import { Topbar } from "@/components/shell/Topbar";
import { NoStationRole, stationProblem } from "@/components/StationProblem";
import type { DecisionEntry } from "@/components/DecisionList";
import { safeExternalLink } from "@/lib/links";
import {
  headingFromProject,
  headingFromRecord,
  hubCannotAnswer,
  newestPerVisit,
  type ProjectHeading,
} from "@/lib/packages";
import { revisionStateText } from "@/lib/project-view";
import { noticeTiles, stationDiff, type ChangeTile } from "@/lib/revision-diff";
import { hasStationAccess } from "@/lib/roles";
import { StationError, type StationClient } from "@/lib/station";
import type {
  HubProject,
  ModelingDecisionWithContext,
  NextRevisionNotice,
  PackageSummary,
  StationPackage,
} from "@/lib/station-types";
import { requireViewerSession } from "@/lib/viewer";

export const dynamic = "force-dynamic";

export const metadata: Metadata = { title: "Project · Capture review" };

interface ProjectPageProps {
  readonly params: Promise<{ dealId: string }>;
  readonly searchParams: Promise<Record<string, string | string[] | undefined>>;
}

interface ProjectData {
  readonly heading: ProjectHeading;
  readonly packages: PackageSummary[];
  readonly notices: Map<string, NextRevisionNotice>;
  readonly diffLines: Map<string, string>;
  readonly revisionCard?: { revision: number; state: string; tiles: ChangeTile[] };
  readonly latest?: { packageId: string; revision: number; verdict: Verdict };
  readonly decisions: DecisionEntry[];
  readonly hubUrl: string | null;
}

async function loadProject(
  station: StationClient,
  dealId: string,
  canReview: boolean,
): Promise<ProjectData> {
  const [project, packages] = await Promise.all([
    station.getProject(dealId).then(
      (value): { ok: true; value: HubProject } => ({ ok: true, value }),
      (error: unknown): { ok: false; error: unknown } => ({ ok: false, error }),
    ),
    station.listPackages(dealId),
  ]);

  const details = new Map<string, Promise<StationPackage>>();
  const detail = (packageId: string) => {
    let found = details.get(packageId);
    if (found === undefined) {
      found = station.getPackage(packageId);
      details.set(packageId, found);
    }
    return found;
  };
  const verdicts = new Map<string, Promise<Verdict | null>>();
  const verdictOf = (packageId: string) => {
    let found = verdicts.get(packageId);
    if (found === undefined) {
      found = station.getVerdict(packageId);
      verdicts.set(packageId, found);
    }
    return found;
  };

  let heading: ProjectHeading;
  if (project.ok) {
    heading = headingFromProject(project.value);
  } else {
    if (!hubCannotAnswer(project.error)) {
      throw project.error;
    }
    if (packages.length === 0) {
      notFound();
    }
    const sealed = packages.find((pkg) => pkg.sealedAt !== undefined);
    heading = headingFromRecord(
      dealId,
      sealed === undefined ? undefined : (await detail(sealed.packageId)).captureRecord,
    );
  }

  // The phone's next revision is noted on the newest sealed package of each visit.
  const notices = new Map<string, NextRevisionNotice>();
  const heads = newestPerVisit(packages).filter((pkg) => pkg.status !== "uploading");
  await Promise.all(
    heads.map(async (pkg) => {
      const found = (await detail(pkg.packageId)).nextRevision;
      if (found !== undefined) {
        notices.set(pkg.packageId, found);
      }
    }),
  );

  const withVerdict = packages.find((pkg) => pkg.verdict !== undefined);
  const latestVerdict = withVerdict === undefined ? null : await verdictOf(withVerdict.packageId);

  const diffLines = new Map<string, string>();
  let revisionCard: ProjectData["revisionCard"];
  const newestVisit = packages[0];
  const noticed = packages.find((pkg) => notices.has(pkg.packageId));
  if (
    noticed !== undefined &&
    newestVisit !== undefined &&
    noticed.visitId === newestVisit.visitId
  ) {
    const notice = notices.get(noticed.packageId) as NextRevisionNotice;
    const base = await detail(noticed.packageId);
    const baseVerdict = noticed.verdict === undefined ? null : await verdictOf(noticed.packageId);
    revisionCard = {
      revision: notice.revision,
      state: "from the phone, not sealed yet",
      tiles: noticeTiles(notice, baseVerdict, base.captureRecord),
    };
  } else if (
    newestVisit !== undefined &&
    newestVisit.revision > 1 &&
    newestVisit.verdict === undefined
  ) {
    const after = await detail(newestVisit.packageId);
    let tiles: ChangeTile[] = [];
    if (after.supersedesPackageId !== undefined) {
      try {
        const diff = stationDiff(await detail(after.supersedesPackageId), after);
        tiles = diff.tiles;
        if (diff.compact.length > 0) {
          diffLines.set(after.packageId, diff.compact);
        }
      } catch (error) {
        if (!(error instanceof StationError && error.status === 404)) {
          throw error;
        }
      }
    }
    revisionCard = {
      revision: newestVisit.revision,
      state: revisionStateText(newestVisit),
      tiles,
    };
  }

  let decisions: DecisionEntry[] = [];
  if (canReview) {
    const page = await station.listAllModelingDecisions({ dealId, limit: 200 });
    decisions = await Promise.all(
      page.items.map(async (decision: ModelingDecisionWithContext) => {
        const pkg = await detail(decision.packageId).catch(() => undefined);
        return {
          decision,
          revision: decision.revision,
          ...(pkg === undefined
            ? {}
            : {
                context: {
                  files: pkg.files,
                  ...(pkg.captureRecord === undefined ? {} : { captureRecord: pkg.captureRecord }),
                  ...(pkg.fieldControls === undefined ? {} : { fieldControls: pkg.fieldControls }),
                },
              }),
        };
      }),
    );
  }

  const hubUrl = safeExternalLink(packages.find((pkg) => pkg.links?.hub !== undefined)?.links?.hub);
  return {
    heading,
    packages,
    notices,
    diffLines,
    ...(revisionCard === undefined ? {} : { revisionCard }),
    ...(withVerdict === undefined || latestVerdict === null
      ? {}
      : {
          latest: {
            packageId: withVerdict.packageId,
            revision: withVerdict.revision,
            verdict: latestVerdict,
          },
        }),
    decisions,
    hubUrl,
  };
}

export default async function ProjectPage({ params, searchParams }: ProjectPageProps) {
  const { dealId } = await params;
  const wantsLog = (await searchParams).tab === "log";
  const path = `/projects/${encodeURIComponent(dealId)}`;
  const { viewer, station } = await requireViewerSession(wantsLog ? `${path}?tab=log` : path);
  if (!hasStationAccess(viewer.roles)) {
    return (
      <>
        <Topbar title="Project" />
        <main className="page" id="main">
          <NoStationRole />
        </main>
      </>
    );
  }
  const tab = wantsLog && viewer.canReview ? "log" : "packages";

  let data: ProjectData;
  try {
    data = await loadProject(station, dealId, viewer.canReview);
  } catch (error) {
    return (
      <>
        <Topbar title="Project" />
        <main className="page" id="main">
          {stationProblem(error, tab === "log" ? `${path}?tab=log` : path)}
        </main>
      </>
    );
  }

  const now = new Date();
  const packageCount = data.packages.length + data.notices.size;
  const reportPackage = viewer.canReview
    ? data.packages.find((pkg) => pkg.report?.status === "ready")
    : undefined;
  const newest = data.packages[0];
  return (
    <>
      <Topbar title={data.heading.title} />
      <main className="page" id="main">
        <ProjectHeader
          dealId={dealId}
          heading={data.heading}
          packageCount={packageCount}
          latestWithVerdict={data.packages.find((pkg) => pkg.verdict !== undefined)}
          reportPackage={reportPackage}
          hubUrl={data.hubUrl}
        />
        <Tabs
          label="Project"
          value={tab}
          items={[
            { id: "packages", label: "Packages", count: packageCount, href: path },
            ...(viewer.canReview
              ? [
                  {
                    id: "log",
                    label: "Decision log",
                    count: data.decisions.length,
                    href: `${path}?tab=log`,
                  },
                ]
              : []),
          ]}
        />
        <div className="page-grid">
          <div className="page-col">
            {tab === "log" ? (
              <ProjectDecisionLog
                entries={data.decisions}
                {...(newest === undefined
                  ? {}
                  : { newest: { packageId: newest.packageId, revision: newest.revision } })}
              />
            ) : (
              <>
                <PackagesTable
                  packages={data.packages}
                  notices={data.notices}
                  diffLines={data.diffLines}
                  now={now}
                />
                {data.revisionCard === undefined ? null : (
                  <RevisionDiffCard
                    revision={data.revisionCard.revision}
                    state={data.revisionCard.state}
                    tiles={data.revisionCard.tiles}
                  />
                )}
              </>
            )}
          </div>
          <div className="page-col page-col--aside">
            <LatestVerdictCard latest={data.latest} canReview={viewer.canReview} />
            {viewer.canReview ? (
              <DecisionSummaryCard
                decisions={data.decisions.map((entry) => entry.decision)}
                logHref={`${path}?tab=log`}
              />
            ) : null}
          </div>
        </div>
      </main>
    </>
  );
}

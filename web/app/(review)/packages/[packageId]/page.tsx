// "/packages/[packageId]" — Package (web-review §6.4, artboard 2j): the verdict, the plan of each
// floor, the capture checks in the spatial report's words, the files, the decision log, the
// capture record, field controls, station timeline and documents. Capture-role users see the
// status only (§6.6): everything else is not rendered.
//
// "?file=<path>" (a deep link from the HUB) highlights and scrolls to that file; "?floor=<areaKey>"
// selects the floor of the plan preview.

import type { Metadata } from "next";
import type { Verdict } from "@chapter/capture-contract";
import { CaptureRecordCard } from "@/components/package/CaptureRecordCard";
import { ChecksCard } from "@/components/package/ChecksCard";
import { DecisionLogCard } from "@/components/package/DecisionLogCard";
import { DocumentsCard } from "@/components/package/DocumentsCard";
import { FieldControlsCard } from "@/components/package/FieldControlsCard";
import { FilesCard } from "@/components/package/FilesCard";
import { PackageHeader } from "@/components/package/PackageHeader";
import { PlanCard } from "@/components/package/PlanCard";
import { StationCard } from "@/components/package/StationCard";
import { StatusCard } from "@/components/package/StatusCard";
import { VerdictCard } from "@/components/package/VerdictCard";
import { Topbar } from "@/components/shell/Topbar";
import { NoStationRole, stationProblem } from "@/components/StationProblem";
import { sourceGroups } from "@/lib/decisions";
import { buildFileRows, floorOptions, roleOptions } from "@/lib/files-view";
import { hubFilesUrl } from "@/lib/links";
import {
  loadHeading,
  loadVerdict,
  newerRevisions,
  replacedBy,
  type ProjectHeading,
} from "@/lib/packages";
import { hasStationAccess } from "@/lib/roles";
import type { ModelingDecision, PackageSummary, StationPackage } from "@/lib/station-types";
import { requireViewerSession } from "@/lib/viewer";
import { saveDecision } from "./decisions/actions";

export const dynamic = "force-dynamic";

export const metadata: Metadata = { title: "Package · Capture review" };

interface PackagePageProps {
  readonly params: Promise<{ packageId: string }>;
  readonly searchParams: Promise<Record<string, string | string[] | undefined>>;
}

function first(value: string | string[] | undefined): string | undefined {
  const found = Array.isArray(value) ? value[0] : value;
  return found === undefined || found.length === 0 ? undefined : found;
}

interface PackageData {
  readonly pkg: StationPackage;
  readonly heading: ProjectHeading;
  readonly verdict: Verdict | null;
  readonly siblings: PackageSummary[];
  readonly decisions: ModelingDecision[];
}

export default async function PackagePage({ params, searchParams }: PackagePageProps) {
  const { packageId } = await params;
  const query = await searchParams;
  const targetPath = first(query.file);
  const floor = first(query.floor);
  const search = new URLSearchParams();
  if (targetPath !== undefined) {
    search.set("file", targetPath);
  }
  if (floor !== undefined) {
    search.set("floor", floor);
  }
  const path = `/packages/${encodeURIComponent(packageId)}`;
  const returnTo = search.size === 0 ? path : `${path}?${search.toString()}`;
  const { viewer, station } = await requireViewerSession(returnTo);
  if (!hasStationAccess(viewer.roles)) {
    return (
      <>
        <Topbar title="Package" />
        <main className="page" id="main">
          <NoStationRole />
        </main>
      </>
    );
  }

  let data: PackageData;
  try {
    const pkg = await station.getPackage(packageId);
    const [heading, verdict, siblings, decisions] = await Promise.all([
      loadHeading(station, pkg.dealId, async () => pkg.captureRecord),
      loadVerdict(station, pkg),
      station.listPackages(pkg.dealId),
      viewer.canReview ? station.listModelingDecisions(pkg.packageId) : Promise.resolve([]),
    ]);
    data = { pkg, heading, verdict, siblings, decisions };
  } catch (error) {
    return (
      <>
        <Topbar title="Package" />
        <main className="page" id="main">
          {stationProblem(error, returnTo)}
        </main>
      </>
    );
  }

  const { pkg, heading, verdict, siblings, decisions } = data;
  const title = `${heading.title} · Revision ${pkg.revision}`;
  const newer = newerRevisions(siblings, pkg)[0];
  const successor = replacedBy(siblings, pkg);
  const record = pkg.captureRecord;
  const rows = viewer.canReview ? buildFileRows(pkg) : [];
  const hubFiles =
    viewer.canReview && pkg.publication !== undefined
      ? hubFilesUrl(pkg.dealId, pkg.publication.hubFolder)
      : null;

  return (
    <>
      <Topbar title={title} />
      <main className="page" id="main">
        <PackageHeader
          pkg={pkg}
          title={heading.title}
          verdict={verdict}
          canReview={viewer.canReview}
        />
        <div className="page-grid">
          <div className="page-col">
            {verdict === null ? (
              <StatusCard
                pkg={pkg}
                {...(successor === undefined ? {} : { replacedBy: successor })}
              />
            ) : (
              <VerdictCard
                verdict={verdict}
                captureRecord={record}
                {...(pkg.nextRevision === undefined ? {} : { nextRevision: pkg.nextRevision })}
                {...(newer === undefined ? {} : { newer })}
              />
            )}
            {viewer.canReview ? (
              <>
                {record === undefined ? null : (
                  <PlanCard
                    pkg={{ ...pkg, captureRecord: record }}
                    {...(floor === undefined ? {} : { floor })}
                  />
                )}
                {verdict === null ? null : (
                  <ChecksCard
                    verdict={verdict}
                    captureRecord={record}
                    {...(pkg.report === undefined ? {} : { report: pkg.report })}
                  />
                )}
                <FilesCard
                  rows={rows}
                  totalFiles={pkg.totals.files}
                  floorOptions={floorOptions(pkg)}
                  roleOptions={roleOptions(rows)}
                  {...(targetPath === undefined ? {} : { targetPath })}
                />
                <DecisionLogCard
                  packageId={pkg.packageId}
                  decisions={decisions}
                  context={{
                    files: pkg.files,
                    ...(record === undefined ? {} : { captureRecord: record }),
                    ...(pkg.fieldControls === undefined
                      ? {}
                      : { fieldControls: pkg.fieldControls }),
                  }}
                  sources={sourceGroups(pkg)}
                  action={saveDecision}
                />
              </>
            ) : null}
          </div>
          <div className="page-col page-col--aside">
            {viewer.canReview ? (
              <>
                <CaptureRecordCard
                  record={record}
                  {...(pkg.report === undefined ? {} : { report: pkg.report })}
                />
                <FieldControlsCard pkg={pkg} />
              </>
            ) : null}
            <StationCard pkg={pkg} verdict={verdict} hubFilesUrl={hubFiles} />
            {viewer.canReview ? <DocumentsCard pkg={pkg} /> : null}
          </div>
        </div>
        {viewer.canReview ? null : (
          <p className="text-13 text-muted" style={{ margin: 0 }}>
            Checks, files and downloads are shown to BIM operators and admins.
          </p>
        )}
      </main>
    </>
  );
}

// "/packages/[packageId]" — package detail: capture record, verdict, every finding and the
// files. "?file=<path>" highlights and scrolls to that file (linked from the verdict report).

import type { Verdict } from "@chapter/capture-contract";
import { FilesTable } from "@/components/FilesTable";
import { FindingsTable } from "@/components/FindingsTable";
import { Notice } from "@/components/Notice";
import { PackageHeading } from "@/components/PackageHeading";
import { PageFrame } from "@/components/PageFrame";
import { NoStationRole, stationProblem } from "@/components/StationProblem";
import { VerdictCard } from "@/components/VerdictCard";
import { loadPackageBase, loadVerdict, type PackageBase } from "@/lib/packages";
import { loadProjectNav } from "@/lib/projects";
import { hasStationAccess } from "@/lib/roles";
import type { PackageStatus } from "@/lib/station-types";
import { requireViewerSession } from "@/lib/viewer";

export const dynamic = "force-dynamic";

interface PackagePageProps {
  readonly params: Promise<{ packageId: string }>;
  readonly searchParams: Promise<Record<string, string | string[] | undefined>>;
}

function PendingVerdict({ status }: { readonly status: PackageStatus }) {
  if (status === "uploading") {
    return (
      <Notice title="Upload in progress">
        Not every file is verified and sealed yet. The checks start when the package is sealed.
      </Notice>
    );
  }
  if (status === "check_error") {
    return (
      <Notice role="alert" title="The checks could not complete">
        The station could not finish the acceptance checks. This is not a verdict; the station
        retries or an admin intervenes.
      </Notice>
    );
  }
  return (
    <Notice title="Checks running">
      The station is checking this package. The verdict and findings appear here when the checks
      finish.
    </Notice>
  );
}

export default async function PackagePage({ params, searchParams }: PackagePageProps) {
  const { packageId } = await params;
  const rawFile = (await searchParams).file;
  const targetPath = typeof rawFile === "string" && rawFile.length > 0 ? rawFile : undefined;
  const returnTo = `/packages/${encodeURIComponent(packageId)}${
    targetPath === undefined ? "" : `?file=${encodeURIComponent(targetPath)}`
  }`;
  const { viewer, station } = await requireViewerSession(returnTo);
  if (!hasStationAccess(viewer.roles)) {
    return (
      <PageFrame viewer={viewer} nav={null}>
        <NoStationRole />
      </PageFrame>
    );
  }

  const navPromise = loadProjectNav(station, "");
  let base: PackageBase;
  let verdict: Verdict | null;
  try {
    base = await loadPackageBase(station, packageId);
    verdict = await loadVerdict(station, base.pkg);
  } catch (error) {
    const problem = stationProblem(error);
    return (
      <PageFrame viewer={viewer} nav={await navPromise}>
        {problem}
      </PageFrame>
    );
  }
  const { pkg, address } = base;

  return (
    <PageFrame viewer={viewer} nav={await navPromise} selectedDealId={pkg.dealId}>
      <PackageHeading address={address} revision={pkg.revision} captureRecord={pkg.captureRecord} />
      {verdict === null ? (
        <PendingVerdict status={pkg.status} />
      ) : (
        <>
          <VerdictCard verdict={verdict} />
          <FindingsTable verdict={verdict} files={pkg.files} captureRecord={pkg.captureRecord} />
        </>
      )}
      <FilesTable
        packageId={pkg.packageId}
        files={pkg.files}
        captureRecord={pkg.captureRecord}
        canDownload={viewer.canReview}
        targetPath={targetPath}
      />
      {viewer.canReview ? (
        <section className="section" aria-labelledby="decisions-title">
          <h2 id="decisions-title">Modeling decision log</h2>
          <span>
            <a href={`/packages/${pkg.packageId}/decisions`}>
              Record the source used for each modeling decision
            </a>
          </span>
        </section>
      ) : null}
    </PageFrame>
  );
}

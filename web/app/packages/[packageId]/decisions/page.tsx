// "/packages/[packageId]/decisions" — modeling decision log: the form (bim, admin) and every
// logged decision with its author and time.

import { DecisionForm } from "@/components/DecisionForm";
import { DecisionList } from "@/components/DecisionList";
import { Notice } from "@/components/Notice";
import { PackageHeading } from "@/components/PackageHeading";
import { PageFrame } from "@/components/PageFrame";
import { NoStationRole, stationProblem } from "@/components/StationProblem";
import { fileDisplayName, ROLE_LABEL } from "@/lib/format";
import { loadPackageBase, type PackageBase } from "@/lib/packages";
import { loadProjectNav } from "@/lib/projects";
import { hasStationAccess } from "@/lib/roles";
import type { ModelingDecision } from "@/lib/station-types";
import { requireViewerSession } from "@/lib/viewer";
import { saveDecision } from "./actions";

export const dynamic = "force-dynamic";

interface DecisionsPageProps {
  readonly params: Promise<{ packageId: string }>;
}

export default async function DecisionsPage({ params }: DecisionsPageProps) {
  const { packageId } = await params;
  const { viewer, station } = await requireViewerSession(
    `/packages/${encodeURIComponent(packageId)}/decisions`,
  );
  if (!hasStationAccess(viewer.roles)) {
    return (
      <PageFrame viewer={viewer} nav={null}>
        <NoStationRole />
      </PageFrame>
    );
  }

  const navPromise = loadProjectNav(station, "");
  let base: PackageBase;
  let decisions: ModelingDecision[] = [];
  try {
    base = await loadPackageBase(station, packageId);
    if (viewer.canReview) {
      decisions = await station.listModelingDecisions(packageId);
    }
  } catch (error) {
    const problem = stationProblem(error);
    return (
      <PageFrame viewer={viewer} nav={await navPromise}>
        {problem}
      </PageFrame>
    );
  }
  const { pkg, address } = base;
  const sources = pkg.files.map((file) => ({
    path: file.path,
    label: `${fileDisplayName(file.path, pkg.captureRecord, file.captureId, file.areaKey)} (${ROLE_LABEL[file.role]})`,
  }));

  return (
    <PageFrame viewer={viewer} nav={await navPromise} selectedDealId={pkg.dealId}>
      <PackageHeading address={address} revision={pkg.revision} captureRecord={pkg.captureRecord} />
      <section className="section" aria-labelledby="decisions-title">
        <h2 id="decisions-title">Modeling decision log</h2>
        {viewer.canReview ? (
          <>
            <DecisionForm packageId={pkg.packageId} sources={sources} action={saveDecision} />
            <DecisionList
              decisions={decisions}
              files={pkg.files}
              captureRecord={pkg.captureRecord}
            />
          </>
        ) : (
          <Notice title="For BIM operators and admins">
            Modeling decisions are read and logged by BIM operators and admins. Your account can see
            the package status only.
          </Notice>
        )}
        <span>
          <a href={`/packages/${pkg.packageId}`}>Back to the package</a>
        </span>
      </section>
    </PageFrame>
  );
}

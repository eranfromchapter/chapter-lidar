// Head of the project page (web-review §6.3, artboard 2i): back link, the project title with
// the latest verdict, the meta line and the HUB and spatial report buttons.

import { Button } from "@/components/hub/Button";
import { BackIcon } from "@/components/hub/icons";
import { VerdictBadge } from "@/components/hub/VerdictBadge";
import { plural } from "@/lib/format";
import { reportDownloadRoute } from "@/lib/files-view";
import type { ProjectHeading } from "@/lib/packages";
import type { PackageSummary } from "@/lib/station-types";

export interface ProjectHeaderProps {
  readonly dealId: string;
  readonly heading: ProjectHeading;
  readonly packageCount: number;
  /** The newest package that has a verdict ("· latest" badge). */
  readonly latestWithVerdict?: PackageSummary;
  /** The newest package whose spatial report is ready (bim, admin). */
  readonly reportPackage?: PackageSummary;
  /** links.hub of the project's packages; null hides "Open in the HUB". */
  readonly hubUrl: string | null;
}

export function ProjectHeader({
  dealId,
  heading,
  packageCount,
  latestWithVerdict,
  reportPackage,
  hubUrl,
}: ProjectHeaderProps) {
  return (
    <>
      <a href="/" className="back-link">
        <BackIcon size={15} />
        Projects
      </a>
      <div className="title-row">
        <div className="title-row__main">
          <div className="title-row__line">
            <h2 className="page-title">{heading.title}</h2>
            {latestWithVerdict === undefined ? null : (
              <VerdictBadge
                status={latestWithVerdict.status}
                outcome={latestWithVerdict.verdict?.outcome}
                suffix=" · latest"
              />
            )}
          </div>
          <div className="meta-row">
            {heading.address === undefined ? null : <span>{heading.address}</span>}
            <span className="mono">deal {dealId}</span>
            {heading.projectManager === undefined ? null : (
              <span>PM {heading.projectManager.name}</span>
            )}
            <span>{plural(packageCount, "package")}</span>
          </div>
        </div>
        {hubUrl === null && reportPackage === undefined ? null : (
          <div className="title-row__actions">
            {hubUrl === null ? null : (
              <Button variant="outline" size="sm" href={hubUrl} external>
                Open in the HUB
              </Button>
            )}
            {reportPackage === undefined ? null : (
              <Button
                variant="primary"
                size="sm"
                href={reportDownloadRoute(reportPackage.packageId)}
                rel="nofollow"
              >
                Spatial report PDF · r{reportPackage.revision}
              </Button>
            )}
          </div>
        )}
      </div>
    </>
  );
}

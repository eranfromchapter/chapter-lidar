// Head of the package page (web-review §6.4.1, artboard 2j): breadcrumb, "{project} · Revision
// {n}" with the verdict and publication badges, the capture meta line and, for bim and admin,
// the plan sheet and spatial report downloads.

import { ruleSetLabel, type Verdict } from "@chapter/capture-contract";
import { Badge } from "@/components/hub/Badge";
import { Button } from "@/components/hub/Button";
import { DownloadIcon } from "@/components/hub/icons";
import { VerdictBadge } from "@/components/hub/VerdictBadge";
import { fileDownloadRoute, reportDownloadRoute } from "@/lib/files-view";
import { formatDate, formatDateTime, formatDateTime24, modeSummary } from "@/lib/format";
import type { StationPackage } from "@/lib/station-types";

export interface PackageHeaderProps {
  readonly pkg: StationPackage;
  readonly title: string;
  readonly verdict: Verdict | null;
  readonly canReview: boolean;
}

function publicationBadge(pkg: StationPackage): string | undefined {
  switch (pkg.publication?.status) {
    case "published":
      return "Published to the HUB";
    case "pending":
    case "publishing":
      return "Publishing to the HUB";
    case "publish_failed":
      return "Not published";
    case undefined:
      return undefined;
  }
}

function MetaRow({
  pkg,
  verdict,
}: {
  readonly pkg: StationPackage;
  readonly verdict: Verdict | null;
}) {
  const record = pkg.captureRecord;
  if (record === undefined) {
    return (
      <div className="meta-row meta-row--tight">
        <span>
          uploading since{" "}
          <time dateTime={pkg.createdAt} title={formatDateTime(pkg.createdAt)}>
            {formatDateTime24(pkg.createdAt)}
          </time>
        </span>
      </div>
    );
  }
  const ids = record.captures.map((capture) => capture.captureId);
  return (
    <div className="meta-row meta-row--tight">
      <span>
        Captured {formatDate(record.visitedAt)} by {record.operator.name}
      </span>
      <span>
        {record.device.marketingName ?? record.device.model} · app {record.app.version}
      </span>
      <span>{modeSummary(record.captures.map((capture) => capture.mode))}</span>
      {pkg.sealedAt === undefined ? null : <span>sealed {formatDate(pkg.sealedAt)}</span>}
      {verdict === null ? null : (
        <span>
          checked{" "}
          <time dateTime={verdict.evaluatedAt} title={formatDateTime(verdict.evaluatedAt)}>
            {formatDateTime24(verdict.evaluatedAt)}
          </time>{" "}
          · rules {ruleSetLabel(verdict.evaluator)}
        </span>
      )}
      <span className="mono">
        {ids.length === 1 ? "capture" : "captures"} {ids.join(", ")}
      </span>
    </div>
  );
}

export function PackageHeader({ pkg, title, verdict, canReview }: PackageHeaderProps) {
  const published = publicationBadge(pkg);
  const sheets = pkg.files.filter((file) => file.role === "plan_pdf" && file.status === "verified");
  const [sheet] = sheets;
  const reportReady = pkg.report?.status === "ready";
  return (
    <>
      <nav className="breadcrumb" aria-label="Breadcrumb">
        <a href="/">Projects</a>
        <span aria-hidden="true">/</span>
        <a href={`/projects/${encodeURIComponent(pkg.dealId)}`}>{title}</a>
        <span aria-hidden="true">/</span>
        <span aria-current="page">Revision {pkg.revision}</span>
      </nav>
      <div className="title-row">
        <div className="title-row__main">
          <div className="title-row__line">
            <h2 className="page-title">
              {title} · Revision {pkg.revision}
            </h2>
            <VerdictBadge status={pkg.status} outcome={verdict?.outcome} variant="solid" />
            {published === undefined ? null : <Badge tone="neutral">{published}</Badge>}
          </div>
          <MetaRow pkg={pkg} verdict={verdict} />
        </div>
        {canReview && (sheet !== undefined || reportReady) ? (
          <div className="title-row__actions">
            {sheet === undefined ? null : (
              <Button
                variant="outline"
                size="sm"
                href={
                  sheets.length === 1 ? fileDownloadRoute(pkg.packageId, sheet.path) : "#documents"
                }
                rel="nofollow"
              >
                Plan sheet PDF
              </Button>
            )}
            {reportReady ? (
              <Button
                variant="primary"
                size="sm"
                href={reportDownloadRoute(pkg.packageId)}
                rel="nofollow"
                iconLeft={<DownloadIcon size={14} />}
              >
                Spatial report PDF
              </Button>
            ) : null}
          </div>
        ) : null}
      </div>
    </>
  );
}

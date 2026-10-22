// "Documents" (web-review §6.4.9 card 4, addenda D3, D8): the station's spatial report, the plan
// sheet of each floor, verdict.json and manifest.json, each a download route of this app or a
// muted row saying when it will exist.

import { Card } from "@/components/hub/Card";
import { fileDownloadRoute, reportDownloadRoute } from "@/lib/files-view";
import { captureLabel, formatBytes, plural } from "@/lib/format";
import type { PackageFile, StationPackage } from "@/lib/station-types";

/** The phone's plan export that writes one Tabloid sheet per floor from version 2.0.0 on. */
const PLAN_SHEET_GENERATOR = "chapter-capture-ios/PlanExport";

/** True when version `a` (x.y.z) is at least `b`. */
export function versionAtLeast(a: string, b: string): boolean {
  const parse = (value: string) =>
    value
      .split(/[.+-]/)
      .slice(0, 3)
      .map((part) => Number.parseInt(part, 10));
  const left = parse(a);
  const right = parse(b);
  for (let index = 0; index < 3; index += 1) {
    const x = left[index] ?? 0;
    const y = right[index] ?? 0;
    if (Number.isNaN(x)) {
      return false;
    }
    if (x !== y) {
      return x > y;
    }
  }
  return true;
}

/** Right text of a plan sheet row (D8). */
export function planSheetDetail(file: PackageFile): string {
  return file.generator === PLAN_SHEET_GENERATOR &&
    file.generatorVersion !== undefined &&
    versionAtLeast(file.generatorVersion, "2.0.0")
    ? "Tabloid · 1 sheet · from the phone"
    : `${formatBytes(file.bytes)} · from the phone`;
}

function LinkRow({
  name,
  detail,
  href,
}: {
  readonly name: string;
  readonly detail: string;
  readonly href: string;
}) {
  return (
    <a className="doc-row" href={href} rel="nofollow">
      <span className="doc-row__name">{name}</span>
      <span className="doc-row__detail">{detail}</span>
    </a>
  );
}

function MutedRow({ name, detail }: { readonly name: string; readonly detail: string }) {
  return (
    <div className="doc-row">
      <span className="doc-row__name doc-row__name--muted">{name}</span>
      <span className="doc-row__detail">{detail}</span>
    </div>
  );
}

function reportPending(pkg: StationPackage, stopped: boolean): string {
  if (stopped) {
    return "not checked";
  }
  if (pkg.verdict === undefined || pkg.report === undefined) {
    return "after the checks";
  }
  return pkg.report.status === "failed" ? "not generated · ask an admin" : "being generated";
}

export interface DocumentsCardProps {
  readonly pkg: StationPackage;
  /** An upload the phone stopped and replaced: its documents never come ("not checked"). */
  readonly stopped?: boolean;
}

export function DocumentsCard({ pkg, stopped = false }: DocumentsCardProps) {
  const report = pkg.report;
  const sheets = pkg.files.filter((file) => file.role === "plan_pdf" && file.status === "verified");
  const several = sheets.length > 1;
  return (
    <Card padding="md" label="Documents" id="documents">
      <div className="hub-stack hub-stack--10">
        <span className="hub-eyebrow">Documents</span>
        <div>
          {report?.status === "ready" ? (
            <LinkRow
              name="Spatial report PDF"
              detail={[
                report.pages === undefined ? undefined : plural(report.pages, "page"),
                report.bytes === undefined ? undefined : formatBytes(report.bytes),
              ]
                .filter((part) => part !== undefined)
                .join(" · ")}
              href={reportDownloadRoute(pkg.packageId)}
            />
          ) : (
            <MutedRow name="Spatial report PDF" detail={reportPending(pkg, stopped)} />
          )}
          {sheets.map((sheet) => (
            <LinkRow
              key={sheet.path}
              name={`Plan sheet PDF${
                several
                  ? ` · ${captureLabel(pkg.captureRecord, sheet.captureId, sheet.areaKey) ?? ""}`
                  : ""
              }`}
              detail={planSheetDetail(sheet)}
              href={fileDownloadRoute(pkg.packageId, sheet.path)}
            />
          ))}
          {pkg.verdict === undefined ? (
            <MutedRow name="verdict.json" detail={stopped ? "not checked" : "after the checks"} />
          ) : (
            <LinkRow
              name="verdict.json"
              detail="station"
              href={`/packages/${encodeURIComponent(pkg.packageId)}/verdict.json`}
            />
          )}
          {pkg.manifestFile === undefined ? (
            <MutedRow name="manifest.json" detail={stopped ? "not sealed" : "after sealing"} />
          ) : (
            <LinkRow
              name="manifest.json"
              detail={`${plural(pkg.manifest?.files.length ?? pkg.totals.files, "entry", "entries")} · SHA-256`}
              href={fileDownloadRoute(pkg.packageId, pkg.manifestFile.path)}
            />
          )}
        </div>
      </div>
    </Card>
  );
}

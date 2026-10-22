// The project's packages table (web-review §6.3.1, addendum D7): one row per revision the
// station knows, newest first, and above a sealed revision the revision the phone is preparing
// ("Revision 2 · not sealed · on the phone").

import { Button } from "@/components/hub/Button";
import { Card } from "@/components/hub/Card";
import { VerdictBadge } from "@/components/hub/VerdictBadge";
import { HubCell } from "@/components/HubCell";
import { Phrases } from "@/components/Phrases";
import { dayLabel, formatDateTime, formatDateTime24 } from "@/lib/format";
import { replacedBy } from "@/lib/packages";
import { checkedAt, contentsLine, packageSubLine } from "@/lib/project-view";
import { capturedText, hubText } from "@/lib/review";
import { noticeCompactLine } from "@/lib/revision-diff";
import type { NextRevisionNotice, PackageSummary } from "@/lib/station-types";

export interface PackagesTableProps {
  readonly packages: readonly PackageSummary[];
  /** The phone's next-revision notice per sealed packageId. */
  readonly notices: ReadonlyMap<string, NextRevisionNotice>;
  /** The compact diff line per packageId of a station revision > 1 without a verdict. */
  readonly diffLines: ReadonlyMap<string, string>;
  readonly now: Date;
}

const HEADERS = ["Package", "Verdict", "Captured", "Checked", "Contents", "In the HUB"];

function NoticeRow({ notice, now }: { readonly notice: NextRevisionNotice; readonly now: Date }) {
  const day = dayLabel(notice.updatedAt, now);
  return (
    <tr data-revision={notice.revision} data-on-phone="true">
      <td>
        <div className="hub-cell-title nowrap">Revision {notice.revision}</div>
        <div className="hub-cell-sub">not sealed · on the phone</div>
      </td>
      <td>
        <VerdictBadge status="uploading" />
      </td>
      <td>{notice.updatedBy === undefined ? day : `${day} · ${notice.updatedBy}`}</td>
      <td className="hub-table__muted">—</td>
      <td>
        <Phrases text={noticeCompactLine(notice.changes)} maxNowrap={12} />
      </td>
      <td className="hub-table__muted">—</td>
      <td className="hub-table__action" />
    </tr>
  );
}

function PackageRow({
  pkg,
  packages,
  diffLine,
  now,
}: {
  readonly pkg: PackageSummary;
  readonly packages: readonly PackageSummary[];
  readonly diffLine: string | undefined;
  readonly now: Date;
}) {
  const sub = packageSubLine(pkg, packages);
  const stopped = replacedBy(packages, pkg) !== undefined;
  const checked = checkedAt(pkg);
  const hub = hubText(pkg);
  return (
    <tr data-package={pkg.packageId} data-revision={pkg.revision}>
      <td>
        <div className="hub-cell-title nowrap">Revision {pkg.revision}</div>
        <div className="hub-cell-sub">
          {sub.prefix}
          {sub.mono ? (
            <span className="mono" title={sub.title}>
              {sub.text}
            </span>
          ) : (
            sub.text
          )}
        </div>
      </td>
      <td>
        <VerdictBadge status={pkg.status} outcome={pkg.verdict?.outcome} stopped={stopped} />
      </td>
      <td>{capturedText(pkg, now)}</td>
      <td className={checked === undefined ? "hub-table__muted" : undefined}>
        {checked === undefined ? (
          "—"
        ) : (
          <time dateTime={checked} title={formatDateTime(checked)}>
            {formatDateTime24(checked)}
          </time>
        )}
      </td>
      <td>
        <Phrases text={diffLine ?? contentsLine(pkg)} maxNowrap={12} />
      </td>
      <HubCell hub={hub} />
      <td className="hub-table__action">
        <Button
          variant="outline"
          size="sm"
          href={`/packages/${encodeURIComponent(pkg.packageId)}`}
          aria-label={`Open revision ${pkg.revision}`}
        >
          Open
        </Button>
      </td>
    </tr>
  );
}

export function PackagesTable({ packages, notices, diffLines, now }: PackagesTableProps) {
  return (
    <Card padding="none" table label="Packages">
      <div className="hub-card__scroll">
        <table className="hub-table">
          <thead>
            <tr>
              {HEADERS.map((header) => (
                <th key={header} scope="col">
                  {header}
                </th>
              ))}
              <th scope="col">
                <span className="visually-hidden">Open</span>
              </th>
            </tr>
          </thead>
          <tbody>
            {packages.length === 0 ? (
              <tr>
                <td colSpan={7} className="hub-table__message">
                  No capture packages for this project yet.
                </td>
              </tr>
            ) : (
              packages.flatMap((pkg) => {
                const notice = notices.get(pkg.packageId);
                const rows = [
                  <PackageRow
                    key={pkg.packageId}
                    pkg={pkg}
                    packages={packages}
                    diffLine={diffLines.get(pkg.packageId)}
                    now={now}
                  />,
                ];
                if (notice !== undefined) {
                  rows.unshift(
                    <NoticeRow key={`${pkg.packageId}:next`} notice={notice} now={now} />,
                  );
                }
                return rows;
              })
            )}
          </tbody>
        </table>
      </div>
    </Card>
  );
}

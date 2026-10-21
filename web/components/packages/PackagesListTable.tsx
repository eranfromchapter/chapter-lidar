// The Packages list (web-review §6.2): every package revision the station has, newest first,
// with its project, verdict, capture, check and HUB state. An upload the phone replaced with a
// newer revision of the same visit is labelled as on the project and package pages.

import type { ReactNode } from "react";
import { Button } from "@/components/hub/Button";
import { Card } from "@/components/hub/Card";
import { EmptyState } from "@/components/hub/EmptyState";
import { VerdictBadge } from "@/components/hub/VerdictBadge";
import { HubCell } from "@/components/HubCell";
import { Phrases } from "@/components/Phrases";
import { formatDateTime, formatDateTime24, shortId } from "@/lib/format";
import { replacedBy, uploadStoppedText } from "@/lib/packages";
import { capturedText, hubText, projectTitle } from "@/lib/review";
import type { ReviewPackage } from "@/lib/station-types";

export interface PackagesListTableProps {
  readonly packages: readonly ReviewPackage[];
  readonly query: string;
  readonly truncated: boolean;
  readonly now: Date;
}

const HEADERS = ["Package", "Verdict", "Captured", "Checked", "In the HUB"];

function Row({
  pkg,
  packages,
  now,
}: {
  readonly pkg: ReviewPackage;
  readonly packages: readonly ReviewPackage[];
  readonly now: Date;
}) {
  const title = projectTitle(pkg);
  const hub = hubText(pkg);
  const first = pkg.captures[0];
  const checked = pkg.verdict?.evaluatedAt;
  const successor = replacedBy(packages, pkg);
  let detail: ReactNode = null;
  if (successor !== undefined) {
    detail = ` · ${uploadStoppedText(successor)}`;
  } else if (first !== undefined) {
    detail = (
      <>
        {" · "}
        <span className="mono" title={pkg.captures.map((item) => item.captureId).join(", ")}>
          capture {shortId(first.captureId)}
          {pkg.captures.length > 1 ? ` +${pkg.captures.length - 1}` : ""}
        </span>
      </>
    );
  }
  return (
    <tr data-package={pkg.packageId}>
      <td className="hub-table__name">
        <div className="hub-cell-title">{title}</div>
        <div className="hub-cell-sub">
          Revision {pkg.revision}
          {detail}
        </div>
      </td>
      <td>
        <VerdictBadge
          status={pkg.status}
          outcome={pkg.verdict?.outcome}
          stopped={successor !== undefined}
        />
      </td>
      <td>
        <Phrases text={capturedText(pkg, now)} />
      </td>
      <td className={checked === undefined ? "hub-table__muted" : undefined}>
        {checked === undefined ? (
          "—"
        ) : (
          <time dateTime={checked} title={formatDateTime(checked)}>
            {formatDateTime24(checked)}
          </time>
        )}
      </td>
      <HubCell hub={hub} />
      <td className="hub-table__action">
        <Button
          variant="outline"
          size="sm"
          href={`/packages/${encodeURIComponent(pkg.packageId)}`}
          aria-label={`Open ${title} · Revision ${pkg.revision}`}
        >
          Open
        </Button>
      </td>
    </tr>
  );
}

export function PackagesListTable({ packages, query, truncated, now }: PackagesListTableProps) {
  if (packages.length === 0) {
    return (
      <Card padding="none" table>
        {query.length > 0 ? (
          <EmptyState
            title={`No package matches “${query}”`}
            body="Search by address, deal or capture id."
            action={
              <Button variant="ghost" size="sm" href="/packages">
                Clear search
              </Button>
            }
          />
        ) : (
          <EmptyState
            title="No capture packages yet"
            body="Packages appear here when the Chapter Capture app uploads a sealed capture."
          />
        )}
      </Card>
    );
  }
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
            {packages.map((pkg) => (
              <Row key={pkg.packageId} pkg={pkg} packages={packages} now={now} />
            ))}
          </tbody>
        </table>
      </div>
      {truncated ? (
        <div className="hub-table__footer">
          Showing the {packages.length} newest packages. Search by address, deal or capture id to
          find others.
        </div>
      ) : null}
    </Card>
  );
}

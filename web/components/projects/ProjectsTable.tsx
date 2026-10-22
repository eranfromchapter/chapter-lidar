// The Projects table (web-review §6.1, artboard 2h): one row per project with its newest
// package, verdict, floors, capture and HUB state; the empty, no-match and empty-tab states.

import { Button } from "@/components/hub/Button";
import { Card } from "@/components/hub/Card";
import { EmptyState } from "@/components/hub/EmptyState";
import { ProgressBar } from "@/components/hub/ProgressBar";
import { VerdictBadge } from "@/components/hub/VerdictBadge";
import { HubCell } from "@/components/HubCell";
import { Phrases } from "@/components/Phrases";
import {
  capturedText,
  emptyTabText,
  hubText,
  latestPackageText,
  projectTitle,
  type ProjectTab,
} from "@/lib/review";
import type { ReviewProject } from "@/lib/station-types";

export interface ProjectsTableProps {
  /** The projects of the selected tab. */
  readonly projects: readonly ReviewProject[];
  /** How many projects the station returned (all tabs). */
  readonly total: number;
  readonly tab: ProjectTab;
  readonly query: string;
  readonly truncated: boolean;
  readonly now: Date;
}

const HEADERS = ["Project", "Latest package", "Verdict", "Floors", "Captured", "In the HUB"];

function Row({ project, now }: { readonly project: ReviewProject; readonly now: Date }) {
  const title = projectTitle(project);
  const latest = project.latest;
  const pkg = latestPackageText(latest);
  const hub = hubText(latest);
  return (
    <tr data-deal={project.dealId}>
      <td className="hub-table__name">
        <div className="hub-cell-title">{title}</div>
        <div className="hub-cell-sub mono">deal {project.dealId}</div>
      </td>
      <td>
        <div>
          <Phrases text={pkg.text} />
        </div>
        {pkg.percent === undefined ? null : (
          <ProgressBar size="table" value={pkg.percent} label={`Upload ${pkg.percent}%`} />
        )}
      </td>
      <td>
        <VerdictBadge status={latest.status} outcome={latest.verdict?.outcome} />
      </td>
      <td className={latest.captures.length === 0 ? "hub-table__muted" : undefined}>
        {latest.captures.length === 0 ? "—" : latest.captures.length}
      </td>
      <td>
        <Phrases text={capturedText(latest, now)} />
      </td>
      <HubCell hub={hub} />
      <td className="hub-table__action">
        <Button
          variant="outline"
          size="sm"
          href={`/projects/${encodeURIComponent(project.dealId)}`}
          aria-label={`Open ${title}`}
        >
          Open
        </Button>
      </td>
    </tr>
  );
}

export function ProjectsTable({ projects, total, tab, query, truncated, now }: ProjectsTableProps) {
  if (total === 0) {
    return (
      <Card padding="none" table>
        {query.length > 0 ? (
          <EmptyState
            title={`No project matches “${query}”`}
            body="Search by address, deal or capture id."
            action={
              <Button variant="ghost" size="sm" href="/">
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
    <Card padding="none" table label="Projects">
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
            {projects.length === 0 && tab !== "all" ? (
              <tr>
                <td colSpan={7} className="hub-table__message">
                  {emptyTabText(tab)}
                </td>
              </tr>
            ) : (
              projects.map((project) => <Row key={project.dealId} project={project} now={now} />)
            )}
          </tbody>
        </table>
      </div>
      {truncated ? (
        <div className="hub-table__footer">
          Showing the {total} most recently active projects. Search by address, deal or capture id
          to find others.
        </div>
      ) : null}
    </Card>
  );
}

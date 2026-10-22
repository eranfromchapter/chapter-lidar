// The project's "Decision log" tab (web-review §6.3.2): every decision on every revision of the
// project, newest first, each with its revision.

import { Card } from "@/components/hub/Card";
import { DecisionList, type DecisionEntry } from "@/components/DecisionList";
import { plural } from "@/lib/format";

export interface ProjectDecisionLogProps {
  /** Newest first. */
  readonly entries: readonly DecisionEntry[];
  /** The newest package of the project, where a new decision is logged. */
  readonly newest?: { readonly packageId: string; readonly revision: number };
}

export function ProjectDecisionLog({ entries, newest }: ProjectDecisionLogProps) {
  return (
    <Card padding="md" labelledBy="project-log-title">
      <div className="hub-stack hub-stack--16">
        <div className="card-head card-head--center">
          <h3 className="card-title" id="project-log-title">
            Modeling decision log
          </h3>
          <span className="table-head__meta">
            {plural(entries.length, "entry", "entries")} · newest first
          </span>
        </div>
        <DecisionList entries={entries} />
        {newest === undefined ? null : (
          <a
            className="text-13"
            href={`/packages/${encodeURIComponent(newest.packageId)}#decisions`}
          >
            Log a decision on revision {newest.revision} →
          </a>
        )}
      </div>
    </Card>
  );
}

// Logged modeling decisions (web-review §6.4.7): "<b>element</b> — decision · from {sources} ·
// {note}" with the author and the station's time. Used on the package page (oldest first), the
// project's log tab (with a revision badge) and the global log (with a link to the package).

import { formatDateTime, formatDateTime24 } from "@/lib/format";
import { sourceText, type DecisionContext } from "@/lib/decisions";
import type { ModelingDecision } from "@/lib/station-types";
import { Badge } from "./hub/Badge";

export interface DecisionEntry {
  readonly decision: ModelingDecision;
  /** What is known about the decision's package, to word its sources. */
  readonly context?: DecisionContext;
  /** "Revision {n}" badge before the element (project log). */
  readonly revision?: number;
  /** A link line above the entry (global log): "{project title} · Revision {n}". */
  readonly link?: { readonly text: string; readonly href: string };
}

export interface DecisionListProps {
  readonly entries: readonly DecisionEntry[];
  readonly label?: string;
}

export function DecisionList({ entries, label = "Logged decisions" }: DecisionListProps) {
  if (entries.length === 0) {
    return (
      <p className="text-13 text-muted" style={{ margin: 0 }}>
        No decisions logged yet.
      </p>
    );
  }
  return (
    <ul className="decision-list" aria-label={label}>
      {entries.map(({ decision, context, revision, link }) => (
        <li key={decision.decisionId} className="decision-entry">
          <div className="decision-entry__body">
            {link === undefined ? null : (
              <a className="decision-entry__context" href={link.href}>
                {link.text}
              </a>
            )}
            <span>
              {revision === undefined ? null : (
                <span className="decision-entry__badge">
                  <Badge tone="neutral">Revision {revision}</Badge>
                </span>
              )}
              <b>{decision.element}</b> — {decision.decision}
              <span className="decision-entry__muted">
                {" · from "}
                {sourceText(decision, context)}
                {decision.note === undefined ? "" : ` · ${decision.note}`}
              </span>
            </span>
          </div>
          <span className="decision-entry__meta">
            {decision.decidedBy.name} ·{" "}
            <time dateTime={decision.decidedAt} title={formatDateTime(decision.decidedAt)}>
              {formatDateTime24(decision.decidedAt)}
            </time>
          </span>
        </li>
      ))}
    </ul>
  );
}

// The project's decision log in short (web-review §6.3.3): the two newest entries and a link to
// the log tab.

import { Button } from "@/components/hub/Button";
import { Card } from "@/components/hub/Card";
import { formatDateTime, formatDateTime24, plural } from "@/lib/format";
import type { ModelingDecision } from "@/lib/station-types";

export interface DecisionSummaryCardProps {
  /** Every decision of the project, newest first. */
  readonly decisions: readonly ModelingDecision[];
  readonly logHref: string;
}

export function DecisionSummaryCard({ decisions, logHref }: DecisionSummaryCardProps) {
  const newest = decisions.slice(0, 2);
  return (
    <Card padding="md" label="Decision log">
      <div className="hub-stack hub-stack--12">
        <span className="hub-eyebrow">
          Decision log · {plural(decisions.length, "entry", "entries")}
        </span>
        {newest.length === 0 ? (
          <span className="text-13 text-muted">No decisions logged yet.</span>
        ) : (
          <>
            {newest.map((decision) => (
              <div key={decision.decisionId} className="entry">
                <span className="text-13 text-strong">
                  <b>{decision.element}</b> — {decision.decision}
                </span>
                <span className="text-12 text-muted">
                  {decision.decidedBy.name} ·{" "}
                  <time dateTime={decision.decidedAt} title={formatDateTime(decision.decidedAt)}>
                    {formatDateTime24(decision.decidedAt)}
                  </time>
                </span>
              </div>
            ))}
            <span>
              <Button variant="ghost" size="sm" href={logHref}>
                All entries →
              </Button>
            </span>
          </>
        )}
      </div>
    </Card>
  );
}

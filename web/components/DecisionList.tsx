import type { CaptureRecord } from "@chapter/capture-contract";
import { formatDateTime, pathDisplayName } from "@/lib/format";
import type { ModelingDecision, PackageFile } from "@/lib/station-types";

export interface DecisionListProps {
  readonly decisions: readonly ModelingDecision[];
  readonly files: readonly PackageFile[];
  readonly captureRecord: CaptureRecord | undefined;
}

function sourceText(
  decision: ModelingDecision,
  files: readonly PackageFile[],
  record: CaptureRecord | undefined,
): string {
  return decision.sources
    .map((source) => {
      const name = pathDisplayName(source.path, files, record);
      const detail = source.controlId ?? source.elementId;
      return detail === undefined ? name : `${name} (${detail})`;
    })
    .join(" + ");
}

/** Logged decisions, oldest first, each with its author and time as recorded by the station. */
export function DecisionList({ decisions, files, captureRecord }: DecisionListProps) {
  return (
    <ul className="decision-list" aria-label="Logged decisions">
      {decisions.length === 0 ? (
        <li className="decision-list__empty">No decisions logged yet.</li>
      ) : (
        decisions.map((decision) => (
          <li key={decision.decisionId} className="decision-list__item">
            <div className="decision-list__body">
              <span>
                <b>{decision.element}</b> — {decision.decision}
              </span>
              <span className="caption">Source: {sourceText(decision, files, captureRecord)}</span>
              {decision.note === undefined ? null : (
                <span className="caption">Uncertainty and next check: {decision.note}</span>
              )}
            </div>
            <span className="decision-list__meta">
              {decision.decidedBy.name} ·{" "}
              <time dateTime={decision.decidedAt}>{formatDateTime(decision.decidedAt)}</time>
            </span>
          </li>
        ))
      )}
    </ul>
  );
}

// The verdict card of the package page (web-review §6.4.2, addendum D7): the headline in the
// report's words with its shape, the summary, the check counts, the contract's statement, the
// limitations and next actions, and what a newer revision is doing.

import {
  checkCounts,
  checkRows,
  countsLine,
  OUTCOME_WORD,
  verdictHeadline,
  type Verdict,
} from "@chapter/capture-contract";
import type { ReactNode } from "react";
import { Card } from "@/components/hub/Card";
import { OUTCOME_GLYPH, StatusGlyph } from "@/components/hub/StatusGlyph";
import { VerdictBadge } from "@/components/hub/VerdictBadge";
import { inProgressLine } from "@/lib/revision-diff";
import type { CaptureRecord, NextRevisionNotice, PackageSummary } from "@/lib/station-types";

export interface VerdictCardProps {
  readonly verdict: Verdict;
  readonly captureRecord: CaptureRecord | undefined;
  /** The revision the phone is preparing on top of this package. */
  readonly nextRevision?: NextRevisionNotice;
  /** The newest station revision of the same visit above this one. */
  readonly newer?: PackageSummary;
}

function NewerNote({ newer }: { readonly newer: PackageSummary }) {
  const href = `/packages/${encodeURIComponent(newer.packageId)}`;
  let text: ReactNode;
  if (newer.status === "uploading") {
    text = `Revision ${newer.revision} is uploading from the phone.`;
  } else if (newer.verdict === undefined) {
    text = `Revision ${newer.revision} is being checked.`;
  } else {
    text = (
      <>
        Revision {newer.revision} has a newer verdict:{" "}
        <VerdictBadge status={newer.status} outcome={newer.verdict.outcome} />
      </>
    );
  }
  return (
    <>
      <span className="text-12 text-muted" style={{ marginTop: 4 }}>
        {text}
      </span>
      <a className="text-13" href={href}>
        Open revision {newer.revision} →
      </a>
    </>
  );
}

export function VerdictCard({ verdict, captureRecord, nextRevision, newer }: VerdictCardProps) {
  const rows = checkRows(verdict, captureRecord);
  return (
    <Card
      padding="md"
      label={`Verdict: ${OUTCOME_WORD[verdict.outcome]}`}
      dataOutcome={verdict.outcome}
    >
      <div className="verdict-grid">
        <div className="hub-stack hub-stack--8">
          <div className={`verdict-headline tone-${verdict.outcome}`}>
            <StatusGlyph kind={OUTCOME_GLYPH[verdict.outcome]} size={16} />
            {verdictHeadline(verdict)}
          </div>
          <span className="text-14 text-strong">{verdict.summary}</span>
          <span className="text-13 text-muted">{countsLine(checkCounts(rows))}</span>
          <span className="text-12 text-muted push-down">{verdict.statement}</span>
        </div>
        <div className="hub-stack hub-stack--6">
          <span className="hub-eyebrow hub-eyebrow--sm">Limitations</span>
          {verdict.limitations.length === 0 ? (
            <span className="text-13 text-strong">None.</span>
          ) : (
            verdict.limitations.map((limitation, index) => (
              <span key={index} className="text-13 text-strong">
                {limitation}
              </span>
            ))
          )}
        </div>
        <div className="hub-stack hub-stack--6">
          <span className="hub-eyebrow hub-eyebrow--sm">Next actions</span>
          {verdict.nextActions.length === 0 ? (
            <span className="text-13 text-strong">None.</span>
          ) : (
            verdict.nextActions.map((action, index) => (
              <span key={index} className="text-13 text-strong">
                {action}
              </span>
            ))
          )}
          {nextRevision !== undefined ? (
            <span className="text-12 text-muted" style={{ marginTop: 4 }}>
              {inProgressLine(nextRevision, verdict)}
            </span>
          ) : newer !== undefined ? (
            <NewerNote newer={newer} />
          ) : null}
        </div>
      </div>
    </Card>
  );
}

// "Latest verdict" (web-review §6.3.3): the newest verdict of the project in words and shape,
// with its limitations and next actions.

import { OUTCOME_WORD, type Verdict } from "@chapter/capture-contract";
import { Button } from "@/components/hub/Button";
import { Card } from "@/components/hub/Card";
import { OUTCOME_GLYPH, StatusGlyph } from "@/components/hub/StatusGlyph";

export interface LatestVerdictCardProps {
  /** The newest package with a verdict, and its verdict; undefined when none has one. */
  readonly latest?: {
    readonly packageId: string;
    readonly revision: number;
    readonly verdict: Verdict;
  };
  /** bim, admin: "Capture checks →". */
  readonly canReview: boolean;
}

export function LatestVerdictCard({ latest, canReview }: LatestVerdictCardProps) {
  if (latest === undefined) {
    return (
      <Card padding="md" label="Latest verdict">
        <div className="hub-stack hub-stack--12">
          <span className="hub-eyebrow">Latest verdict</span>
          <span className="text-14 text-muted">
            No verdict yet. The station checks a package after it is sealed.
          </span>
        </div>
      </Card>
    );
  }
  const { verdict } = latest;
  return (
    <Card padding="md" label={`Latest verdict: ${OUTCOME_WORD[verdict.outcome]}`}>
      <div className="hub-stack hub-stack--12">
        <span className="hub-eyebrow">Latest verdict · revision {latest.revision}</span>
        <div className={`verdict-word tone-${verdict.outcome}`}>
          <StatusGlyph kind={OUTCOME_GLYPH[verdict.outcome]} size={14} />
          {OUTCOME_WORD[verdict.outcome]}
        </div>
        <span className="text-14 text-strong">{verdict.summary}</span>
        {verdict.limitations.length === 0 ? null : (
          <div className="hub-stack hub-stack--6">
            <span className="group-title">Limitations</span>
            {verdict.limitations.map((limitation, index) => (
              <span key={index} className="text-13">
                {limitation}
              </span>
            ))}
          </div>
        )}
        {verdict.nextActions.length === 0 ? null : (
          <div className="hub-stack hub-stack--6">
            <span className="group-title">Next actions</span>
            {verdict.nextActions.map((action, index) => (
              <span key={index} className="text-13">
                {action}
              </span>
            ))}
          </div>
        )}
        {canReview ? (
          <span>
            <Button
              variant="ghost"
              size="sm"
              href={`/packages/${encodeURIComponent(latest.packageId)}#checks`}
            >
              Capture checks →
            </Button>
          </span>
        ) : null}
      </div>
    </Card>
  );
}

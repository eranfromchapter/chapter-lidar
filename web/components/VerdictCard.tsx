import type { Verdict } from "@chapter/capture-contract";
import { OUTCOME, outcomeHeadline, plural } from "@/lib/format";

export interface VerdictCardProps {
  readonly verdict: Verdict;
}

/** Outcome in plain words, the station's summary and the counts (screen-review verdict card). */
export function VerdictCard({ verdict }: VerdictCardProps) {
  const blockers = verdict.findings.filter((finding) => finding.severity === "blocker").length;
  const limitations = verdict.findings.filter(
    (finding) => finding.severity === "limitation",
  ).length;
  const passed = verdict.checks.filter((check) => check.status === "passed").length;
  return (
    <section
      aria-label={`Verdict: ${OUTCOME[verdict.outcome].word}`}
      className={`verdict verdict--${verdict.outcome}`}
      data-outcome={verdict.outcome}
    >
      <div className="verdict__text">
        <span className={`verdict__headline tone-${verdict.outcome}`}>
          {outcomeHeadline(verdict.outcome)}
        </span>
        <span className="verdict__summary">{verdict.summary}</span>
        {verdict.limitations.length > 0 ? (
          <ul className="verdict__list" aria-label="Named limitations">
            {verdict.limitations.map((limitation, index) => (
              <li key={index}>{limitation}</li>
            ))}
          </ul>
        ) : null}
        {verdict.nextActions.length > 0 ? (
          <ul className="verdict__list" aria-label="Next actions">
            {verdict.nextActions.map((action, index) => (
              <li key={index}>Next: {action}</li>
            ))}
          </ul>
        ) : null}
      </div>
      <span className="verdict__counts">
        {plural(blockers, "blocker")} · {plural(limitations, "limitation")} · {passed} passed
      </span>
    </section>
  );
}

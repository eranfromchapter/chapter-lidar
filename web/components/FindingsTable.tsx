import type { CaptureRecord, Severity, Verdict } from "@chapter/capture-contract";
import {
  pathDisplayName,
  SEVERITY_GROUP,
  SEVERITY_ORDER,
  severityLabel,
  severityTone,
} from "@/lib/format";
import type { PackageFile } from "@/lib/station-types";

export interface FindingsTableProps {
  readonly verdict: Verdict;
  readonly files: readonly PackageFile[];
  readonly captureRecord: CaptureRecord | undefined;
}

/**
 * Every finding of the verdict, grouped by severity (blockers, limitations, information), with
 * its rule, source file, measured and expected values and next action.
 */
export function FindingsTable({ verdict, files, captureRecord }: FindingsTableProps) {
  const titles = new Map(verdict.checks.map((check) => [check.ruleId, check]));
  const groups = SEVERITY_ORDER.map((severity: Severity) => ({
    severity,
    findings: verdict.findings.filter((finding) => finding.severity === severity),
  })).filter((group) => group.findings.length > 0);

  return (
    <section className="section" aria-labelledby="findings-title">
      <h2 id="findings-title">Findings</h2>
      <div className="table-card">
        <table className="table">
          <thead>
            <tr>
              <th scope="col">Severity</th>
              <th scope="col">Rule</th>
              <th scope="col">Source</th>
              <th scope="col">Measured</th>
              <th scope="col">Next action</th>
            </tr>
          </thead>
          {groups.length === 0 ? (
            <tbody>
              <tr>
                <td colSpan={5} className="caption">
                  The station reported no findings.
                </td>
              </tr>
            </tbody>
          ) : (
            groups.map((group) => (
              <tbody key={group.severity} aria-label={SEVERITY_GROUP[group.severity]}>
                {group.findings.map((finding, index) => {
                  const check = titles.get(finding.ruleId);
                  return (
                    <tr key={`${finding.ruleId}-${index}`} data-severity={finding.severity}>
                      <td className={`table__severity tone-${severityTone(finding.severity)}`}>
                        {severityLabel(finding.severity, check?.status === "passed")}
                      </td>
                      <td>
                        {check?.title ?? finding.ruleId}
                        <span className="table__sub">{finding.message}</span>
                      </td>
                      <td>
                        {finding.filePath === undefined
                          ? "Package"
                          : pathDisplayName(finding.filePath, files, captureRecord)}
                      </td>
                      <td>
                        {finding.measured ?? "—"}
                        {finding.expected === undefined ? null : (
                          <span className="table__sub">Expected: {finding.expected}</span>
                        )}
                      </td>
                      <td>{finding.nextAction}</td>
                    </tr>
                  );
                })}
              </tbody>
            ))
          )}
        </table>
      </div>
      <span className="caption">
        Exports from the same capture agreeing with each other are not counted as independent
        measurements.
      </span>
      <span className="caption">{verdict.statement}</span>
    </section>
  );
}

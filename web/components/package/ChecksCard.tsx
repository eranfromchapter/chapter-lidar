// "Capture checks" (web-review §6.4.5, R-15c): every rule the station ran, in the spatial
// report's words (contract checkRows), Blocked > Limited > Passed > Not applicable.

import { checkRows, sortCheckRows, type CheckRow, type Verdict } from "@chapter/capture-contract";
import { Badge } from "@/components/hub/Badge";
import { Card } from "@/components/hub/Card";
import { StatusGlyph } from "@/components/hub/StatusGlyph";
import { formatDateTime, formatDateTime24, plural } from "@/lib/format";
import type { CaptureRecord, ReportSummary } from "@/lib/station-types";

export interface ChecksCardProps {
  readonly verdict: Verdict;
  readonly captureRecord: CaptureRecord | undefined;
  readonly report?: ReportSummary;
}

function ResultBadge({ row }: { readonly row: CheckRow }) {
  return (
    <Badge tone={row.tone}>
      <StatusGlyph kind={row.glyph} />
      {row.word}
    </Badge>
  );
}

export function ChecksCard({ verdict, captureRecord, report }: ChecksCardProps) {
  const rows = sortCheckRows(checkRows(verdict, captureRecord));
  const page =
    report?.status === "ready" && report.checksPage !== undefined
      ? `same table as page ${report.checksPage} of the spatial report`
      : "same table as the spatial report";
  return (
    <Card padding="none" table labelledBy="checks-title" id="checks">
      <div className="table-head table-head--checks">
        <h3 className="card-title" id="checks-title">
          Capture checks
        </h3>
        <span className="table-head__meta">
          {plural(rows.length, "rule")} · evaluated{" "}
          <time dateTime={verdict.evaluatedAt} title={formatDateTime(verdict.evaluatedAt)}>
            {formatDateTime24(verdict.evaluatedAt)}
          </time>{" "}
          · {page}
        </span>
      </div>
      <div className="hub-card__scroll">
        <table className="hub-table hub-table--compact">
          {/* "What was found" carries the most text; the other columns take what they need. */}
          <colgroup>
            <col style={{ width: "22%" }} />
            <col style={{ width: "16%" }} />
            <col style={{ width: "42%" }} />
            <col style={{ width: "20%" }} />
          </colgroup>
          <thead>
            <tr>
              <th scope="col">Check</th>
              <th scope="col">Result</th>
              <th scope="col">What was found</th>
              <th scope="col">Next action</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((row) => (
              <tr key={row.ruleId} data-result={row.result} data-rule={row.ruleId}>
                <td>
                  <div className="hub-cell-title">{row.title}</div>
                  <div className="hub-cell-sub mono">{row.ruleId}</div>
                </td>
                <td>
                  <ResultBadge row={row} />
                </td>
                <td>
                  {row.found.length === 0 ? (
                    "—"
                  ) : (
                    <div className="hub-cell-lines">
                      {row.found.map((block, index) => (
                        <div key={index}>
                          <div>{block.message}</div>
                          {block.values === undefined ? null : (
                            <div className="hub-cell-sub">{block.values}</div>
                          )}
                        </div>
                      ))}
                    </div>
                  )}
                </td>
                <td>
                  {row.nextActions.length === 0 ? (
                    <span className="text-muted">None</span>
                  ) : (
                    <div className="hub-cell-lines">
                      {row.nextActions.map((action) => (
                        <div key={action}>{action}</div>
                      ))}
                    </div>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <div className="checks-footer">
        Every rule the station ran is listed. Exports of one scan that agree with each other are not
        independent measurements.
      </div>
    </Card>
  );
}

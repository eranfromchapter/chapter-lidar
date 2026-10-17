import type { CaptureRecord } from "@chapter/capture-contract";
import { formatDate, modeSummary } from "@/lib/format";

export interface PackageHeadingProps {
  readonly address: string;
  readonly revision: number;
  readonly captureRecord: CaptureRecord | undefined;
}

/** "618 Valley Street · revision 1" and the capture record line under it. */
export function PackageHeading({ address, revision, captureRecord }: PackageHeadingProps) {
  return (
    <div className="page-title">
      <h1>
        {address} · revision {revision}
      </h1>
      {captureRecord === undefined ? (
        <span className="page-title__meta">
          The capture record is available once the package is sealed.
        </span>
      ) : (
        <span className="page-title__meta">
          Captured {formatDate(captureRecord.visitedAt)} by {captureRecord.operator.name} ·{" "}
          {captureRecord.device.marketingName ?? captureRecord.device.model} ·{" "}
          {modeSummary(captureRecord)} · capture id
          {captureRecord.captures.length > 1 ? "s" : ""}{" "}
          {captureRecord.captures.map((capture, index) => (
            <span key={capture.captureId}>
              {index > 0 ? ", " : null}
              {capture.label} <span className="mono">{capture.captureId}</span>
            </span>
          ))}
        </span>
      )}
    </div>
  );
}

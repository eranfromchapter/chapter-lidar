// The state of a package without a verdict (web-review §6.4.3): uploading with its progress,
// checks running, checks that did not finish, or an upload the phone replaced with a new
// revision.

import { Card } from "@/components/hub/Card";
import { ProgressBar } from "@/components/hub/ProgressBar";
import { formatBytes } from "@/lib/format";
import { uploadPercent } from "@/lib/review";
import type { PackageSummary } from "@/lib/station-types";

export interface StatusCardProps {
  readonly pkg: PackageSummary;
  /** The newer revision that replaced this upload (re-seal after "Upload stopped"). */
  readonly replacedBy?: PackageSummary;
}

export function StatusCard({ pkg, replacedBy }: StatusCardProps) {
  if (replacedBy !== undefined) {
    return (
      <Card padding="md" label="Upload stopped" role="status">
        <div className="hub-stack hub-stack--10">
          <h3 className="status-title">Upload stopped</h3>
          <span className="text-14">
            The phone stopped this upload and sealed the capture again as revision{" "}
            {replacedBy.revision}. This revision is not checked.
          </span>
          <a className="text-13" href={`/packages/${encodeURIComponent(replacedBy.packageId)}`}>
            Open revision {replacedBy.revision} →
          </a>
        </div>
      </Card>
    );
  }
  if (pkg.status === "uploading") {
    const percent = uploadPercent(pkg);
    return (
      <Card padding="md" label="Uploading from the phone" role="status">
        <div className="hub-stack hub-stack--10">
          <h3 className="status-title">Uploading from the phone</h3>
          <span className="text-14">
            Not every file is verified and sealed yet. The checks start when the package is sealed.
          </span>
          <ProgressBar value={percent} label={`Upload ${percent}%`} />
          <span className="text-13 text-muted">
            {formatBytes(pkg.totals.bytesVerified)} of {formatBytes(pkg.totals.bytes)} · {percent}%
          </span>
        </div>
      </Card>
    );
  }
  if (pkg.status === "check_error") {
    return (
      <Card padding="md" label="The checks could not complete" role="alert">
        <div className="hub-stack hub-stack--10">
          <h3 className="status-title">The checks could not complete</h3>
          <span className="text-14">
            The station could not finish the acceptance checks. This is not a verdict; the station
            retries or an admin intervenes.
          </span>
        </div>
      </Card>
    );
  }
  return (
    <Card padding="md" label="Checks running" role="status">
      <div className="hub-stack hub-stack--10">
        <h3 className="status-title">Checks running</h3>
        <span className="text-14">
          The station is checking this package. The verdict and findings appear here when the checks
          finish.
        </span>
      </div>
    </Card>
  );
}

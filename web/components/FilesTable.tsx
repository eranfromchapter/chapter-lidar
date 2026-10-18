import type { CaptureRecord } from "@chapter/capture-contract";
import { fileDisplayName, formatBytes, hubState, ROLE_LABEL, shortSha } from "@/lib/format";
import type { PackageFile } from "@/lib/station-types";
import { ScrollToTarget } from "./ScrollToTarget";

export const TARGET_ROW_ID = "file-target";

export interface FilesTableProps {
  readonly packageId: string;
  readonly files: readonly PackageFile[];
  readonly captureRecord: CaptureRecord | undefined;
  /** bim and admin: download links and plan previews. */
  readonly canDownload: boolean;
  /** Path from ?file=, highlighted and scrolled into view. */
  readonly targetPath?: string | undefined;
}

function filesRoute(packageId: string, action: "download" | "preview", path: string): string {
  return `/packages/${encodeURIComponent(packageId)}/files/${action}?path=${encodeURIComponent(path)}`;
}

/**
 * Package files with role, size, SHA-256, HUB state and download. Download links point at this
 * app; the short-lived station link is fetched only when the user clicks.
 */
export function FilesTable({
  packageId,
  files,
  captureRecord,
  canDownload,
  targetPath,
}: FilesTableProps) {
  const previews = canDownload
    ? files.filter((file) => file.role === "plan_png" && file.status === "verified")
    : [];
  const hasTarget = targetPath !== undefined && files.some((file) => file.path === targetPath);

  return (
    <section className="section" aria-labelledby="files-title">
      <h2 id="files-title">Files</h2>
      {previews.length > 0 ? (
        <div className="plan-previews">
          {previews.map((file) => {
            const name = fileDisplayName(file.path, captureRecord, file.captureId, file.areaKey);
            return (
              <figure key={file.path} className="plan-preview">
                {/* Plain img: the PNG is streamed through this app, never from a signed link. */}
                <img src={filesRoute(packageId, "preview", file.path)} alt={`Plan of ${name}`} />
                <figcaption className="caption">{name}</figcaption>
              </figure>
            );
          })}
        </div>
      ) : null}
      <div className="table-card">
        <table className="table">
          <thead>
            <tr>
              <th scope="col">File</th>
              <th scope="col">Role</th>
              <th scope="col">Size</th>
              <th scope="col">SHA-256</th>
              <th scope="col">In the HUB</th>
              {canDownload ? (
                <th scope="col">
                  <span className="visually-hidden">Download</span>
                </th>
              ) : null}
            </tr>
          </thead>
          <tbody>
            {files.map((file) => {
              const isTarget = hasTarget && file.path === targetPath;
              const name = fileDisplayName(file.path, captureRecord, file.captureId, file.areaKey);
              return (
                <tr
                  key={file.path}
                  id={isTarget ? TARGET_ROW_ID : undefined}
                  className={isTarget ? "is-target" : undefined}
                  aria-current={isTarget ? "true" : undefined}
                  data-path={file.path}
                >
                  <td>
                    <span title={file.path}>{name}</span>
                  </td>
                  <td>{ROLE_LABEL[file.role]}</td>
                  <td>{formatBytes(file.bytes)}</td>
                  <td className="mono">
                    <span title={file.sha256}>{shortSha(file.sha256)}</span>
                  </td>
                  <td>{hubState(file.role, file.bytes)}</td>
                  {canDownload ? (
                    <td>
                      {file.status === "verified" ? (
                        <a
                          href={filesRoute(packageId, "download", file.path)}
                          aria-label={`Download ${name}`}
                          rel="nofollow"
                        >
                          Download
                        </a>
                      ) : (
                        <span className="caption">Not verified</span>
                      )}
                    </td>
                  ) : null}
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
      {hasTarget ? <ScrollToTarget targetId={TARGET_ROW_ID} /> : null}
    </section>
  );
}

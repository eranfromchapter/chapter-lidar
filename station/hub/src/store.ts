// Publication state of a package revision (table hub_publications): one row per package, so a
// retry updates the same row. `files` records every file already uploaded or linked, so a retry
// skips it. The worker implements this over Postgres; MemoryPublicationStore is for tests.

import type { PublicationError } from "./errors.js";

export type PublicationStatus = "pending" | "publishing" | "published" | "publish_failed";

/** One entry of hub_publications.files. */
export interface PublishedFile {
  /** uploaded: in the HUB; linked: listed in the report with its station link. */
  readonly kind: "uploaded" | "linked";
  /** File name in the HUB (uploaded) or the package path (linked). */
  readonly name: string;
  /** HUB folder (uploaded), null for linked files. */
  readonly folder: string | null;
  /** Package path; null for the spatial report. */
  readonly path: string | null;
  /** Manifest role, "manifest" or "spatial_report" (older rows: "verdict_report"). */
  readonly role: string;
  readonly sha256: string;
  readonly bytes: number;
  /** HUB document id, when the HUB returned one. */
  readonly documentId?: string;
  /** Station link (linked files). */
  readonly url?: string;
  readonly reason?: "too_large" | "not_published";
  /** The verdict a report belongs to. */
  readonly verdictId?: string;
  /** True when a retry found the file already in the HUB (an earlier answer was lost). */
  readonly foundBySearch?: boolean;
  readonly recordedAt: string;
}

export interface PublicationState {
  readonly status: PublicationStatus;
  readonly attempts: number;
  readonly verdictId: string | null;
  readonly files: readonly PublishedFile[];
  readonly error: PublicationError | null;
}

export interface PublicationStore {
  /**
   * Opens the publication of this verdict: creates the row or moves it to publishing (clearing
   * the error). A row already published for the same verdict stays published (nothing to do).
   * Recorded files are kept.
   */
  begin(packageId: string, verdictId: string): Promise<PublicationState>;
  /** Counts one more attempt; returns the new total. */
  countAttempt(packageId: string): Promise<number>;
  /** Records an uploaded or linked file (replaces an entry of the same kind, folder and name). */
  recordFile(packageId: string, file: PublishedFile): Promise<void>;
  /** Stores the error of a failed attempt that will be retried (status stays publishing). */
  attemptFailed(packageId: string, error: PublicationError): Promise<void>;
  markPublished(packageId: string): Promise<void>;
  markFailed(packageId: string, error: PublicationError): Promise<void>;
}

/** Key of a recorded file: kind, folder and name. */
export function fileKey(file: Pick<PublishedFile, "kind" | "folder" | "name">): string {
  return `${file.kind}\n${file.folder ?? ""}\n${file.name}`;
}

/** Replaces the entry with the same key, or appends. */
export function mergeFile(files: readonly PublishedFile[], file: PublishedFile): PublishedFile[] {
  const key = fileKey(file);
  const out = files.filter((item) => fileKey(item) !== key);
  out.push(file);
  return out;
}

interface MemoryRow {
  status: PublicationStatus;
  attempts: number;
  verdictId: string | null;
  files: PublishedFile[];
  error: PublicationError | null;
  publishedAt: string | null;
}

/** In-memory store with the same rules as the Postgres one (tests). */
export class MemoryPublicationStore implements PublicationStore {
  readonly rows = new Map<string, MemoryRow>();

  get(packageId: string): MemoryRow | undefined {
    return this.rows.get(packageId);
  }

  #row(packageId: string): MemoryRow {
    const row = this.rows.get(packageId);
    if (row === undefined) {
      throw new Error(`no publication for package ${packageId}`);
    }
    return row;
  }

  async begin(packageId: string, verdictId: string): Promise<PublicationState> {
    const row = this.rows.get(packageId);
    if (row === undefined) {
      const created: MemoryRow = {
        status: "publishing",
        attempts: 0,
        verdictId,
        files: [],
        error: null,
        publishedAt: null,
      };
      this.rows.set(packageId, created);
      return { ...created, files: [] };
    }
    const same = row.status === "published" && row.verdictId === verdictId;
    if (!same) {
      row.status = "publishing";
      row.verdictId = verdictId;
      row.error = null;
      row.publishedAt = null;
    }
    return { ...row, files: [...row.files] };
  }

  async countAttempt(packageId: string): Promise<number> {
    const row = this.#row(packageId);
    row.attempts += 1;
    return row.attempts;
  }

  async recordFile(packageId: string, file: PublishedFile): Promise<void> {
    const row = this.#row(packageId);
    row.files = mergeFile(row.files, file);
  }

  async attemptFailed(packageId: string, error: PublicationError): Promise<void> {
    this.#row(packageId).error = error;
  }

  async markPublished(packageId: string): Promise<void> {
    const row = this.#row(packageId);
    row.status = "published";
    row.error = null;
    row.publishedAt = new Date().toISOString();
  }

  async markFailed(packageId: string, error: PublicationError): Promise<void> {
    const row = this.#row(packageId);
    row.status = "publish_failed";
    row.error = error;
    row.publishedAt = null;
  }
}

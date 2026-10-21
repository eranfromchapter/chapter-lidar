// One-off backfill of the review read model (migration 0011) for packages sealed before it:
// packages.manifest_bytes from the stored manifest blob, and packages.field_controls from the
// package's field-controls file (when it matches the contract; else it stays NULL, as at
// sealing). New seals fill both columns themselves (routes/uploads/index.ts).
//
// - Reads each blob from the originals container and checks it against the registered
//   fingerprint (manifest_sha256, or the file's SHA-256 and size); a missing or different blob
//   is reported as a failure and nothing is written for that package.
// - Dry run unless apply is set: reports what it would write.
// - Idempotent: only NULL columns are filled (COALESCE), the guard trigger keeps filled ones
//   immutable, and a re-run finds nothing left except contract-invalid field controls, which
//   it reports again without writing.
// - Filling these columns does not move packages.updated_at (0011 trigger), and every package
//   written is audited as a system action.

import { validateFieldControls } from "@chapter/capture-contract";
import { writeAudit } from "../core/audit.js";
import type { Queryable } from "../core/db.js";
import { manifestBlobName, type OriginalsStorage } from "../storage/originals.js";

/** Largest manifest the backfill reads (a sealed manifest is far smaller). */
export const MAX_MANIFEST_BYTES = 64 * 1024 * 1024;
/** Largest field-controls file the backfill parses, as at sealing. */
export const MAX_FIELD_CONTROLS_BYTES = 4 * 1024 * 1024;
/** Audit actor name of the backfill. */
export const BACKFILL_ACTOR = "backfill-review-read-model";

export type FieldControlsOutcome =
  | "stored" // contract-valid: stored (or would be)
  | "invalid" // the file does not match the contract or is too large: stays NULL
  | "present" // already stored
  | "none"; // the package has no field-controls file

export interface BackfilledPackage {
  readonly packageId: string;
  /** Manifest size written (or that would be); undefined when it was already stored. */
  readonly manifestBytes?: number;
  readonly fieldControls: FieldControlsOutcome;
  /** Set when the package was skipped because a blob is missing or does not match. */
  readonly failure?: string;
}

export interface BackfillReport {
  readonly apply: boolean;
  readonly packages: readonly BackfilledPackage[];
  /** Packages written (apply) or that would be written (dry run). */
  readonly updated: number;
  readonly failed: number;
}

export interface BackfillOptions {
  readonly db: Queryable;
  readonly storage: Pick<OriginalsStorage, "read">;
  /** Write the columns; false (default) is a dry run. */
  readonly apply?: boolean;
  /** One line per package, for the CLI. */
  readonly log?: (line: string) => void;
}

interface Candidate {
  package_id: string;
  visit_id: string;
  manifest_sha256: string;
  manifest_bytes: number | null;
  has_field_controls: boolean;
  fc_path: string | null;
  fc_blob_name: string | null;
  fc_sha256: string | null;
  fc_bytes: number | null;
}

class BlobCheckError extends Error {}

async function readChecked(
  storage: Pick<OriginalsStorage, "read">,
  blobName: string,
  sha256: string,
  bytes: number | undefined,
  maxBytes: number,
  what: string,
): Promise<Buffer> {
  const blob = await storage.read(blobName, maxBytes);
  if (blob === undefined) {
    throw new BlobCheckError(`${what} blob is missing`);
  }
  if (blob.sha256 !== sha256) {
    throw new BlobCheckError(`${what} blob does not match its registered SHA-256`);
  }
  if (bytes !== undefined && blob.bytes !== bytes) {
    throw new BlobCheckError(`${what} blob does not match its registered size`);
  }
  return blob.data;
}

function parseFieldControls(data: Buffer): unknown {
  let parsed: unknown;
  try {
    parsed = JSON.parse(data.toString("utf8"));
  } catch {
    return undefined;
  }
  const checked = validateFieldControls(parsed);
  return checked.ok ? checked.value : undefined;
}

/** Sealed packages that miss a read model column the backfill can fill. */
async function candidates(db: Queryable): Promise<Candidate[]> {
  const result = await db.query<Candidate>(
    `SELECT p.package_id, p.visit_id, p.manifest_sha256, p.manifest_bytes,
            p.field_controls IS NOT NULL AS has_field_controls,
            f.path AS fc_path, f.blob_name AS fc_blob_name, f.sha256 AS fc_sha256,
            f.bytes AS fc_bytes
       FROM packages p
       LEFT JOIN LATERAL (
         SELECT path, blob_name, sha256, bytes FROM package_files
          WHERE package_id = p.package_id AND role = 'field_controls' AND status = 'verified'
          ORDER BY path COLLATE "C"
          LIMIT 1
       ) f ON true
      WHERE p.manifest IS NOT NULL
        AND (p.manifest_bytes IS NULL OR (p.field_controls IS NULL AND f.path IS NOT NULL))
      ORDER BY p.created_at, p.package_id`,
  );
  return result.rows;
}

async function backfillOne(
  options: BackfillOptions,
  candidate: Candidate,
): Promise<BackfilledPackage> {
  const { storage } = options;
  let manifestBytes: number | undefined;
  if (candidate.manifest_bytes === null) {
    const data = await readChecked(
      storage,
      manifestBlobName(candidate.package_id, candidate.visit_id),
      candidate.manifest_sha256,
      undefined,
      MAX_MANIFEST_BYTES,
      "manifest",
    );
    manifestBytes = data.length;
  }

  let fieldControls: FieldControlsOutcome = candidate.has_field_controls ? "present" : "none";
  let value: unknown;
  if (!candidate.has_field_controls && candidate.fc_path !== null) {
    if (
      candidate.fc_bytes === null ||
      candidate.fc_sha256 === null ||
      candidate.fc_blob_name === null ||
      candidate.fc_bytes > MAX_FIELD_CONTROLS_BYTES
    ) {
      fieldControls = "invalid";
    } else {
      const data = await readChecked(
        storage,
        candidate.fc_blob_name,
        candidate.fc_sha256,
        candidate.fc_bytes,
        MAX_FIELD_CONTROLS_BYTES,
        "field-controls",
      );
      value = parseFieldControls(data);
      fieldControls = value === undefined ? "invalid" : "stored";
    }
  }

  const writes = manifestBytes !== undefined || value !== undefined;
  if (options.apply === true && writes) {
    await options.db.query(
      `UPDATE packages
          SET manifest_bytes = COALESCE(manifest_bytes, $2::bigint),
              field_controls = COALESCE(field_controls, $3::jsonb)
        WHERE package_id = $1`,
      [
        candidate.package_id,
        manifestBytes ?? null,
        value === undefined ? null : JSON.stringify(value),
      ],
    );
    await writeAudit(options.db, {
      actor: { type: "system", name: BACKFILL_ACTOR },
      action: "package.read_model_backfill",
      target: { type: "package", id: candidate.package_id },
      details: {
        ...(manifestBytes === undefined ? {} : { manifestBytes }),
        fieldControls,
      },
    });
  }
  return {
    packageId: candidate.package_id,
    ...(manifestBytes === undefined ? {} : { manifestBytes }),
    fieldControls,
  };
}

/** Runs the backfill over every sealed package that needs it. */
export async function backfillReviewReadModel(options: BackfillOptions): Promise<BackfillReport> {
  const apply = options.apply === true;
  const packages: BackfilledPackage[] = [];
  for (const candidate of await candidates(options.db)) {
    let done: BackfilledPackage;
    try {
      done = await backfillOne(options, candidate);
    } catch (error) {
      if (!(error instanceof BlobCheckError)) {
        throw error;
      }
      done = {
        packageId: candidate.package_id,
        fieldControls: candidate.has_field_controls ? "present" : "none",
        failure: error.message,
      };
    }
    packages.push(done);
    options.log?.(describe(done, apply));
  }
  const failed = packages.filter((item) => item.failure !== undefined).length;
  const updated = packages.filter(
    (item) =>
      item.failure === undefined &&
      (item.manifestBytes !== undefined || item.fieldControls === "stored"),
  ).length;
  return { apply, packages, updated, failed };
}

/** One report line: the package id and what was (or would be) written. */
export function describe(item: BackfilledPackage, apply: boolean): string {
  if (item.failure !== undefined) {
    return `${item.packageId} FAILED: ${item.failure}`;
  }
  const parts = [
    item.manifestBytes === undefined
      ? "manifest_bytes kept"
      : `manifest_bytes=${item.manifestBytes}`,
    `field_controls ${item.fieldControls}`,
  ];
  return `${item.packageId} ${parts.join(", ")}${apply ? "" : " (dry run)"}`;
}

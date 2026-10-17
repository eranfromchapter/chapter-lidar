// PublicationStore over the hub_publications table (station/db/migrations/0006).

import type {
  PublicationError,
  PublicationState,
  PublicationStore,
  PublishedFile,
} from "@chapter/station-hub";
import type { Queryable } from "./db.js";

interface Row {
  status: PublicationState["status"];
  attempts: number;
  verdict_id: string | null;
  files: PublishedFile[];
  error: PublicationError | null;
}

export class PgPublicationStore implements PublicationStore {
  constructor(private readonly db: Queryable) {}

  async begin(packageId: string, verdictId: string): Promise<PublicationState> {
    const result = await this.db.query<Row>(
      `INSERT INTO hub_publications (package_id, verdict_id, status)
       VALUES ($1, $2, 'publishing')
       ON CONFLICT (package_id) DO UPDATE SET
         status = CASE
           WHEN hub_publications.status = 'published' AND hub_publications.verdict_id = EXCLUDED.verdict_id
           THEN 'published' ELSE 'publishing' END,
         published_at = CASE
           WHEN hub_publications.status = 'published' AND hub_publications.verdict_id = EXCLUDED.verdict_id
           THEN hub_publications.published_at ELSE NULL END,
         error = CASE
           WHEN hub_publications.status = 'published' AND hub_publications.verdict_id = EXCLUDED.verdict_id
           THEN hub_publications.error ELSE NULL END,
         verdict_id = EXCLUDED.verdict_id
       RETURNING status, attempts, verdict_id, files, error`,
      [packageId, verdictId],
    );
    const row = result.rows[0];
    if (row === undefined) {
      throw new Error("hub_publications upsert returned no row");
    }
    return {
      status: row.status,
      attempts: row.attempts,
      verdictId: row.verdict_id,
      files: row.files,
      error: row.error,
    };
  }

  async countAttempt(packageId: string): Promise<number> {
    const result = await this.db.query<{ attempts: number }>(
      `UPDATE hub_publications SET attempts = attempts + 1 WHERE package_id = $1 RETURNING attempts`,
      [packageId],
    );
    return result.rows[0]?.attempts ?? 0;
  }

  async recordFile(packageId: string, file: PublishedFile): Promise<void> {
    // One statement: drop an entry with the same kind, folder and name, append the new one.
    await this.db.query(
      `UPDATE hub_publications
          SET files = COALESCE((
                SELECT jsonb_agg(t.f ORDER BY t.ord)
                  FROM jsonb_array_elements(files) WITH ORDINALITY AS t(f, ord)
                 WHERE NOT (t.f->>'kind' = $2 AND COALESCE(t.f->>'folder', '') = $3
                            AND t.f->>'name' = $4)
              ), '[]'::jsonb) || jsonb_build_array($5::jsonb)
        WHERE package_id = $1`,
      [packageId, file.kind, file.folder ?? "", file.name, JSON.stringify(file)],
    );
  }

  async attemptFailed(packageId: string, error: PublicationError): Promise<void> {
    await this.db.query(`UPDATE hub_publications SET error = $2::jsonb WHERE package_id = $1`, [
      packageId,
      JSON.stringify(error),
    ]);
  }

  async markPublished(packageId: string): Promise<void> {
    await this.db.query(
      `UPDATE hub_publications SET status = 'published', published_at = now(), error = NULL
        WHERE package_id = $1`,
      [packageId],
    );
  }

  async markFailed(packageId: string, error: PublicationError): Promise<void> {
    await this.db.query(
      `UPDATE hub_publications SET status = 'publish_failed', published_at = NULL, error = $2::jsonb
        WHERE package_id = $1`,
      [packageId, JSON.stringify(error)],
    );
  }
}

/**
 * Records publish_failed when the publication could not even start or its job ended outside
 * the publisher (integrity failure, lost lock). Leaves a publication of the same verdict that is
 * already published alone.
 */
export async function markPublicationFailed(
  db: Queryable,
  packageId: string,
  verdictId: string | null,
  error: PublicationError,
): Promise<void> {
  await db.query(
    `INSERT INTO hub_publications (package_id, verdict_id, status, error)
     VALUES ($1, $2, 'publish_failed', $3::jsonb)
     ON CONFLICT (package_id) DO UPDATE SET
       status = 'publish_failed', published_at = NULL, error = EXCLUDED.error,
       verdict_id = COALESCE(EXCLUDED.verdict_id, hub_publications.verdict_id)
     WHERE NOT (hub_publications.status = 'published'
                AND hub_publications.verdict_id IS NOT DISTINCT FROM EXCLUDED.verdict_id)`,
    [packageId, verdictId, JSON.stringify(error)],
  );
}

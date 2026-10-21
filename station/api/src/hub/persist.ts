// Write-through of HUB projects to the projects_cache table (migration 0002).
//
// Every successful HUB lookup stores the projects it returned, so the review lists
// (GET /review/projects, /review/packages) can name a project without calling the HUB: also
// after the entry expired, after a restart and on another replica. The in-memory 10-minute
// cache (cache.ts) still answers the capture app; this table is never read for that.
//
// Storing is best effort: a database failure is logged (no project data) and the HUB answer
// is returned as usual.

import type { Queryable } from "../core/db.js";
import { HUB_CACHE_TTL_MS } from "./cache.js";
import type { HubClient, HubLogger, HubProject } from "./types.js";

/** Stores projects in projects_cache, replacing each deal's row; expires_at = now + ttlMs. */
export async function storeProjects(
  db: Queryable,
  projects: readonly HubProject[],
  ttlMs: number = HUB_CACHE_TTL_MS,
): Promise<void> {
  // One row per deal: ON CONFLICT cannot update the same row twice in one statement.
  const byDeal = new Map(projects.map((project) => [project.dealId, project]));
  if (byDeal.size === 0) {
    return;
  }
  const rows = [...byDeal.values()];
  await db.query(
    `INSERT INTO projects_cache
       (deal_id, project_name, address_formatted, hub_updated_at, fetched_at, expires_at)
     SELECT p.deal_id, p.project_name, p.address, p.hub_updated_at, now(),
            now() + $5::integer * interval '1 millisecond'
       FROM unnest($1::text[], $2::text[], $3::text[], $4::timestamptz[])
         AS p(deal_id, project_name, address, hub_updated_at)
     ON CONFLICT (deal_id) DO UPDATE
       SET project_name = EXCLUDED.project_name,
           address_formatted = EXCLUDED.address_formatted,
           hub_updated_at = EXCLUDED.hub_updated_at,
           fetched_at = EXCLUDED.fetched_at,
           expires_at = EXCLUDED.expires_at`,
    [
      rows.map((project) => project.dealId),
      rows.map((project) => project.projectName ?? null),
      rows.map((project) => project.address.formatted),
      rows.map((project) =>
        project.updatedAtMs === undefined ? null : new Date(project.updatedAtMs),
      ),
      Math.max(1, Math.round(ttlMs)),
    ],
  );
}

/** A HubClient that hands every project it returns to store (best effort). */
export class PersistingHubClient implements HubClient {
  readonly #inner: HubClient;
  readonly #store: (projects: readonly HubProject[]) => Promise<void>;
  readonly #logger: HubLogger | undefined;

  constructor(
    inner: HubClient,
    store: (projects: readonly HubProject[]) => Promise<void>,
    logger?: HubLogger,
  ) {
    this.#inner = inner;
    this.#store = store;
    this.#logger = logger;
  }

  async listProjects(): Promise<readonly HubProject[]> {
    const projects = await this.#inner.listProjects();
    await this.#persist(projects);
    return projects;
  }

  async getProject(dealId: string): Promise<HubProject | null> {
    const project = await this.#inner.getProject(dealId);
    if (project !== null) {
      await this.#persist([project]);
    }
    return project;
  }

  async #persist(projects: readonly HubProject[]): Promise<void> {
    try {
      await this.#store(projects);
    } catch (error) {
      this.#logger?.warn(
        {
          hub: {
            projects: projects.length,
            reason: error instanceof Error ? error.name : "unknown",
          },
        },
        "could not store HUB projects in projects_cache",
      );
    }
  }
}

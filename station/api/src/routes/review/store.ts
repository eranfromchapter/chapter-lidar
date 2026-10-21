// Reads of the review lists (web-review §9.1 C and D): projects that have packages, each with
// its newest package, and every package with its project's name and address. The package
// summaries come from routes/packages/store.ts, so the lists show exactly what the package
// routes show.
//
// Project name and address: the HUB project cache (also when expired), else the newest sealed
// capture record of the deal (hub.projectName, address.formatted), else "HUB deal {dealId}".
//
// Search q, case-insensitively: part of the project name or address (cache or any capture
// record of the deal), the start of the deal id, or, when q is 8 hex characters or more
// (dashes allowed), the start of a package id or capture id. A project matches when one of its
// packages does; a package matches by its project's name, address or deal, or its own ids.

import type { Queryable } from "../../core/db.js";
import {
  NEWEST_FIRST,
  PACKAGE_FROM,
  PACKAGE_UPDATED_AT,
  selectSummaryRows,
  toSummary,
  type LinkSettings,
  type PackageSummary,
} from "../packages/store.js";

export interface ReviewProject {
  dealId: string;
  projectName?: string;
  address: { formatted: string };
  packageCount: number;
  latest: PackageSummary;
}

export type ReviewPackage = PackageSummary & {
  projectName?: string;
  address: { formatted: string };
};

export interface ReviewPage<T> {
  readonly items: T[];
  readonly truncated: boolean;
}

/** Name and address of every deal that has packages (columns deal_id, project_name, address). */
const DEAL_NAMES = `
  SELECT d.deal_id,
         COALESCE(c.project_name, rec.project_name) AS project_name,
         COALESCE(c.address_formatted, rec.address, 'HUB deal ' || d.deal_id) AS address
    FROM (SELECT DISTINCT deal_id FROM packages) d
    LEFT JOIN projects_cache c ON c.deal_id = d.deal_id
    LEFT JOIN LATERAL (
      SELECT r.capture_record -> 'address' ->> 'formatted' AS address,
             r.capture_record -> 'hub' ->> 'projectName' AS project_name
        FROM packages r
       WHERE r.deal_id = d.deal_id AND r.capture_record IS NOT NULL
       ORDER BY r.created_at DESC, r.revision DESC, r.package_id
       LIMIT 1
    ) rec ON true`;

/** Text match of the deal n against $1 (null: everything matches). */
const DEAL_TEXT_MATCH = `(
  $1::text IS NULL
  OR strpos(lower(n.address), lower($1::text)) > 0
  OR strpos(lower(COALESCE(n.project_name, '')), lower($1::text)) > 0
  OR starts_with(lower(n.deal_id), lower($1::text))
  OR EXISTS (
    SELECT 1 FROM packages r
     WHERE r.deal_id = n.deal_id AND r.capture_record IS NOT NULL
       AND (strpos(lower(COALESCE(r.capture_record -> 'address' ->> 'formatted', '')),
                   lower($1::text)) > 0
            OR strpos(lower(COALESCE(r.capture_record -> 'hub' ->> 'projectName', '')),
                      lower($1::text)) > 0)))`;

/** Id match of the package alias against $2 (null: no id search). */
function packageIdMatch(alias: string): string {
  return `(
  $2::text IS NOT NULL
  AND (starts_with(${alias}.package_id::text, $2::text)
       OR EXISTS (SELECT 1 FROM package_files fi
                   WHERE fi.package_id = ${alias}.package_id
                     AND starts_with(fi.capture_id::text, $2::text))))`;
}

/** The id prefix q stands for: lowercase, hex and dashes only, 8 hex digits or more. */
export function idPrefixOf(q: string | undefined): string | null {
  if (q === undefined) {
    return null;
  }
  const lower = q.trim().toLowerCase();
  return /^[0-9a-f-]+$/.test(lower) && lower.replace(/-/g, "").length >= 8 ? lower : null;
}

async function summariesById(
  db: Queryable,
  links: LinkSettings,
  ids: readonly string[],
): Promise<Map<string, PackageSummary>> {
  if (ids.length === 0) {
    return new Map();
  }
  const rows = await selectSummaryRows(db, "p.package_id = ANY($1::uuid[])", [ids]);
  return new Map(rows.map((row) => [row.package_id, toSummary(row, links)]));
}

interface NamedRow {
  deal_id: string;
  project_name: string | null;
  address: string;
}

function nameOf(row: NamedRow): { projectName?: string; address: { formatted: string } } {
  return {
    ...(row.project_name === null ? {} : { projectName: row.project_name }),
    address: { formatted: row.address },
  };
}

/** Projects with packages, most recent package change first. */
export async function listReviewProjects(
  db: Queryable,
  links: LinkSettings,
  q: string | undefined,
  limit: number,
): Promise<ReviewPage<ReviewProject>> {
  const result = await db.query<NamedRow & { package_count: number; latest_id: string }>(
    `WITH names AS (${DEAL_NAMES}),
          changes AS (
            SELECT p.package_id, p.deal_id, p.created_at, p.revision,
                   ${PACKAGE_UPDATED_AT} AS updated_at
              FROM ${PACKAGE_FROM}
          ),
          deals AS (
            SELECT deal_id, count(*) AS package_count, max(updated_at) AS last_change,
                   (array_agg(package_id ORDER BY created_at DESC, revision DESC, package_id))[1]
                     AS latest_id
              FROM changes
             GROUP BY deal_id
          )
     SELECT n.deal_id, n.project_name, n.address, deals.package_count, deals.latest_id
       FROM deals JOIN names n ON n.deal_id = deals.deal_id
      WHERE ${DEAL_TEXT_MATCH}
         OR EXISTS (SELECT 1 FROM packages pm
                     WHERE pm.deal_id = n.deal_id AND ${packageIdMatch("pm")})
      ORDER BY deals.last_change DESC, n.deal_id
      LIMIT $3`,
    [q ?? null, idPrefixOf(q), limit + 1],
  );
  const rows = result.rows.slice(0, limit);
  const latest = await summariesById(
    db,
    links,
    rows.map((row) => row.latest_id),
  );
  const items = rows.flatMap((row) => {
    const summary = latest.get(row.latest_id);
    return summary === undefined
      ? []
      : [{ dealId: row.deal_id, ...nameOf(row), packageCount: row.package_count, latest: summary }];
  });
  return { items, truncated: result.rows.length > limit };
}

/** Every package, newest first, with its project's name and address. */
export async function listReviewPackages(
  db: Queryable,
  links: LinkSettings,
  q: string | undefined,
  limit: number,
): Promise<ReviewPage<ReviewPackage>> {
  const result = await db.query<NamedRow & { package_id: string }>(
    `WITH names AS (${DEAL_NAMES})
     SELECT p.package_id, n.deal_id, n.project_name, n.address
       FROM packages p JOIN names n ON n.deal_id = p.deal_id
      WHERE ${DEAL_TEXT_MATCH} OR ${packageIdMatch("p")}
      ORDER BY ${NEWEST_FIRST}
      LIMIT $3`,
    [q ?? null, idPrefixOf(q), limit + 1],
  );
  const rows = result.rows.slice(0, limit);
  const summaries = await summariesById(
    db,
    links,
    rows.map((row) => row.package_id),
  );
  const items = rows.flatMap((row) => {
    const summary = summaries.get(row.package_id);
    return summary === undefined ? [] : [{ ...summary, ...nameOf(row) }];
  });
  return { items, truncated: result.rows.length > limit };
}

// Turns raw HUB deal fields into HubProjects. Shared by the live client and the fake, so both
// apply the same "confirmed address only" rule and the same ordering.

import type { HubProject } from "./types.js";

export const DEAL_ID_MAX_LENGTH = 64;
export const PROJECT_NAME_MAX_LENGTH = 200;
export const ADDRESS_MAX_LENGTH = 300;
export const PROJECT_MANAGER_NAME_MAX_LENGTH = 200;
export const PROJECT_MANAGER_PHONE_MAX_LENGTH = 50;

/** The deal fields the station needs, as read from the HUB (types not yet checked). */
export interface RawHubDeal {
  readonly dealId: unknown;
  readonly projectName: unknown;
  readonly address: unknown;
  /** The HUB's "address confirmed" marker; only the boolean true counts as confirmed. */
  readonly addressConfirmed: unknown;
  readonly updatedAt: unknown;
  /** The deal's project manager, when the HUB gives one (optional fields). */
  readonly projectManagerName?: unknown;
  readonly projectManagerPhone?: unknown;
}

/** Why a raw deal is not a project for capture. */
export type SkipReason =
  "invalid_deal_id" | "address_not_confirmed" | "confirmation_missing" | "invalid_address";

export type NormalizeResult =
  | { readonly ok: true; readonly project: HubProject }
  | { readonly ok: false; readonly reason: SkipReason };

function normalizeDealId(value: unknown): string | undefined {
  if (typeof value === "number" && Number.isSafeInteger(value) && value >= 0) {
    return String(value);
  }
  if (typeof value === "string" && value.length >= 1 && value.length <= DEAL_ID_MAX_LENGTH) {
    return value;
  }
  return undefined;
}

function normalizeAddress(value: unknown): string | undefined {
  if (typeof value !== "string") {
    return undefined;
  }
  // Exactly as shown by the HUB: no rewriting. It must be one non-blank line that fits.
  if (value.trim() === "" || /[\r\n]/.test(value) || value.length > ADDRESS_MAX_LENGTH) {
    return undefined;
  }
  return value;
}

function normalizeName(value: unknown, maxLength = PROJECT_NAME_MAX_LENGTH): string | undefined {
  if (typeof value !== "string") {
    return undefined;
  }
  const name = value.trim().slice(0, maxLength);
  return name === "" ? undefined : name;
}

/** The project manager when the HUB names one; a phone without a name is dropped. */
function normalizeProjectManager(raw: RawHubDeal): HubProject["projectManager"] {
  const name = normalizeName(raw.projectManagerName, PROJECT_MANAGER_NAME_MAX_LENGTH);
  if (name === undefined) {
    return undefined;
  }
  const phone =
    typeof raw.projectManagerPhone === "string" &&
    !/[\r\n]/.test(raw.projectManagerPhone) &&
    raw.projectManagerPhone.trim().length <= PROJECT_MANAGER_PHONE_MAX_LENGTH
      ? normalizeName(raw.projectManagerPhone, PROJECT_MANAGER_PHONE_MAX_LENGTH)
      : undefined;
  return phone === undefined ? { name } : { name, phone };
}

function normalizeUpdatedAt(value: unknown): number | undefined {
  if (typeof value === "string" && value.trim() !== "") {
    const ms = Date.parse(value);
    return Number.isNaN(ms) ? undefined : ms;
  }
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  return undefined;
}

/** A project when the deal has a usable dealId and a confirmed, usable address. */
export function normalizeDeal(raw: RawHubDeal): NormalizeResult {
  const dealId = normalizeDealId(raw.dealId);
  if (dealId === undefined) {
    return { ok: false, reason: "invalid_deal_id" };
  }
  if (raw.addressConfirmed === undefined || raw.addressConfirmed === null) {
    return { ok: false, reason: "confirmation_missing" };
  }
  if (raw.addressConfirmed !== true) {
    return { ok: false, reason: "address_not_confirmed" };
  }
  const formatted = normalizeAddress(raw.address);
  if (formatted === undefined) {
    return { ok: false, reason: "invalid_address" };
  }
  const projectName = normalizeName(raw.projectName);
  const projectManager = normalizeProjectManager(raw);
  const updatedAtMs = normalizeUpdatedAt(raw.updatedAt);
  return {
    ok: true,
    project: {
      dealId,
      ...(projectName === undefined ? {} : { projectName }),
      address: { formatted },
      ...(projectManager === undefined ? {} : { projectManager }),
      ...(updatedAtMs === undefined ? {} : { updatedAtMs }),
    },
  };
}

export interface NormalizedDeals {
  /** Projects, most recently updated first (deals without an update time last, in HUB order). */
  readonly projects: HubProject[];
  /** How many raw deals were skipped, by reason. */
  readonly skipped: Partial<Record<SkipReason, number>>;
  /** Raw deals whose dealId was already seen (the first one wins). */
  readonly duplicates: number;
}

/** Normalizes, de-duplicates by dealId and orders a list of raw deals. */
export function normalizeDeals(raws: readonly RawHubDeal[]): NormalizedDeals {
  const projects: HubProject[] = [];
  const skipped: Partial<Record<SkipReason, number>> = {};
  const seen = new Set<string>();
  let duplicates = 0;
  for (const raw of raws) {
    const result = normalizeDeal(raw);
    if (!result.ok) {
      skipped[result.reason] = (skipped[result.reason] ?? 0) + 1;
      continue;
    }
    if (seen.has(result.project.dealId)) {
      duplicates += 1;
      continue;
    }
    seen.add(result.project.dealId);
    projects.push(result.project);
  }
  return { projects: sortByMostRecent(projects), skipped, duplicates };
}

/** Most recently updated first; projects without an update time keep their order, last. */
export function sortByMostRecent(projects: readonly HubProject[]): HubProject[] {
  return [...projects].sort((a, b) => {
    if (a.updatedAtMs === undefined || b.updatedAtMs === undefined) {
      return (a.updatedAtMs === undefined ? 1 : 0) - (b.updatedAtMs === undefined ? 1 : 0);
    }
    return b.updatedAtMs - a.updatedAtMs;
  });
}

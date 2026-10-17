// 10-minute cache in front of a HubClient (per station replica, in memory).
//
// - The deals list is one entry; single-deal lookups are answered from a fresh list when the
//   deal is in it, else cached per dealId (including "no such deal").
// - An entry is fresh while less than the TTL has passed since its HUB call started.
// - Failures are never cached: the next call asks the HUB again.
// - Concurrent callers of the same lookup share one HUB call.
// - Single-deal entries are capped so arbitrary dealIds cannot grow memory without bound.

import type { HubClient, HubProject } from "./types.js";

export const HUB_CACHE_TTL_MS = 10 * 60_000;
export const HUB_CACHE_MAX_DEALS = 1000;

export interface CachedHubClientOptions {
  readonly ttlMs?: number;
  /** Clock (epoch ms), for tests. Defaults to Date.now. */
  readonly now?: () => number;
  readonly maxDeals?: number;
}

interface Entry<T> {
  readonly value: T;
  readonly fetchedAt: number;
}

export class CachedHubClient implements HubClient {
  readonly #inner: HubClient;
  readonly #ttlMs: number;
  readonly #now: () => number;
  readonly #maxDeals: number;
  #list: Entry<readonly HubProject[]> | undefined;
  #listPending: Promise<readonly HubProject[]> | undefined;
  readonly #deals = new Map<string, Entry<HubProject | null>>();
  readonly #dealsPending = new Map<string, Promise<HubProject | null>>();

  constructor(inner: HubClient, options: CachedHubClientOptions = {}) {
    this.#inner = inner;
    this.#ttlMs = options.ttlMs ?? HUB_CACHE_TTL_MS;
    this.#now = options.now ?? Date.now;
    this.#maxDeals = options.maxDeals ?? HUB_CACHE_MAX_DEALS;
  }

  #fresh(entry: Entry<unknown> | undefined, now: number): boolean {
    return entry !== undefined && now - entry.fetchedAt < this.#ttlMs && now >= entry.fetchedAt;
  }

  async listProjects(): Promise<readonly HubProject[]> {
    const now = this.#now();
    if (this.#list !== undefined && this.#fresh(this.#list, now)) {
      return this.#list.value;
    }
    this.#listPending ??= this.#inner
      .listProjects()
      .then((value) => {
        this.#list = { value, fetchedAt: now };
        return value;
      })
      .finally(() => {
        this.#listPending = undefined;
      });
    return this.#listPending;
  }

  async getProject(dealId: string): Promise<HubProject | null> {
    const now = this.#now();
    if (this.#list !== undefined && this.#fresh(this.#list, now)) {
      const listed = this.#list.value.find((project) => project.dealId === dealId);
      if (listed !== undefined) {
        return listed;
      }
    }
    const cached = this.#deals.get(dealId);
    if (cached !== undefined && this.#fresh(cached, now)) {
      return cached.value;
    }
    const pending = this.#dealsPending.get(dealId);
    if (pending !== undefined) {
      return pending;
    }
    const call = this.#inner
      .getProject(dealId)
      .then((value) => {
        this.#remember(dealId, { value, fetchedAt: now });
        return value;
      })
      .finally(() => {
        this.#dealsPending.delete(dealId);
      });
    this.#dealsPending.set(dealId, call);
    return call;
  }

  #remember(dealId: string, entry: Entry<HubProject | null>): void {
    this.#deals.delete(dealId);
    this.#deals.set(dealId, entry);
    if (this.#deals.size <= this.#maxDeals) {
      return;
    }
    const now = this.#now();
    for (const [key, value] of this.#deals) {
      if (!this.#fresh(value, now)) {
        this.#deals.delete(key);
      }
    }
    // Still over the cap: drop the oldest entries (Map keeps insertion order).
    for (const key of this.#deals.keys()) {
      if (this.#deals.size <= this.#maxDeals) {
        break;
      }
      this.#deals.delete(key);
    }
  }
}

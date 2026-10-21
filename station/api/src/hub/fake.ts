// In-memory HubClient for tests, local development and the local stack (HUB_MODE=fake).
// Deterministic: the same deals every time. Never used in production (config refuses it).

import { normalizeDeals, type RawHubDeal } from "./normalize.js";
import type { HubClient, HubProject } from "./types.js";

/** The deal the fixtures and station checks use. */
export const FIXTURE_DEAL_ID = "fixture-deal-0001";
export const FIXTURE_DEAL_ADDRESS = "100 Example Street, Testville, NY 00000";

/**
 * The fake HUB's deals. Two have a confirmed address; the third does not and is never returned.
 * The second one names a project manager.
 */
export const FAKE_HUB_DEALS: readonly RawHubDeal[] = Object.freeze([
  {
    dealId: FIXTURE_DEAL_ID,
    projectName: "Fixture project",
    address: FIXTURE_DEAL_ADDRESS,
    addressConfirmed: true,
    updatedAt: "2026-10-01T12:00:00Z",
  },
  {
    dealId: "fixture-deal-0002",
    projectName: "Fixture second project",
    address: "200 Sample Avenue, Testville, NY 00000",
    addressConfirmed: true,
    updatedAt: "2026-09-15T09:30:00Z",
    projectManagerName: "Pat Fixture",
    projectManagerPhone: "+1 212 555 0100",
  },
  {
    dealId: "fixture-deal-0003",
    projectName: "Fixture deal without a confirmed address",
    address: "300 Pending Road, Testville, NY 00000",
    addressConfirmed: false,
    updatedAt: "2026-10-10T08:00:00Z",
  },
]);

export class FakeHubClient implements HubClient {
  readonly #projects: readonly HubProject[];

  constructor(deals: readonly RawHubDeal[] = FAKE_HUB_DEALS) {
    this.#projects = Object.freeze(normalizeDeals(deals).projects);
  }

  async listProjects(): Promise<readonly HubProject[]> {
    return this.#projects;
  }

  async getProject(dealId: string): Promise<HubProject | null> {
    return this.#projects.find((project) => project.dealId === dealId) ?? null;
  }
}

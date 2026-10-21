// HUB project lookup: the HubClient interface, its live and fake implementations, the
// 10-minute cache and the app service. Route areas use resolveHubClient(app).

export { CachedHubClient, HUB_CACHE_MAX_DEALS, HUB_CACHE_TTL_MS } from "./cache.js";
export type { CachedHubClientOptions } from "./cache.js";
export { FAKE_HUB_DEALS, FIXTURE_DEAL_ADDRESS, FIXTURE_DEAL_ID, FakeHubClient } from "./fake.js";
export { HUB_MAX_RESPONSE_BYTES, HUB_REQUEST_TIMEOUT_MS, LiveHubClient } from "./live.js";
export type { LiveHubClientOptions } from "./live.js";
export { HUB_API_MAPPING, readPath } from "./mapping.js";
export type { HubApiMapping } from "./mapping.js";
export { normalizeDeal, normalizeDeals, sortByMostRecent } from "./normalize.js";
export { PersistingHubClient, storeProjects } from "./persist.js";
export type { RawHubDeal, SkipReason } from "./normalize.js";
export { createHubClient, resolveHubClient } from "./service.js";
export type { CreateHubClientOptions } from "./service.js";
export { HubError } from "./types.js";
export type { HubClient, HubFailure, HubLogger, HubProject } from "./types.js";

// Fake HUB for tests, local development and the end-to-end run. Never used in production: the
// worker refuses HUB_MODE=fake when NODE_ENV is production.

import { LiveHubApi } from "../live.js";
import type { HubApi } from "../types.js";
import { FakeHub, type FakeHubOptions } from "./hub.js";

export {
  DEFAULT_FAKE_DEALS,
  FAKE_CREDENTIAL,
  FAKE_DEAL_ADDRESS,
  FAKE_DEAL_ID,
  FAKE_HUB_MAX_UPLOAD_BYTES,
  FAKE_PROJECT_RECORD_ID,
  FakeHub,
  MULTIPART_OVERHEAD_BYTES,
} from "./hub.js";
export type {
  FailureRule,
  FakeDeal,
  FakeHubOptions,
  FakeOperation,
  RecordedRequest,
  StoredDocument,
} from "./hub.js";
export { startFakeHubServer } from "./server.js";
export type { FakeHubServer } from "./server.js";

/**
 * The in-process fake client (HUB_MODE=fake): the real HTTP client over the fake's fetch, so
 * requests are built, authenticated and parsed exactly as in live mode.
 */
export function createFakeHubApi(hub: FakeHub = new FakeHub()): { api: HubApi; hub: FakeHub } {
  const api = new LiveHubApi({
    baseUrl: "http://fake-hub.invalid",
    credential: hub.credential,
    fetch: hub.fetch,
  });
  return { api, hub };
}

export function createFakeHub(options: FakeHubOptions = {}): FakeHub {
  return new FakeHub(options);
}

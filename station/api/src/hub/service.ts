// The station's HubClient service: `app.services.hub`.
//
// Tests inject a HubClient through buildServer({ services: { hub } }). Otherwise the first
// route area that needs the HUB calls resolveHubClient(app), which builds the client from
// config (fake or live, behind the 10-minute cache) and stores it in app.services for every
// other area.

import type { FastifyInstance } from "fastify";
import type { StationConfig } from "../core/config.js";
import "../core/fastify-types.js";
import { CachedHubClient, type CachedHubClientOptions } from "./cache.js";
import { FakeHubClient } from "./fake.js";
import { LiveHubClient } from "./live.js";
import type { HubClient, HubLogger } from "./types.js";

declare module "../core/services.js" {
  interface StationServices {
    /** HUB project lookup (cached). */
    hub: HubClient;
  }
}

export interface CreateHubClientOptions {
  readonly logger?: HubLogger;
  readonly cache?: CachedHubClientOptions;
  /** fetch implementation for the live client, for tests. */
  readonly fetch?: typeof fetch;
}

/** Builds the cached HubClient that config.hub describes. */
export function createHubClient(
  hub: StationConfig["hub"],
  options: CreateHubClientOptions = {},
): HubClient {
  let inner: HubClient;
  if (hub.mode === "fake") {
    inner = new FakeHubClient();
  } else {
    // Read the secret from the config object itself: it is non-enumerable, so a spread drops it.
    const credential = hub.serviceCredential;
    if (hub.baseUrl === undefined || credential === undefined) {
      throw new Error("HUB_MODE is live but HUB_BASE_URL or HUB_SERVICE_CREDENTIAL is not set");
    }
    inner = new LiveHubClient({
      baseUrl: hub.baseUrl,
      credential,
      ...(options.logger === undefined ? {} : { logger: options.logger }),
      ...(options.fetch === undefined ? {} : { fetch: options.fetch }),
    });
  }
  return new CachedHubClient(inner, options.cache);
}

/** The app's HubClient: the injected one, else one built from config (once per app). */
export function resolveHubClient(app: FastifyInstance): HubClient {
  const existing = app.services.hub;
  if (existing !== undefined) {
    return existing;
  }
  const created = createHubClient(app.config.hub, {
    logger: app.log.child({ component: "hub" }),
  });
  app.services.hub = created;
  return created;
}

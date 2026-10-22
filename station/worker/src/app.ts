// Builds the worker from its configuration: database, originals reader, HUB client, loop.

import { LiveHubApi, type HubApi } from "@chapter/station-hub";
import { createFakeHubApi } from "@chapter/station-hub/fake";
import type { WorkerConfig } from "./config.js";
import { createDatabase } from "./db.js";
import type { Logger } from "./logger.js";
import { createOriginalsReader, createReportsWriter } from "./storage.js";
import { Worker } from "./worker.js";

/** The HUB client of the configuration: live, or the in-process fake (never in production). */
export function createHubApi(config: WorkerConfig): HubApi {
  if (config.hub.mode === "fake") {
    if (config.env === "production") {
      throw new Error("HUB_MODE fake is not allowed in production");
    }
    return createFakeHubApi().api;
  }
  // Read the secret from the config object itself: it is non-enumerable.
  const credential = config.hub.serviceCredential;
  if (config.hub.baseUrl === undefined || credential === undefined) {
    throw new Error("HUB_MODE is live but HUB_BASE_URL or HUB_SERVICE_CREDENTIAL is not set");
  }
  return new LiveHubApi({ baseUrl: config.hub.baseUrl, credential });
}

export interface StartedWorker {
  readonly worker: Worker;
  stop(): Promise<void>;
}

/** Builds the worker from a configuration and starts its loop. */
export function startWorker(config: WorkerConfig, logger: Logger, hub?: HubApi): StartedWorker {
  const db = createDatabase({
    connection: config.database.connection,
    poolMax: config.database.poolMax,
    onPoolError: (error) =>
      logger.warn({ error: error.message }, "idle database connection failed"),
  });
  const worker = new Worker(
    {
      db,
      originals: createOriginalsReader(config.storage),
      reports: createReportsWriter(config.storage),
      hub: hub ?? createHubApi(config),
      logger,
      reviewBaseUrl: config.reviewBaseUrl,
      reportTimeZone: config.reportTimeZone,
      retryBaseSeconds: config.worker.retryBaseSeconds,
      retryMaxSeconds: config.worker.retryMaxSeconds,
      publishRetryBaseMs: config.worker.publishRetryBaseMs,
      publishRetryMaxMs: config.worker.publishRetryMaxMs,
      secrets: config.hub.serviceCredential === undefined ? [] : [config.hub.serviceCredential],
      now: () => new Date(),
    },
    {
      workerId: config.worker.id,
      pollIntervalMs: config.worker.pollIntervalMs,
      lockTimeoutSeconds: config.worker.lockTimeoutSeconds,
    },
  );
  const running = worker.start();
  return {
    worker,
    stop: async () => {
      await worker.stop();
      await running;
      await db.close();
    },
  };
}

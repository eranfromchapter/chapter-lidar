// Worker entrypoint (container CMD: node dist/main.js). Reads and validates the configuration
// (refuses to start on any problem, naming variables only), then runs the job loop until
// SIGTERM or SIGINT, finishing the current job first.

import { startWorker } from "./app.js";
import { ConfigError, describeConfig, loadConfig, type WorkerConfig } from "./config.js";
import { createLogger } from "./logger.js";

async function main(): Promise<void> {
  let config: WorkerConfig;
  try {
    config = loadConfig();
  } catch (error) {
    if (error instanceof ConfigError) {
      process.stderr.write(`${error.message}\n`);
      process.exit(1);
    }
    throw error;
  }
  const logger = createLogger(config.logLevel);
  logger.info({ config: describeConfig(config) }, "station worker starting");
  const started = startWorker(config, logger);
  let stopping = false;
  const shutdown = (signal: string) => {
    if (stopping) {
      return;
    }
    stopping = true;
    logger.info({ signal }, "station worker stopping after the current job");
    started.stop().then(
      () => process.exit(0),
      (error: unknown) => {
        logger.error(
          { error: error instanceof Error ? error.message : "unknown" },
          "shutdown failed",
        );
        process.exit(1);
      },
    );
  };
  process.on("SIGTERM", () => shutdown("SIGTERM"));
  process.on("SIGINT", () => shutdown("SIGINT"));
}

await main();

// Station API entry point: load config, optionally migrate, build the app and listen.
// Importing this module only re-exports buildServer; the server starts when it is run directly.

import { realpathSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { buildServer } from "./core/app.js";
import { ConfigError, describeConfig, loadConfig } from "./core/config.js";
import { createDatabase } from "./core/db.js";
import { runMigrations } from "./core/migrate.js";

export { buildServer, type BuildServerOptions } from "./core/app.js";

async function main(): Promise<void> {
  let config;
  try {
    config = loadConfig();
  } catch (error) {
    if (error instanceof ConfigError) {
      console.error(error.message);
      process.exit(2);
    }
    throw error;
  }

  let app: Awaited<ReturnType<typeof buildServer>> | undefined;
  const db = createDatabase({
    url: config.database.url,
    poolMax: config.database.poolMax,
    onPoolError: (error) => app?.log.error({ err: error }, "idle database connection failed"),
  });

  try {
    app = await buildServer({ config, db });
    app.log.info({ config: describeConfig(config) }, "station api starting");

    if (config.database.migrateOnStart) {
      const log = app.log;
      const applied = await runMigrations({
        databaseUrl: config.database.url,
        logger: {
          info: (message) => log.info({ migrate: message }),
          warn: (message) => log.warn({ migrate: message }),
          error: (message) => log.error({ migrate: message }),
        },
      });
      log.info({ applied }, `migrations: ${applied.length} applied`);
    }

    await app.listen({ host: config.server.host, port: config.server.port });
  } catch (error) {
    if (app) {
      app.log.fatal({ err: error }, "station api failed to start");
      await app.close().catch(() => undefined);
    } else {
      console.error(error);
    }
    await db.close().catch(() => undefined);
    process.exit(1);
  }

  let closing = false;
  const shutdown = (signal: string) => {
    if (closing) {
      return;
    }
    closing = true;
    app?.log.info({ signal }, "station api shutting down");
    void (async () => {
      await app?.close();
      await db.close();
      process.exit(0);
    })();
  };
  process.once("SIGTERM", () => shutdown("SIGTERM"));
  process.once("SIGINT", () => shutdown("SIGINT"));
}

function isMainModule(): boolean {
  const entry = process.argv[1];
  if (entry === undefined) {
    return false;
  }
  try {
    return realpathSync(entry) === realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
}

if (isMainModule()) {
  await main();
}

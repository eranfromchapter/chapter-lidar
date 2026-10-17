// Builds the station Fastify app.
//
// Order matters: problem handlers, then auth (root hooks and the route access check), then
// /health, then every route area autoloaded from src/routes/<area>/index.(ts|js) under /v1.
//
// Route areas are Fastify plugins (default export). Paths are written in full relative to /v1
// (dirNameRoutePrefix is off), for example "/packages/:packageId/verdict" in
// src/routes/verdicts/index.ts. Every route declares config.roles; see auth.ts.

import { randomUUID } from "node:crypto";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import autoload from "@fastify/autoload";
import Fastify, { type FastifyInstance } from "fastify";
import type { JWTVerifyGetKey } from "jose";
import { auth } from "./auth.js";
import type { StationConfig } from "./config.js";
import type { Database } from "./db.js";
import "./fastify-types.js";
import { healthRoutes } from "./health.js";
import { type LogDestination, loggerOptions } from "./logger.js";
import { problems } from "./problem.js";
import type { StationServices } from "./services.js";

/** src/routes (or dist/routes in the image). */
export const ROUTES_DIR = fileURLToPath(new URL("../routes", import.meta.url));

/** Only <area>/index.(ts|js) files are route plugins; helpers next to them are not loaded. */
export const ROUTE_FILE_PATTERN = /^\/[a-z0-9]+(?:-[a-z0-9]+)*\/index\.(?:ts|js)$/;

export interface BuildServerOptions {
  readonly config: StationConfig;
  readonly db: Database;
  /** Services to inject (test doubles); areas create the real ones when absent. */
  readonly services?: Partial<StationServices>;
  /** Signing keys for token verification; defaults to the remote JWKS in config. */
  readonly getKey?: JWTVerifyGetKey;
  /** Route areas folder; false loads no route areas. Defaults to ROUTES_DIR. */
  readonly routesDir?: string | false;
  /** Log destination (tests); defaults to stdout. */
  readonly logStream?: LogDestination;
}

/**
 * Creates the app without starting it. Call ready(), inject() or listen() next; a route without
 * an access rule makes that call fail.
 */
export async function buildServer(options: BuildServerOptions): Promise<FastifyInstance> {
  const { config } = options;
  const app = Fastify({
    logger: loggerOptions(config.server.logLevel, options.logStream),
    genReqId: () => randomUUID(),
    bodyLimit: config.server.bodyLimitBytes,
    ajv: {
      // Unknown properties are rejected (additionalProperties: false -> 400), not stripped.
      customOptions: { removeAdditional: false },
    },
  });

  app.decorate("config", config);
  app.decorate("db", options.db);
  app.decorate("services", { ...(options.services ?? {}) });

  app.addHook("onRequest", async (request, reply) => {
    reply.header("x-request-id", request.id);
  });

  await app.register(problems);
  await app.register(auth, {
    config: config.auth,
    ...(options.getKey === undefined ? {} : { getKey: options.getKey }),
  });
  await app.register(healthRoutes);

  const routesDir = options.routesDir ?? ROUTES_DIR;
  if (routesDir !== false && existsSync(routesDir)) {
    await app.register(
      async (v1) => {
        await v1.register(autoload, {
          dir: routesDir,
          dirNameRoutePrefix: false,
          forceESM: true,
          matchFilter: (path: string) => ROUTE_FILE_PATTERN.test(path),
        });
      },
      { prefix: "/v1" },
    );
  }

  return app;
}

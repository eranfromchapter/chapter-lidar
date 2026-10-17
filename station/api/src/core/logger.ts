// Pino logger options for the station. Request logs carry method, URL and request id only;
// authorization and cookie headers are redacted wherever they appear.

import type { FastifyServerOptions } from "fastify";
import type { LogLevel } from "./config.js";

export interface LogDestination {
  write(message: string): void;
}

export const REDACT_PATHS = [
  "req.headers.authorization",
  "req.headers.cookie",
  "headers.authorization",
  "headers.cookie",
  "authorization",
  "token",
  "accessToken",
  "password",
  "connectionString",
  "databaseUrl",
  "*.authorization",
  "*.token",
  "*.accessToken",
  "*.password",
  "*.connectionString",
  "*.databaseUrl",
];

export function loggerOptions(
  level: LogLevel,
  stream?: LogDestination,
): NonNullable<FastifyServerOptions["logger"]> {
  return {
    level,
    redact: { paths: REDACT_PATHS, censor: "[redacted]" },
    ...(stream === undefined ? {} : { stream }),
  };
}

// Minimal JSON-lines logger (stdout). Callers pass only safe fields: ids, counts, statuses and
// station-written messages; never credentials, tokens, connection strings or file contents.

import type { LogLevel } from "./config.js";

export interface Logger {
  error(details: Record<string, unknown>, message: string): void;
  warn(details: Record<string, unknown>, message: string): void;
  info(details: Record<string, unknown>, message: string): void;
  debug(details: Record<string, unknown>, message: string): void;
}

const ORDER: Record<LogLevel, number> = {
  trace: 10,
  debug: 20,
  info: 30,
  warn: 40,
  error: 50,
  fatal: 60,
  silent: 100,
};

export function createLogger(
  level: LogLevel,
  write: (line: string) => void = (line) => process.stdout.write(`${line}\n`),
): Logger {
  const emit = (at: Exclude<LogLevel, "silent">, details: Record<string, unknown>, msg: string) => {
    if (ORDER[at] < ORDER[level]) {
      return;
    }
    write(
      JSON.stringify({
        level: at,
        time: new Date().toISOString(),
        component: "station-worker",
        msg,
        ...details,
      }),
    );
  };
  return {
    error: (details, msg) => emit("error", details, msg),
    warn: (details, msg) => emit("warn", details, msg),
    info: (details, msg) => emit("info", details, msg),
    debug: (details, msg) => emit("debug", details, msg),
  };
}

export const silentLogger: Logger = {
  error: () => undefined,
  warn: () => undefined,
  info: () => undefined,
  debug: () => undefined,
};

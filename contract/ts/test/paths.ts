// Repository paths shared by the tests.

import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));

export const contractDir = resolve(here, "..", "..");
export const examplesDir = resolve(contractDir, "examples");

export function readJson(path: string): unknown {
  return JSON.parse(readFileSync(path, "utf8")) as unknown;
}

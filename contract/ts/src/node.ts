// Node-only helpers for @chapter/capture-contract. Kept out of the main entry so
// the main entry stays browser-safe.

import { join } from "node:path";
import { fileURLToPath } from "node:url";
import type { SchemaName } from "./validators.js";

/**
 * Absolute path of contract/schema in this repository. Resolves from both
 * src/ (tsx, tests) and dist/ (built), which sit at the same depth.
 */
export const schemaDir: string = fileURLToPath(new URL("../../schema/", import.meta.url));

/** Absolute path of one schema file, for example contract/schema/manifest.schema.json. */
export function schemaPath(name: SchemaName): string {
  return join(schemaDir, `${name}.schema.json`);
}

/** Absolute path of contract/schema/layout.json. */
export const layoutPath: string = join(schemaDir, "layout.json");

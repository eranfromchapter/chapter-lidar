// Node-only helper: reads a package folder into memory. The only module that touches the file
// system; the checks themselves stay pure.

import { lstatSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { packageFromFiles } from "./package.js";
import type { LoadedPackage } from "./types.js";

/**
 * Reads every regular file under `dir` (symbolic links are skipped, so nothing outside the folder
 * is read) and builds the in-memory package. Paths are relative to `dir` with forward slashes.
 */
export function readPackageFiles(dir: string): Map<string, Uint8Array> {
  const files = new Map<string, Uint8Array>();
  const walk = (current: string, prefix: string) => {
    const entries = readdirSync(current, { withFileTypes: true }).sort((a, b) =>
      a.name < b.name ? -1 : a.name > b.name ? 1 : 0,
    );
    for (const entry of entries) {
      const full = join(current, entry.name);
      const relative = prefix === "" ? entry.name : `${prefix}/${entry.name}`;
      const stat = lstatSync(full);
      if (stat.isSymbolicLink()) {
        continue;
      }
      if (stat.isDirectory()) {
        walk(full, relative);
      } else if (stat.isFile()) {
        files.set(relative, new Uint8Array(readFileSync(full)));
      }
    }
  };
  walk(dir, "");
  return files;
}

/** Loads a package folder (the folder that holds "Source Register", "Original Exports", ...). */
export function loadPackageFromDirectory(dir: string): LoadedPackage {
  return packageFromFiles(readPackageFiles(dir));
}

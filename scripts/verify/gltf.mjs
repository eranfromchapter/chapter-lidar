#!/usr/bin/env node
// Validates .glb / .gltf files with the Khronos glTF-Validator (npm "gltf-validator").
// External buffers and images are loaded relative to each file, so missing companion
// files are reported as errors. Exits 1 if any file has one or more errors.
//
// Usage: node scripts/verify/gltf.mjs <file> [<file> ...]

import { readFile } from "node:fs/promises";
import { basename, dirname, resolve } from "node:path";
import validator from "gltf-validator";

const files = process.argv.slice(2);
if (files.length === 0) {
  console.error("usage: node scripts/verify/gltf.mjs <file> [<file> ...]");
  process.exit(2);
}

let failed = 0;

for (const file of files) {
  const baseDir = dirname(resolve(file));
  try {
    const data = new Uint8Array(await readFile(file));
    const report = await validator.validateBytes(data, {
      uri: basename(file),
      maxIssues: 0,
      externalResourceFunction: async (uri) =>
        new Uint8Array(await readFile(resolve(baseDir, decodeURIComponent(uri)))),
    });
    const { numErrors, numWarnings } = report.issues;
    if (numErrors > 0) {
      failed += 1;
      console.log(`FAIL ${file}: ${numErrors} error(s), ${numWarnings} warning(s)`);
      for (const issue of report.issues.messages.filter((message) => message.severity === 0)) {
        console.log(`  ${issue.code} ${issue.pointer ?? ""} ${issue.message}`);
      }
    } else {
      console.log(`OK   ${file}: 0 errors, ${numWarnings} warning(s)`);
    }
  } catch (error) {
    failed += 1;
    console.log(`FAIL ${file}: ${error instanceof Error ? error.message : String(error)}`);
  }
}

process.exit(failed > 0 ? 1 : 0);

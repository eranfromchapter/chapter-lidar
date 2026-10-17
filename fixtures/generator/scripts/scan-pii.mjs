#!/usr/bin/env node
// Scans text files under one or more folders for personal information: email addresses, phone
// numbers and street addresses. Prints every offender and exits 1 if there is any hit.
//
// Usage: node fixtures/generator/scripts/scan-pii.mjs <dir> [<dir> ...]
//
// - Binary files (a NUL byte in the first 8 KB) are skipped. node_modules and .git are skipped.
// - The two documented placeholder addresses are allowed, exactly as written:
//   "100 Example Street, Testville, NY 00000" and "200 Sample Avenue, Testville, NY 00000".
// - A folder may add its own allowed literal strings in a "pii-allowlist.txt" at its root (one
//   per line, "#" starts a comment). A hit is ignored when its matched text is listed.

import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative, resolve } from "node:path";

const PLACEHOLDER_ADDRESSES = [
  "100 Example Street, Testville, NY 00000",
  "200 Sample Avenue, Testville, NY 00000",
];
const SKIP_DIRS = new Set(["node_modules", ".git"]);
const ALLOWLIST_FILE = "pii-allowlist.txt";

const SUFFIXES = [
  "Street",
  "St",
  "Avenue",
  "Ave",
  "Road",
  "Rd",
  "Boulevard",
  "Blvd",
  "Lane",
  "Ln",
  "Drive",
  "Dr",
  "Court",
  "Ct",
  "Terrace",
  "Ter",
  "Way",
  "Place",
  "Pl",
  "Highway",
  "Hwy",
  "Parkway",
  "Pkwy",
  "Circle",
  "Cir",
  "Square",
  "Sq",
  "Trail",
  "Trl",
].join("|");

const RULES = [
  {
    kind: "email",
    pattern: /[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}/g,
  },
  {
    kind: "phone",
    // 10 digits grouped 3-3-4 with spaces, dots or hyphens, optional +1 and parentheses.
    pattern: /(?<![\w.+-])(?:\+?1[ .-])?(?:\(\d{3}\)[ ]?|\d{3}[ .-])\d{3}[ .-]\d{4}(?!\d)/g,
  },
  {
    kind: "street address",
    pattern: new RegExp(
      `\\b\\d{1,6}[ \\t]+(?:[A-Z][A-Za-z0-9.'-]*[ \\t]+){0,4}(?:${SUFFIXES})\\b\\.?`,
      "g",
    ),
    allowPlaceholders: true,
  },
];

function* walk(dir) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (SKIP_DIRS.has(entry.name)) {
      continue;
    }
    const full = join(dir, entry.name);
    if (entry.isDirectory()) {
      yield* walk(full);
    } else if (entry.isFile()) {
      yield full;
    }
  }
}

function isBinary(buffer) {
  const end = Math.min(buffer.length, 8192);
  for (let i = 0; i < end; i += 1) {
    if (buffer[i] === 0) {
      return true;
    }
  }
  return false;
}

function readAllowlist(root) {
  const file = join(root, ALLOWLIST_FILE);
  if (!existsSync(file)) {
    return new Set();
  }
  return new Set(
    readFileSync(file, "utf8")
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter((line) => line !== "" && !line.startsWith("#")),
  );
}

/** Returns the offenders of one text: [{ line, kind, text }]. */
export function scanText(text, allowed = new Set()) {
  const offenders = [];
  const lines = text.split(/\r?\n/);
  lines.forEach((line, index) => {
    for (const rule of RULES) {
      rule.pattern.lastIndex = 0;
      for (const match of line.matchAll(rule.pattern)) {
        const found = match[0];
        if (allowed.has(found)) {
          continue;
        }
        if (
          rule.allowPlaceholders &&
          PLACEHOLDER_ADDRESSES.some((placeholder) => line.startsWith(placeholder, match.index))
        ) {
          continue;
        }
        offenders.push({ line: index + 1, kind: rule.kind, text: found });
      }
    }
  });
  return offenders;
}

export function scanFolder(root) {
  const allowed = readAllowlist(root);
  const hits = [];
  let scanned = 0;
  for (const file of walk(root)) {
    if (file.endsWith(`${ALLOWLIST_FILE}`)) {
      continue;
    }
    const buffer = readFileSync(file);
    if (isBinary(buffer)) {
      continue;
    }
    scanned += 1;
    for (const offender of scanText(buffer.toString("latin1"), allowed)) {
      hits.push({ file, ...offender });
    }
  }
  return { scanned, hits };
}

function main() {
  const roots = process.argv.slice(2);
  if (roots.length === 0) {
    console.error("usage: node scan-pii.mjs <dir> [<dir> ...]");
    process.exit(2);
  }
  let total = 0;
  for (const root of roots) {
    const resolved = resolve(root);
    if (!existsSync(resolved) || !statSync(resolved).isDirectory()) {
      console.error(`scan-pii: '${root}' is not a directory`);
      process.exit(2);
    }
    const { scanned, hits } = scanFolder(resolved);
    for (const hit of hits) {
      console.log(`${relative(process.cwd(), hit.file)}:${hit.line}: ${hit.kind}: ${hit.text}`);
    }
    console.log(`scan-pii: ${root}: ${scanned} text files scanned, ${hits.length} hit(s)`);
    total += hits.length;
  }
  process.exit(total > 0 ? 1 : 0);
}

if (import.meta.url === `file://${process.argv[1]}` || process.argv[1]?.endsWith("scan-pii.mjs")) {
  main();
}

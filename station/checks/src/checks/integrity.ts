// Check 1 (fingerprints) and check 2 (nonempty and readable per role).

import { createHash } from "node:crypto";
import type { CheckContext } from "../context.js";
import { NO_ACTION, count, finding, scopeOf } from "../finding.js";
import { ROLE_FORMAT } from "../parsers/index.js";
import type { CheckOutput, StationFinding } from "../types.js";

function sha256(bytes: Uint8Array): string {
  return createHash("sha256").update(bytes).digest("hex");
}

/** Check 1: every listed file is present and its sha256 and size equal the manifest. */
export function checkFingerprints(ctx: CheckContext): CheckOutput {
  const findings: StationFinding[] = [];
  let matched = 0;
  for (const entry of ctx.entries) {
    const bytes = ctx.bytes(entry.path);
    const where = { filePath: entry.path, ...scopeOf(entry) };
    if (bytes === undefined) {
      findings.push(
        finding({
          ruleId: "manifest.fingerprints",
          severity: "blocker",
          message: "A file listed in the manifest is missing from the package.",
          ...where,
          measured: "file not present",
          expected: `present, ${entry.bytes} bytes, sha256 ${entry.sha256}`,
          nextAction: "Re-upload the sealed package from the device so every listed file arrives.",
        }),
      );
      continue;
    }
    const actual = sha256(bytes);
    if (actual !== entry.sha256 || bytes.length !== entry.bytes) {
      findings.push(
        finding({
          ruleId: "manifest.fingerprints",
          severity: "blocker",
          message: "File does not match its manifest fingerprint; it changed after sealing.",
          ...where,
          measured: `${bytes.length} bytes, sha256 ${actual}`,
          expected: `${entry.bytes} bytes, sha256 ${entry.sha256}`,
          nextAction: "Re-upload the original sealed package; do not edit files after sealing.",
        }),
      );
      continue;
    }
    matched += 1;
  }
  const listed = new Set(ctx.entries.map((entry) => entry.path));
  for (const path of ctx.pkg.files.keys()) {
    if (path !== ctx.manifestPath && !listed.has(path)) {
      findings.push(
        finding({
          ruleId: "manifest.fingerprints",
          severity: "info",
          message: "File is not listed in the manifest; it was not fingerprinted and is not used.",
          filePath: ctx.manifestPath,
          measured: `unlisted file: ${path}`,
          expected: "every package file listed in the manifest",
          nextAction: NO_ACTION,
        }),
      );
    }
  }
  if (matched === ctx.entries.length) {
    findings.push(
      finding({
        ruleId: "manifest.fingerprints",
        severity: "info",
        message: "Every file matches its manifest fingerprint.",
        filePath: ctx.manifestPath,
        measured: `${matched} of ${ctx.entries.length} match`,
        expected: "sha256 and size equal the manifest",
        nextAction: NO_ACTION,
      }),
    );
  }
  return { findings };
}

/** Check 2: every listed file that is present is nonempty and reads as its role's format. */
export function checkParseable(ctx: CheckContext): CheckOutput {
  const findings: StationFinding[] = [];
  let readable = 0;
  let present = 0;
  for (const entry of ctx.entries) {
    const bytes = ctx.bytes(entry.path);
    if (bytes === undefined) {
      continue;
    }
    present += 1;
    const format = ROLE_FORMAT[entry.role];
    const where = { filePath: entry.path, ...scopeOf(entry) };
    const name = entry.path.split("/").pop() ?? entry.path;
    if (bytes.length === 0) {
      findings.push(
        finding({
          ruleId: "files.parseable",
          severity: "blocker",
          message: `File is empty (role ${entry.role}).`,
          ...where,
          measured: "0 bytes",
          expected: `a nonempty ${format} file`,
          nextAction: `Re-export ${name} on the device and re-upload the package.`,
        }),
      );
      continue;
    }
    const result = ctx.parsed(entry);
    if (result !== undefined && !result.ok) {
      findings.push(
        finding({
          ruleId: "files.parseable",
          severity: "blocker",
          message: `File cannot be read as ${format} (role ${entry.role}).`,
          ...where,
          measured: `${bytes.length} bytes; ${result.reason}`,
          expected: `a readable ${format} file`,
          nextAction: `Re-export ${name} on the device and re-upload the package.`,
        }),
      );
      continue;
    }
    readable += 1;
  }
  if (readable === present) {
    findings.push(
      finding({
        ruleId: "files.parseable",
        severity: "info",
        message: "Every file is nonempty and reads as the format of its role.",
        filePath: ctx.manifestPath,
        measured: `${readable} of ${count(present, "file")} readable`,
        expected: "nonempty and readable per role",
        nextAction: NO_ACTION,
      }),
    );
  }
  return { findings };
}

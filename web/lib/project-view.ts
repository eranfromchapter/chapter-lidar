// Cells of the project page's packages table (web-review §6.3.1) and the words of package states
// shared with the package page. Pure functions over station summaries.

import { areaNoun, formatBytes, formatDate, plural, shortId } from "./format";
import { replacedBy } from "./packages";
import { uploadPercent } from "./review";
import type { PackageSummary } from "./station-types";

/** True when the packages come from more than one site visit. */
export function hasSeveralVisits(packages: readonly PackageSummary[]): boolean {
  return new Set(packages.map((pkg) => pkg.visitId)).size > 1;
}

/** The "Package" cell's second line, and whether it is an id (set in mono). */
export function packageSubLine(
  pkg: PackageSummary,
  packages: readonly PackageSummary[],
): { prefix: string; text: string; mono: boolean; title?: string } {
  const prefix = hasSeveralVisits(packages)
    ? `visit ${formatDate(pkg.visitedAt ?? pkg.createdAt)} · `
    : "";
  const successor = replacedBy(packages, pkg);
  if (successor !== undefined) {
    return {
      prefix,
      text: `upload stopped · replaced by revision ${successor.revision}`,
      mono: false,
    };
  }
  switch (pkg.status) {
    case "uploading":
      return { prefix, text: `uploading from the phone · ${uploadPercent(pkg)}%`, mono: false };
    case "checks_queued":
    case "checking":
      return { prefix, text: "sealed · checks running", mono: false };
    case "check_error":
      return { prefix, text: "sealed · checks did not finish", mono: false };
    case "verdict_ready": {
      const [first] = pkg.captures;
      if (first === undefined) {
        return { prefix, text: "sealed", mono: false };
      }
      const more = pkg.captures.length > 1 ? ` +${pkg.captures.length - 1}` : "";
      return {
        prefix,
        text: `capture ${shortId(first.captureId)}${more}`,
        mono: true,
        title: pkg.captures.map((capture) => capture.captureId).join(", "),
      };
    }
  }
}

/**
 * "Contents": "{floors} · {rooms} rooms · {files} files · {size}"; the rooms part only with the
 * spatial report's floor facts.
 */
export function contentsLine(pkg: PackageSummary): string {
  const modes = pkg.captures.map((capture) => capture.mode);
  const parts = [plural(pkg.captures.length, areaNoun(modes))];
  const floors = pkg.report?.floors;
  if (floors !== undefined && floors.length > 0) {
    const rooms = floors.reduce((sum, floor) => sum + floor.roomsScanned, 0);
    parts.push(plural(rooms, "room"));
  }
  parts.push(plural(pkg.totals.files, "file"));
  parts.push(formatBytes(pkg.totals.bytes));
  return parts.join(" · ");
}

/** When the checks finished, for the "Checked" column; undefined before a finished run. */
export function checkedAt(pkg: PackageSummary): string | undefined {
  if (pkg.verdict !== undefined) {
    return pkg.checks?.finishedAt ?? pkg.verdict.evaluatedAt;
  }
  return pkg.checks?.status === "completed" ? pkg.checks.finishedAt : undefined;
}

/** The status words under "What revision N adds" of a station revision without a verdict. */
export function revisionStateText(pkg: PackageSummary): string {
  switch (pkg.status) {
    case "uploading":
      return "uploading from the phone, not checked yet";
    case "check_error":
      return "sealed, checks did not finish";
    default:
      return "sealed, checks running";
  }
}

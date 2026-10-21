// npm run record-report --workspace @chapter/fixtures [-- --check]
// Rewrites fixtures/report/424-west-end from the station checks run on the generated sample-424
// package (run `npm run generate` first when the package changed). With --check it writes
// nothing, names every file that would change and exits 1 if any would.

import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, relative } from "node:path";
import { repoRoot } from "./json.js";
import {
  REPORT_OUTCOMES,
  recordReportVerdicts,
  reportDir,
  reportVerdictFileName,
  reportVerdictText,
} from "./report.js";

const check = process.argv.slice(2).includes("--check");
const verdicts = recordReportVerdicts();
const changed: string[] = [];

for (const outcome of REPORT_OUTCOMES) {
  const path = join(reportDir, reportVerdictFileName(outcome));
  const text = await reportVerdictText(verdicts[outcome]);
  if (existsSync(path) && readFileSync(path, "utf8") === text) {
    continue;
  }
  changed.push(relative(repoRoot, path));
  if (!check) {
    mkdirSync(reportDir, { recursive: true });
    writeFileSync(path, text);
  }
}

if (changed.length === 0) {
  console.log("fixtures/report/424-west-end is up to date");
} else if (check) {
  console.error(`out of date (run npm run record-report): ${changed.join(", ")}`);
  process.exitCode = 1;
} else {
  console.log(`recorded ${changed.join(", ")}`);
}

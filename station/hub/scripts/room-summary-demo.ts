// Writes the room summary of a package folder, and the brief section written from it, without a
// station: the same code the publisher runs, on the capture models under "Original Exports".
//
//   npm run room-summary:demo --workspace station/hub -- [--package <dir>] [--out <dir>]
//
// Defaults: the sample-424 fixture package, and ./room-summary-demo for the output.

import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import type { CaptureModel } from "@chapter/capture-contract";
import type { ReportFloorSource } from "../src/report/input.js";
import {
  buildRoomSummary,
  roomSummaryFileName,
  roomSummaryJson,
} from "../src/summary/room-summary.js";
import { spatialObservations } from "../src/summary/spatial-observations.js";

const repo = fileURLToPath(new URL("../../../", import.meta.url));
const { values } = parseArgs({
  options: {
    package: { type: "string", default: join(repo, "fixtures/generated/sample-424/package") },
    out: { type: "string", default: "room-summary-demo" },
  },
});
const packageDir = resolve(values.package);
const outDir = resolve(values.out);

const exportsDir = join(packageDir, "Original Exports");
if (!existsSync(exportsDir)) {
  console.error(`No "Original Exports" folder in ${packageDir}`);
  process.exit(1);
}

const floors: ReportFloorSource[] = readdirSync(exportsDir)
  .sort()
  .flatMap((areaKey) =>
    readdirSync(join(exportsDir, areaKey)).map((captureId) => {
      const file = join(exportsDir, areaKey, captureId, "capture-model.json");
      if (!existsSync(file)) {
        return { captureId, areaKey, model: { status: "absent" as const } };
      }
      try {
        const model = JSON.parse(readFileSync(file, "utf8")) as CaptureModel;
        return { captureId, areaKey, model: { status: "ok" as const, model } };
      } catch {
        return { captureId, areaKey, model: { status: "unreadable" as const } };
      }
    }),
  );

const summary = buildRoomSummary({ packageId: "demo", dealId: "demo", floors });
mkdirSync(outDir, { recursive: true });
const jsonPath = join(outDir, roomSummaryFileName());
const textPath = join(outDir, "spatial-observations.txt");
writeFileSync(jsonPath, roomSummaryJson(summary));
writeFileSync(textPath, spatialObservations(summary));

const totals = summary.totals;
console.log(
  `${totals.rooms} rooms, ${totals.floorAreaSqFt} sq ft, ${totals.paintableWallAreaSqFt} sq ft of ` +
    `paintable wall, ${totals.baseboardFt} ft of baseboard`,
);
console.log(`Wrote ${jsonPath}`);
console.log(`Wrote ${textPath}`);

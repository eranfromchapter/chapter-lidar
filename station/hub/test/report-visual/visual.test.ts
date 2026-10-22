// Visual snapshots and the black-and-white proof of the spatial report (spec 11.3; SR-AC5,
// SR-AC6). Each scenario page is rasterized with `pdftoppm -r 96` (792 pt -> 1056 px, the
// artboards' size) and compared with __snapshots__/{platform}/{scenario}.png by pixelmatch
// (threshold 0.1, at most 0.5 % of the pixels differ). Rasterizers differ between platforms, so
// each platform keeps its own snapshots; a platform without them skips the comparison with a
// notice. Record or update: UPDATE_REPORT_SNAPSHOTS=1 npm test -w @chapter/station-hub.
//
// pdftoppm (poppler-utils) is required in CI; locally the test is skipped without it.
// The B&W assertions read greyscale rasters (`pdftoppm -gray`): the three room fill greys differ
// by at least 3 % lightness and the blocked glyph stays dark.

import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { before, describe, it } from "node:test";
import { fileURLToPath } from "node:url";
import type { CaptureRecord, Finding, Verdict } from "@chapter/capture-contract";
import pixelmatch from "pixelmatch";
import { PNG } from "pngjs";
import { renderSpatialReport } from "../../src/report/index.js";
import type { SpatialReportInput } from "../../src/report/input.js";
import type { PageSpec } from "../../src/report/pages/index-of-pages.js";
import { COLOR } from "../../src/report/tokens.js";
import {
  fixtureInput,
  input424,
  layoutOf,
  manyObjects,
  syntheticInput,
  verdict424,
} from "../report/support.js";

const SNAPSHOTS = fileURLToPath(new URL(`./__snapshots__/${process.platform}/`, import.meta.url));
const UPDATE = process.env.UPDATE_REPORT_SNAPSHOTS === "1";
const MAX_DIFF = 0.005;

function hasPdftoppm(): boolean {
  try {
    execFileSync("pdftoppm", ["-v"], { stdio: "ignore" });
    return true;
  } catch {
    return false;
  }
}

const POPPLER = hasPdftoppm();
if (!POPPLER && process.env.CI !== undefined) {
  throw new Error("pdftoppm (poppler-utils) is required in CI for the report snapshots");
}
const work = mkdtempSync(join(tmpdir(), "report-visual-"));

/** One page of a PDF at 96 dpi, colour or grey. */
function rasterize(pdf: Uint8Array, page: number, gray = false): PNG {
  const file = join(work, `in-${Date.now()}-${Math.random().toString(16).slice(2)}.pdf`);
  writeFileSync(file, pdf);
  const prefix = `${file}.p${page}${gray ? "g" : ""}`;
  execFileSync("pdftoppm", [
    "-r",
    "96",
    "-png",
    ...(gray ? ["-gray"] : []),
    "-f",
    String(page),
    "-l",
    String(page),
    "-singlefile",
    file,
    prefix,
  ]);
  return PNG.sync.read(readFileSync(`${prefix}.png`));
}

// MARK: Scenarios

type Pick = (pages: readonly PageSpec[]) => number;
const first =
  (kind: PageSpec["kind"], nth = 0, room?: number): Pick =>
  (pages) => {
    const matches = pages
      .map((page, i) => ({ page, i }))
      .filter(
        ({ page }) =>
          page.kind === kind && (room === undefined || ("room" in page && page.room === room)),
      );
    const found = matches[nth];
    if (found === undefined) {
      throw new Error(`no ${kind} page ${nth}`);
    }
    return found.i + 1;
  };

function withoutCompass(record: CaptureRecord): CaptureRecord {
  for (const capture of record.captures) {
    delete capture.heading;
    delete capture.headingAccuracy;
    delete capture.headingSource;
    delete capture.headingRecordedAt;
    delete capture.headingIssue;
  }
  return record;
}

function secondFloorApproximate(record: CaptureRecord): CaptureRecord {
  const floor2 = record.captures[1];
  if (floor2 !== undefined) {
    delete floor2.headingIssue;
    Object.assign(floor2, {
      heading: 31.6,
      headingAccuracy: 18,
      headingSource: "magnetic",
      headingRecordedAt: floor2.capturedAt,
    });
  }
  return record;
}

function sixtyFindings(): Verdict {
  const verdict = verdict424("blocked");
  const extra: Finding[] = Array.from({ length: 60 }, (_, i) => ({
    ruleId: "manifest.fingerprints",
    severity: "blocker",
    message: `File ${i + 1} does not match its manifest fingerprint.`,
    filePath: `Original Exports/floor-1/33ede7f4-cfcb-4cd6-9af5-7daffee829a9/file-${i + 1}.json`,
    measured: `sha256 differs (size ${1200 + i} bytes)`,
    expected: "sha256 and size equal the manifest",
    nextAction: "Re-seal the package on the phone and upload it again.",
  }));
  return { ...verdict, findings: [...verdict.findings, ...extra] };
}

const LONG_NAME = "Primary bedroom suite with walk-in closet, dressing area and reading nook";

interface Scenario {
  readonly name: string;
  readonly input: () => Promise<SpatialReportInput>;
  readonly page: Pick;
  /** Also compared in greyscale (B&W proof). */
  readonly gray?: boolean;
}

const twoFloors = () =>
  fixtureInput("two-floor-house", verdict424("ready"), secondFloorApproximate);

const SCENARIOS: readonly Scenario[] = [
  { name: "1f-cover-limited", input: () => input424("limited"), page: first("cover"), gray: true },
  { name: "1g-cover-ready", input: () => input424("ready"), page: first("cover") },
  {
    name: "1h-cover-blocked-not-verified",
    input: () => fixtureInput("sample-424", verdict424("blocked"), withoutCompass),
    page: first("cover"),
  },
  { name: "1i-cover-two-floors", input: twoFloors, page: first("cover") },
  { name: "1k-plan-floor-1", input: () => input424("limited"), page: first("plan") },
  { name: "1l-plan-floor-2", input: twoFloors, page: first("plan", 1) },
  { name: "1n-schedule", input: () => input424("limited"), page: first("schedule"), gray: true },
  { name: "1p-checks-limited", input: () => input424("limited"), page: first("checks") },
  { name: "1q-checks-ready", input: () => input424("ready"), page: first("checks") },
  {
    name: "1r-checks-blocked",
    input: () => input424("blocked"),
    page: first("checks"),
    gray: true,
  },
  {
    name: "checks-continuation-60-findings",
    input: async () =>
      syntheticInput([{ label: "Floor 1", rooms: [{ label: "Living room", w: 5, d: 4 }] }], {
        verdict: sixtyFindings(),
      }),
    page: first("checks", 1),
  },
  {
    name: "1t-room-living",
    input: () => input424("limited"),
    page: first("room", 0, 1),
    gray: true,
  },
  { name: "1w-room-kitchen", input: () => input424("limited"), page: first("room", 0, 6) },
  { name: "1x-room-closet", input: () => input424("limited"), page: first("room", 0, 11) },
  { name: "1y-room-4-unlabeled", input: () => input424("limited"), page: first("room", 0, 10) },
  ...[0, 1].map((nth) => ({
    name: `1${nth === 0 ? "z" : "aa"}-room-long-name-27-items`,
    input: async () =>
      syntheticInput([
        {
          label: "Floor 1",
          rooms: [
            { label: LONG_NAME, w: 6.2, d: 4.8, objects: manyObjects(25), doors: 1, windows: 1 },
          ],
        },
      ]),
    page: first("room", nth),
  })),
  { name: "1u-photos-living", input: () => input424("limited"), page: first("photos", 0, 1) },
  { name: "package-record", input: () => input424("limited"), page: first("record") },
];

// MARK: Snapshot comparison

const renders = new Map<string, Promise<{ pdf: Buffer; pages: PageSpec[] }>>();
function renderOnce(scenario: Scenario): Promise<{ pdf: Buffer; pages: PageSpec[] }> {
  // Scenarios with the same input function share one render.
  const key = scenario.input.toString();
  let found = renders.get(key);
  if (found === undefined) {
    found = (async () => {
      const input = await scenario.input();
      const report = await renderSpatialReport(input);
      return { pdf: report.bytes, pages: layoutOf(input).pages };
    })();
    renders.set(key, found);
  }
  return found;
}

function compare(name: string, actual: PNG): { skipped?: string } {
  const file = join(SNAPSHOTS, `${name}.png`);
  if (UPDATE) {
    mkdirSync(SNAPSHOTS, { recursive: true });
    writeFileSync(file, PNG.sync.write(actual));
    return {};
  }
  if (!existsSync(file)) {
    return {
      skipped: `no ${process.platform} snapshot ${name}.png (record with UPDATE_REPORT_SNAPSHOTS=1)`,
    };
  }
  const expected = PNG.sync.read(readFileSync(file));
  assert.deepEqual([actual.width, actual.height], [expected.width, expected.height], name);
  const diff = new PNG({ width: actual.width, height: actual.height });
  const different = pixelmatch(expected.data, actual.data, diff.data, actual.width, actual.height, {
    threshold: 0.1,
  });
  const share = different / (actual.width * actual.height);
  if (share > MAX_DIFF) {
    writeFileSync(join(work, `${name}-actual.png`), PNG.sync.write(actual));
    writeFileSync(join(work, `${name}-diff.png`), PNG.sync.write(diff));
  }
  assert.ok(
    share <= MAX_DIFF,
    `${name}: ${(share * 100).toFixed(2)} % of the pixels differ (actual and diff in ${work})`,
  );
  return {};
}

describe("report snapshots", { skip: POPPLER ? false : "pdftoppm not installed" }, () => {
  for (const scenario of SCENARIOS) {
    it(scenario.name, async (t) => {
      const { pdf, pages } = await renderOnce(scenario);
      const page = scenario.page(pages);
      const colour = compare(scenario.name, rasterize(pdf, page));
      if (colour.skipped !== undefined) {
        t.skip(colour.skipped);
        return;
      }
      if (scenario.gray === true) {
        compare(`${scenario.name}-gray`, rasterize(pdf, page, true));
      }
    });
  }
});

// MARK: B&W proof

/** Grey value at each pixel whose colour raster pixel is `hex` (within 2 per channel). */
function greysWhere(colour: PNG, gray: PNG, hex: string): number[] {
  const r = Number.parseInt(hex.slice(1, 3), 16);
  const g = Number.parseInt(hex.slice(3, 5), 16);
  const b = Number.parseInt(hex.slice(5, 7), 16);
  const out: number[] = [];
  for (let i = 0; i < colour.data.length; i += 4) {
    if (
      Math.abs((colour.data[i] as number) - r) <= 2 &&
      Math.abs((colour.data[i + 1] as number) - g) <= 2 &&
      Math.abs((colour.data[i + 2] as number) - b) <= 2
    ) {
      out.push(gray.data[i] as number);
    }
  }
  return out;
}

const median = (values: readonly number[]) => {
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.floor(sorted.length / 2)] as number;
};

describe("black-and-white proof", { skip: POPPLER ? false : "pdftoppm not installed" }, () => {
  let cover: { colour: PNG; gray: PNG };
  let checks: { colour: PNG; gray: PNG };

  before(async () => {
    const limited = await renderOnce(SCENARIOS[0] as Scenario);
    cover = { colour: rasterize(limited.pdf, 1), gray: rasterize(limited.pdf, 1, true) };
    const blocked = await renderOnce(
      SCENARIOS.find((s) => s.name === "1r-checks-blocked") as Scenario,
    );
    const page = first("checks")(blocked.pages);
    checks = { colour: rasterize(blocked.pdf, page), gray: rasterize(blocked.pdf, page, true) };
  });

  it("keeps the three room fills apart in grey (at least 3 % lightness)", () => {
    const levels = [COLOR.nude, COLOR.wet, COLOR.ground].map((hex) => {
      const greys = greysWhere(cover.colour, cover.gray, hex);
      assert.ok(greys.length > 300, `${hex}: ${greys.length} px`);
      return median(greys);
    });
    const [habitable, wet, other] = levels as [number, number, number];
    assert.ok(wet - habitable >= 0.03 * 255, `habitable ${habitable} wet ${wet}`);
    assert.ok(other - wet >= 0.03 * 255, `wet ${wet} other ${other}`);
  });

  it("keeps the blocked glyph and word dark on the page", () => {
    const greys = greysWhere(checks.colour, checks.gray, COLOR.blocked);
    assert.ok(greys.length > 50, `${greys.length} px`);
    const background = median(greysWhere(checks.colour, checks.gray, COLOR.surface));
    assert.ok(median(greys) < 128, `blocked grey ${median(greys)}`);
    assert.ok(background - median(greys) > 0.5 * 255, `background ${background}`);
  });
});

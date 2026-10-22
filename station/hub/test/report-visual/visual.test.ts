// Visual snapshots and the black-and-white proof of the spatial report (spec 11.3; SR-AC5,
// SR-AC6). Each scenario page is rasterized with `pdftoppm -r 96` (792 pt -> 1056 px, the
// artboards' size) and compared with __snapshots__/{scenario}.png by pixelmatch (threshold 0.1,
// at most 0.5 % of the pixels differ). Record or update:
//   UPDATE_REPORT_SNAPSHOTS=1 npm test -w @chapter/station-hub
//
// The snapshots are the same on every platform: Inter is embedded in the report, and the two
// PDF standard fonts the report does not embed (Times-Roman, Courier) are drawn from fixed font
// files instead of whatever the machine has. pdftoppm runs with its own fontconfig file
// (FONTCONFIG_FILE) that knows only Tinos and Cousine (metric twins of Times and Courier, from
// the @fontsource devDependencies, WOFF2 -> TrueType with wawoff2) and maps Times and Courier to
// them. A platform whose rasterizer still differs can keep its own snapshots in
// __snapshots__/{platform}/ (UPDATE_REPORT_SNAPSHOTS=platform); they are used when present.
//
// pdftoppm (poppler-utils) is required in CI; locally the tests are skipped without it. A
// missing snapshot fails (never a skip). A missing or differing page is written, with its diff,
// to REPORT_SNAPSHOT_OUT (CI keeps it as an artifact), else to a temp folder.
// The B&W assertions read greyscale rasters (`pdftoppm -gray`): the three room fill greys differ
// by at least 3 % lightness and the blocked glyph stays dark.

import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
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

const SNAPSHOTS = fileURLToPath(new URL("./__snapshots__/", import.meta.url));
const PLATFORM_SNAPSHOTS = join(SNAPSHOTS, process.platform);
const UPDATE = process.env.UPDATE_REPORT_SNAPSHOTS;
const CI = process.env.CI !== undefined && process.env.CI !== "" && process.env.CI !== "false";
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
if (!POPPLER && CI) {
  throw new Error("pdftoppm (poppler-utils) is required in CI for the report snapshots");
}
const work = mkdtempSync(join(tmpdir(), "report-visual-"));
const out = process.env.REPORT_SNAPSHOT_OUT ?? work;

// MARK: Fonts for the PDF standard fonts

const require = createRequire(import.meta.url);
const wawoff2 = require("wawoff2") as { decompress(data: Uint8Array): Promise<Uint8Array> };

/**
 * A fontconfig file that knows only Tinos (for Times) and Cousine (for Courier), so pdftoppm
 * draws the report's standard-font text with the same glyphs on every machine.
 */
async function standardFontsConfig(): Promise<string> {
  const dir = join(work, "fonts");
  mkdirSync(dir, { recursive: true });
  const fonts = [
    ["@fontsource/tinos/files/tinos-latin-400-normal.woff2", "Tinos-Regular.ttf"],
    ["@fontsource/cousine/files/cousine-latin-400-normal.woff2", "Cousine-Regular.ttf"],
  ] as const;
  for (const [source, name] of fonts) {
    writeFileSync(join(dir, name), await wawoff2.decompress(readFileSync(require.resolve(source))));
  }
  const xml = (text: string) =>
    text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  const alias = (families: readonly string[], to: string) =>
    families
      .map(
        (family) =>
          `  <alias binding="same"><family>${family}</family><prefer><family>${to}</family></prefer></alias>`,
      )
      .join("\n");
  const config = join(work, "fonts.conf");
  writeFileSync(
    config,
    [
      `<?xml version="1.0"?>`,
      `<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">`,
      `<fontconfig>`,
      `  <dir>${xml(dir)}</dir>`,
      `  <cachedir>${xml(join(work, "fontconfig-cache"))}</cachedir>`,
      alias(["Times", "Times-Roman", "Times New Roman"], "Tinos"),
      alias(["Courier", "Courier New"], "Cousine"),
      `</fontconfig>`,
      ``,
    ].join("\n"),
  );
  return config;
}

let fontsConfig: Promise<string> | undefined;

/** One page of a PDF at 96 dpi, colour or grey. */
async function rasterize(pdf: Uint8Array, page: number, gray = false): Promise<PNG> {
  fontsConfig ??= standardFontsConfig();
  const env = { ...process.env, FONTCONFIG_FILE: await fontsConfig };
  const file = join(work, `in-${Date.now()}-${Math.random().toString(16).slice(2)}.pdf`);
  writeFileSync(file, pdf);
  const prefix = `${file}.p${page}${gray ? "g" : ""}`;
  execFileSync(
    "pdftoppm",
    [
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
    ],
    { env },
  );
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

function compare(name: string, actual: PNG): void {
  const own = join(PLATFORM_SNAPSHOTS, `${name}.png`);
  const shared = join(SNAPSHOTS, `${name}.png`);
  if (UPDATE === "1" || UPDATE === "platform") {
    const dir = UPDATE === "platform" ? PLATFORM_SNAPSHOTS : SNAPSHOTS;
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, `${name}.png`), PNG.sync.write(actual));
    return;
  }
  const file = existsSync(own) ? own : shared;
  if (!existsSync(file)) {
    mkdirSync(out, { recursive: true });
    writeFileSync(join(out, `${name}.png`), PNG.sync.write(actual));
    assert.fail(
      `no snapshot ${name}.png (the page is in ${out}; record with UPDATE_REPORT_SNAPSHOTS=1)`,
    );
  }
  const expected = PNG.sync.read(readFileSync(file));
  assert.deepEqual([actual.width, actual.height], [expected.width, expected.height], name);
  const diff = new PNG({ width: actual.width, height: actual.height });
  const different = pixelmatch(expected.data, actual.data, diff.data, actual.width, actual.height, {
    threshold: 0.1,
  });
  const share = different / (actual.width * actual.height);
  if (share > MAX_DIFF) {
    mkdirSync(out, { recursive: true });
    writeFileSync(join(out, `${name}.png`), PNG.sync.write(actual));
    writeFileSync(join(out, `${name}-diff.png`), PNG.sync.write(diff));
  }
  assert.ok(
    share <= MAX_DIFF,
    `${name}: ${(share * 100).toFixed(2)} % of the pixels differ (actual and diff in ${out})`,
  );
}

describe("report snapshots", { skip: POPPLER ? false : "pdftoppm not installed" }, () => {
  for (const scenario of SCENARIOS) {
    it(scenario.name, async () => {
      const { pdf, pages } = await renderOnce(scenario);
      const page = scenario.page(pages);
      compare(scenario.name, await rasterize(pdf, page));
      if (scenario.gray === true) {
        compare(`${scenario.name}-gray`, await rasterize(pdf, page, true));
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
    cover = {
      colour: await rasterize(limited.pdf, 1),
      gray: await rasterize(limited.pdf, 1, true),
    };
    const blocked = await renderOnce(
      SCENARIOS.find((s) => s.name === "1r-checks-blocked") as Scenario,
    );
    const page = first("checks")(blocked.pages);
    checks = {
      colour: await rasterize(blocked.pdf, page),
      gray: await rasterize(blocked.pdf, page, true),
    };
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

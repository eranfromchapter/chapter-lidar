// The station's spatial report (spatial-report spec): rendered by the worker after the checks,
// from the verdict, the capture record, the capture models, the field controls and the photos.
// US Letter landscape, pdfkit, Inter (embedded) with Times and Courier, the real Chapter logo.
// Same input, same bytes: dates come from the verdict and nothing reads the clock.

import { createHash } from "node:crypto";
import { checkCounts, checkRows, type Verdict } from "@chapter/capture-contract";
import PDFDocument from "pdfkit";
import { registerFonts } from "./fonts.js";
import type { RenderedReport, SpatialReportInput } from "./input.js";
import { Canvas } from "./layout/canvas.js";
import { buildModel, reportFloors } from "./model.js";
import { paginate } from "./paginate.js";
import { drawChecksPage } from "./pages/checks.js";
import type { PageContext } from "./pages/context.js";
import { coverSentence, drawCover } from "./pages/cover.js";
import { PageIndex, type PageSpec } from "./pages/index-of-pages.js";
import { drawPhotosPage } from "./pages/photos.js";
import { drawContentsPage, drawPlanPage } from "./pages/plan.js";
import { drawRecordPage } from "./pages/record.js";
import { drawRoomPage } from "./pages/room.js";
import { drawSchedulePage } from "./pages/schedule.js";
import { REPORT_TITLE } from "./words.js";

export {
  REPORT_NOT_CERTIFICATION,
  REPORT_STATEMENT_CHECKS,
  REPORT_STATEMENT_FULL,
  REPORT_STATEMENT_SHORT,
  REPORT_TITLE,
} from "./words.js";
export { DEFAULT_REPORT_TIME_ZONE, formatBytes, isTimeZone, pdfSafeText } from "./format.js";
export { coverSentence } from "./pages/cover.js";
export type {
  RenderedReport,
  ReportFile,
  ReportFileLocation,
  ReportFloor,
  ReportFloorSource,
  ReportInput,
  ReportModel,
  ReportPhoto,
  SpatialReportInput,
} from "./input.js";

/** The outcome in plain words: the cover sentence (first capture checks page `checksPage`). */
export function outcomeInPlainWords(verdict: Verdict, checksPage: number): string {
  return coverSentence(verdict, checksPage, checkCounts(checkRows(verdict)).blockers);
}

function drawPage(ctx: PageContext, page: PageSpec): void {
  switch (page.kind) {
    case "cover":
      drawCover(ctx);
      return;
    case "contents":
      drawContentsPage(ctx, page.columns, page.note);
      return;
    case "plan":
      drawPlanPage(ctx, page.floor, page.contents);
      return;
    case "schedule":
      drawSchedulePage(ctx, page.rows, page.first, page.last);
      return;
    case "checks":
      drawChecksPage(ctx, page);
      return;
    case "room":
      drawRoomPage(ctx, page);
      return;
    case "photos":
      drawPhotosPage(ctx, page);
      return;
    case "record":
      drawRecordPage(ctx, page);
      return;
  }
}

/** Renders the spatial report. Deterministic for the same input. */
export async function renderSpatialReport(input: SpatialReportInput): Promise<RenderedReport> {
  const verdict = input.verdict;
  const evaluated = new Date(verdict.evaluatedAt);
  const model = buildModel(input);
  const doc = new PDFDocument({
    size: [792, 612],
    margin: 0,
    autoFirstPage: false,
    pdfVersion: "1.7",
    lang: "en-US",
    displayTitle: true,
    font: "Times-Roman",
    info: {
      Title: `Spatial report · ${model.title} · revision ${verdict.revision}`,
      Author: "Chapter Capture station",
      Subject: `Spatial report and station verdict (${verdict.outcome}) for package ${input.packageId}`,
      Creator: "Chapter Capture station",
      Producer: "Chapter Capture station",
      Keywords: REPORT_TITLE,
      CreationDate: evaluated,
      ModDate: evaluated,
    },
  });
  const chunks: Buffer[] = [];
  const done = new Promise<Buffer>((resolve, reject) => {
    doc.on("data", (chunk: Buffer) => chunks.push(chunk));
    doc.on("end", () => resolve(Buffer.concat(chunks)));
    doc.on("error", reject);
  });
  registerFonts(doc);
  const canvas = new Canvas(doc);
  const pages = paginate(canvas, model);
  const index = new PageIndex(pages);
  pages.forEach((page, i) => {
    doc.addPage({ size: [792, 612], margin: 0 });
    drawPage({ canvas, model, index, page: i + 1 }, page);
  });
  doc.end();
  const bytes = await done;
  return {
    bytes,
    sha256: createHash("sha256").update(bytes).digest("hex"),
    pages: pages.length,
    checksPage: index.checks,
    recordPage: index.record,
    name: input.reportLocation.name,
    floors: reportFloors(model),
  };
}

/** Deprecated: the v1 name. Renders the spatial report and returns its bytes. */
export async function renderVerdictReport(input: SpatialReportInput): Promise<Buffer> {
  return (await renderSpatialReport(input)).bytes;
}

// What every page renderer gets: the canvas, the model, the page list and its page numbers,
// and the page frame (header and footer) drawn the same way on every page.

import type { Canvas, Run } from "../layout/canvas.js";
import { drawBackground, drawFooter, drawHeader } from "../layout/page.js";
import { longDate } from "../format.js";
import type { Model } from "../model.js";
import { COLOR, FONT, TYPE } from "../tokens.js";
import {
  KICKER,
  REPORT_STATEMENT_CHECKS,
  REPORT_STATEMENT_FULL,
  REPORT_STATEMENT_SHORT,
  WORDS,
} from "../words.js";
import type { PageIndex } from "./index-of-pages.js";

export interface PageContext {
  readonly canvas: Canvas;
  readonly model: Model;
  readonly index: PageIndex;
  /** 1-based number of the page being drawn. */
  readonly page: number;
}

export type StatementKind = "full" | "checks" | "short";

export interface FrameOptions {
  /** Kicker parts after "Spatial report". */
  readonly kicker: readonly string[];
  /** Cover: the address line gets the confirmation suffix. */
  readonly cover?: boolean;
  readonly statement: StatementKind;
  /** The capture the page shows (floor pages); undefined for visit-wide pages. */
  readonly captureId?: string;
}

/** "Spatial report · Floor plan · Floor 1". */
export function kicker(parts: readonly string[]): string {
  return [KICKER, ...parts].join(" · ");
}

/** The page frame: background, header and footer. */
export function drawFrame(ctx: PageContext, options: FrameOptions): void {
  const { canvas, model } = ctx;
  drawBackground(canvas);
  const record = model.input.captureRecord;
  let subline = model.addressLine;
  if (options.cover === true && record !== undefined) {
    const suffix = record.address.confirmedOnSite
      ? WORDS.addressConfirmed
      : WORDS.addressNotConfirmed;
    subline = subline === "" ? suffix : `${subline} · ${suffix}`;
  }
  drawHeader(canvas, { kicker: kicker(options.kicker), title: model.title, subline });

  const ink = { ...TYPE.caption, color: COLOR.ink };
  const mono = { ...ink, font: FONT.mono };
  const captures = model.floors.length;
  const line1: Run[] = [{ text: "Review link · ", style: ink }];
  if (options.captureId !== undefined || captures === 1) {
    const id = options.captureId ?? model.floors[0]?.captureId ?? "";
    line1.push({ text: "capture ", style: ink }, { text: id, style: mono });
  } else {
    line1.push({ text: "package ", style: ink }, { text: model.input.packageId, style: mono });
  }
  const parts: string[] = [];
  if (record !== undefined) {
    parts.push(`captured ${longDate(record.visitedAt, model.timeZone)}`);
  }
  parts.push(
    `report generated ${longDate(model.verdict.evaluatedAt, model.timeZone)}${options.cover === true ? " by the Chapter station" : ""}`,
  );
  line1.push({ text: ` · ${parts.join(" · ")}`, style: ink });
  const statement =
    options.statement === "full"
      ? REPORT_STATEMENT_FULL
      : options.statement === "checks"
        ? REPORT_STATEMENT_CHECKS
        : REPORT_STATEMENT_SHORT;
  drawFooter(canvas, {
    line1,
    statement,
    pageLabel: `${ctx.page} / ${ctx.index.total}`,
    reviewUrl: model.reviewUrl,
  });
}

/** The floor kicker: 1 floor `{label}`; 2+ floors `{label} of {n}` or `{label} · {i} of {n}`. */
export function floorKicker(model: Model, floorIndex: number): string {
  const floor = model.floors[floorIndex];
  const label = floor?.label ?? "";
  const n = model.floors.length;
  if (n <= 1) {
    return label;
  }
  return /^Floor \d+$/.test(label) ? `${label} of ${n}` : `${label} · ${floorIndex + 1} of ${n}`;
}

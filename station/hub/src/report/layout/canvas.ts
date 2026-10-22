// A thin layer over the pdfkit document: text measured and placed like the HTML artboards (CSS
// line boxes with half-leading, our own word wrap, tracking), filled rules and simple shapes.
//
// Line positioning: a line of style (size s, line height L) sits in a line box of height L; its
// baseline is at lineTop + (L - (asc - desc) * s / 1000) / 2 + asc * s / 1000, where asc and desc
// are the font's ascender and descender in 1/1000 em. For Inter they are the embedded font's
// (pdfkit reads them from the font); for Times and Courier they are the metrics browsers use for
// Times New Roman and Courier New, so serif titles and mono strings land where the artboards draw
// them (the PDF standard fonts' AFM metrics would put them about 2 pt higher).
//
// Every string passes pdfSafeText first; truncation appends "...".

import { pdfSafeText } from "../format.js";
import { FONT, type FontName, type TextStyle } from "../tokens.js";

type Doc = PDFKit.PDFDocument;

/** Ascender and descender (negative) in 1/1000 em used for line placement. */
const LINE_METRICS: Record<string, { asc: number; desc: number }> = {
  [FONT.serif]: { asc: 891.1, desc: -216.3 },
  [FONT.mono]: { asc: 832.5, desc: -300.3 },
};

export const ELLIPSIS = "...";

/** A run of one style inside a single line. */
export interface Run {
  readonly text: string;
  readonly style: TextStyle;
}

export interface LineOptions {
  /** Box width for center/right alignment. */
  readonly width?: number;
  readonly align?: "left" | "center" | "right";
  /** Link annotation over the drawn text. */
  readonly link?: string;
}

export interface BlockOptions extends LineOptions {
  readonly maxLines?: number;
}

export class Canvas {
  readonly #metrics = new Map<string, { asc: number; desc: number }>();

  constructor(readonly doc: Doc) {}

  // MARK: Text measurement

  #use(style: TextStyle): void {
    this.doc.font(style.font).fontSize(style.size);
  }

  #metricsOf(font: FontName): { asc: number; desc: number } {
    const fixed = LINE_METRICS[font];
    if (fixed !== undefined) {
      return fixed;
    }
    let found = this.#metrics.get(font);
    if (found === undefined) {
      this.doc.font(font);
      const loaded = (this.doc as unknown as { _font: { ascender: number; descender: number } })
        ._font;
      found = { asc: loaded.ascender, desc: loaded.descender };
      this.#metrics.set(font, found);
    }
    return found;
  }

  /** The string as drawn: WinAnsi-safe, upper-cased when the style says so. */
  prepare(text: string, style: TextStyle): string {
    const safe = pdfSafeText(text);
    return style.upper === true ? safe.toUpperCase() : safe;
  }

  /** Width of prepared text in `style`, tracking included (between characters). */
  measure(prepared: string, style: TextStyle): number {
    if (prepared.length === 0) {
      return 0;
    }
    this.#use(style);
    return this.doc.widthOfString(prepared, { characterSpacing: style.tracking ?? 0 });
  }

  /** Width of raw text (prepared first). */
  width(text: string, style: TextStyle): number {
    return this.measure(this.prepare(text, style), style);
  }

  /** Width of a line of runs. */
  runsWidth(runs: readonly Run[]): number {
    return runs.reduce((sum, run) => sum + this.width(run.text, run.style), 0);
  }

  /** Baseline offset from the top of the line box. */
  baselineOffset(style: TextStyle): number {
    const { asc, desc } = this.#metricsOf(style.font);
    return (style.line - ((asc - desc) * style.size) / 1000) / 2 + (asc * style.size) / 1000;
  }

  /** Cap-to-descender ink box of one line relative to the line top: [top, bottom]. */
  inkBox(style: TextStyle): [number, number] {
    const { asc, desc } = this.#metricsOf(style.font);
    const base = this.baselineOffset(style);
    return [base - (asc * style.size) / 1000, base - (desc * style.size) / 1000];
  }

  /** Prepared text cut to fit `width`, with "..." when cut. */
  truncate(prepared: string, style: TextStyle, width: number): string {
    if (this.measure(prepared, style) <= width + 1e-6) {
      return prepared;
    }
    let low = 0;
    let high = prepared.length;
    while (low < high) {
      const mid = Math.ceil((low + high) / 2);
      if (this.measure(prepared.slice(0, mid).trimEnd() + ELLIPSIS, style) <= width + 1e-6) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return prepared.slice(0, low).trimEnd() + ELLIPSIS;
  }

  /**
   * Greedy word wrap of raw text into lines no wider than `width`. A word longer than the width
   * breaks after "/" first, then anywhere. `maxLines` cuts the last kept line with "...".
   */
  wrap(text: string, style: TextStyle, width: number, maxLines?: number): string[] {
    const prepared = this.prepare(text, style);
    const lines: string[] = [];
    for (const paragraph of prepared.split("\n")) {
      const words = paragraph.split(" ").filter((word) => word.length > 0);
      let current = "";
      for (const word of words) {
        const candidate = current === "" ? word : `${current} ${word}`;
        if (this.measure(candidate, style) <= width + 1e-6) {
          current = candidate;
          continue;
        }
        if (current !== "") {
          lines.push(current);
        }
        if (this.measure(word, style) <= width + 1e-6) {
          current = word;
          continue;
        }
        const pieces = this.#breakWord(word, style, width);
        lines.push(...pieces.slice(0, -1));
        current = pieces[pieces.length - 1] ?? "";
      }
      lines.push(current);
    }
    if (maxLines !== undefined && lines.length > maxLines) {
      const kept = lines.slice(0, maxLines);
      const last = kept[maxLines - 1] ?? "";
      const rest = lines.slice(maxLines).join(" ");
      kept[maxLines - 1] = this.truncate(`${last} ${rest}`, style, width);
      if (!kept[maxLines - 1]?.endsWith(ELLIPSIS)) {
        kept[maxLines - 1] = this.truncate(`${last}${ELLIPSIS}`, style, width);
      }
      return kept;
    }
    return lines;
  }

  /**
   * Wraps a package path at "/" boundaries (spaces inside folder names never break), a segment
   * longer than the width anywhere.
   */
  wrapPath(path: string, style: TextStyle, width: number): string[] {
    const prepared = this.prepare(path, style);
    const segments = prepared.match(/[^/]*\/|[^/]+$/g) ?? [prepared];
    const lines: string[] = [];
    let current = "";
    for (const segment of segments) {
      if (this.measure(current + segment, style) <= width + 1e-6) {
        current += segment;
        continue;
      }
      if (current !== "") {
        lines.push(current);
      }
      if (this.measure(segment, style) <= width + 1e-6) {
        current = segment;
        continue;
      }
      const pieces = this.#breakWord(segment, style, width);
      lines.push(...pieces.slice(0, -1));
      current = pieces[pieces.length - 1] ?? "";
    }
    if (current !== "" || lines.length === 0) {
      lines.push(current);
    }
    return lines;
  }

  #breakWord(word: string, style: TextStyle, width: number): string[] {
    const pieces: string[] = [];
    let rest = word;
    while (this.measure(rest, style) > width + 1e-6 && rest.length > 1) {
      // Longest prefix ending after a "/" that fits, else the longest prefix that fits.
      let cut = 0;
      for (let i = 1; i < rest.length; i += 1) {
        if (this.measure(rest.slice(0, i), style) > width + 1e-6) {
          break;
        }
        cut = i;
      }
      const slash = rest.lastIndexOf("/", cut - 1);
      const at = slash > 0 ? slash + 1 : Math.max(1, cut);
      pieces.push(rest.slice(0, at));
      rest = rest.slice(at);
    }
    pieces.push(rest);
    return pieces;
  }

  /** Height of a wrapped block. */
  blockHeight(text: string, style: TextStyle, width: number, maxLines?: number): number {
    return this.wrap(text, style, width, maxLines).length * style.line;
  }

  // MARK: Text drawing

  /** Draws one prepared line with its line box top at `lineTop`. Returns the drawn width. */
  #drawPrepared(
    prepared: string,
    style: TextStyle,
    x: number,
    lineTop: number,
    options: LineOptions = {},
  ): number {
    const width = this.measure(prepared, style);
    let left = x;
    if (options.width !== undefined) {
      if (options.align === "right") {
        left = x + options.width - width;
      } else if (options.align === "center") {
        left = x + (options.width - width) / 2;
      }
    }
    if (prepared.length > 0) {
      this.#use(style);
      this.doc.fillColor(style.color);
      this.doc.text(prepared, left, lineTop + this.baselineOffset(style), {
        lineBreak: false,
        baseline: "alphabetic",
        characterSpacing: style.tracking ?? 0,
      });
    }
    if (options.link !== undefined && width > 0) {
      this.doc.link(left, lineTop, width, style.line, options.link);
    }
    return width;
  }

  /** Draws raw text as one line (no wrap); `maxWidth` truncates with "...". */
  line(
    text: string,
    style: TextStyle,
    x: number,
    lineTop: number,
    options: LineOptions & { maxWidth?: number } = {},
  ): number {
    let prepared = this.prepare(text, style);
    const limit = options.maxWidth ?? options.width;
    if (limit !== undefined) {
      prepared = this.truncate(prepared, style, limit);
    }
    return this.#drawPrepared(prepared, style, x, lineTop, options);
  }

  /**
   * Draws a line of runs sharing one baseline (the first run's line box), aligned in `width`.
   * Returns the drawn width.
   */
  runs(runs: readonly Run[], x: number, lineTop: number, options: LineOptions = {}): number {
    const first = runs[0];
    if (first === undefined) {
      return 0;
    }
    const total = this.runsWidth(runs);
    let left = x;
    if (options.width !== undefined) {
      if (options.align === "right") {
        left = x + options.width - total;
      } else if (options.align === "center") {
        left = x + (options.width - total) / 2;
      }
    }
    const baseline = lineTop + this.baselineOffset(first.style);
    let cursor = left;
    for (const run of runs) {
      const prepared = this.prepare(run.text, run.style);
      // Each run in its own line box whose baseline is the shared one.
      const top = baseline - this.baselineOffset(run.style);
      cursor += this.#drawPrepared(prepared, run.style, cursor, top);
    }
    if (options.link !== undefined && total > 0) {
      this.doc.link(left, lineTop, total, first.style.line, options.link);
    }
    return total;
  }

  /** Draws wrapped text from `top`; returns the height used. */
  block(
    text: string,
    style: TextStyle,
    x: number,
    top: number,
    width: number,
    options: BlockOptions = {},
  ): number {
    const lines = this.wrap(text, style, width, options.maxLines);
    lines.forEach((line, index) => {
      this.#drawPrepared(line, style, x, top + index * style.line, {
        width,
        align: options.align ?? "left",
        ...(options.link === undefined ? {} : { link: options.link }),
      });
    });
    return lines.length * style.line;
  }

  /** Draws already wrapped (prepared) lines. */
  lines(
    lines: readonly string[],
    style: TextStyle,
    x: number,
    top: number,
    width: number,
    align: "left" | "center" | "right" = "left",
  ): number {
    lines.forEach((line, index) => {
      this.#drawPrepared(line, style, x, top + index * style.line, { width, align });
    });
    return lines.length * style.line;
  }

  // MARK: Shapes

  /** Filled rectangle (rules are filled rectangles, as CSS borders are). */
  fillRect(x: number, y: number, width: number, height: number, color: string): void {
    this.doc.save().rect(x, y, width, height).fill(color).restore();
  }

  /** A horizontal rule `weight` thick whose top edge is at `y`. */
  rule(x: number, y: number, width: number, color: string, weight = 0.75): void {
    this.fillRect(x, y, width, weight, color);
  }

  /** Rounded rectangle border stroked on the box edge (CSS border inside the box). */
  roundedBorder(
    x: number,
    y: number,
    width: number,
    height: number,
    radius: number,
    weight: number,
    color: string,
  ): void {
    const inset = weight / 2;
    this.doc
      .save()
      .roundedRect(
        x + inset,
        y + inset,
        width - weight,
        height - weight,
        Math.max(0, radius - inset),
      )
      .lineWidth(weight)
      .strokeColor(color)
      .stroke()
      .restore();
  }

  roundedFill(
    x: number,
    y: number,
    width: number,
    height: number,
    radius: number,
    color: string,
  ): void {
    this.doc.save().roundedRect(x, y, width, height, radius).fill(color).restore();
  }
}

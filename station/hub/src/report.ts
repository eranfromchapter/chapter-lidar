// Verdict report PDF (pdfkit, built-in Helvetica and Courier only: no font files, no network).
//
// Contents: the outcome in plain words, the summary, the package and verdict ids, the result of
// every check, a findings table, limitations, next actions, the capture record, the file list
// with SHA-256 (where each file is in the HUB, or its station link when it is not uploaded) and
// the statement that this is not a certification of measurements.
//
// The built-in fonts use WinAnsi encoding: text is passed through pdfSafeText first, so a
// character the font cannot show becomes a close ASCII equivalent or "?".

import type { CaptureRecord, Verdict } from "@chapter/capture-contract";
import PDFDocument from "pdfkit";

/** Statement printed on every report, next to the verdict's own statement. */
export const REPORT_NOT_CERTIFICATION =
  "This report is not a certification of measurements or of any property model. It records an automated check of the intake package by the Chapter Capture station.";

export const REPORT_TITLE = "Chapter Capture verdict report";

/** Where one file of the package is after publishing. */
export type ReportFileLocation =
  | { readonly kind: "hub"; readonly folder: string; readonly name: string }
  | {
      readonly kind: "link";
      readonly url: string;
      readonly reason: "too_large" | "not_published";
    };

export interface ReportFile {
  readonly path: string;
  readonly role: string;
  readonly bytes: number;
  readonly sha256: string;
  readonly location: ReportFileLocation;
}

export interface ReportInput {
  readonly verdict: Verdict;
  readonly packageId: string;
  readonly dealId: string;
  readonly captureRecord?: CaptureRecord;
  /** Where this report itself is filed in the HUB. */
  readonly reportLocation: { readonly folder: string; readonly name: string };
  readonly files: readonly ReportFile[];
  /** Largest uploaded size, for the explanation of linked files. */
  readonly maxUploadBytes: number;
}

const OUTCOME_LABEL: Record<Verdict["outcome"], string> = {
  ready: "READY",
  limited: "LIMITED",
  blocked: "BLOCKED",
};

/** The outcome in plain words. */
export function outcomeInPlainWords(verdict: Verdict): string {
  const task = verdict.task.charAt(0).toLowerCase() + verdict.task.slice(1);
  switch (verdict.outcome) {
    case "ready":
      return `Ready: the package is ready for ${task}. The station found no blockers and no limitations.`;
    case "limited":
      return `Limited: the package can be used for ${task}, with the named limitations listed below.`;
    case "blocked":
      return `Blocked: missing or inconsistent information prevents ${task}. Resolve the blockers below and upload a new revision.`;
  }
}

const REPLACEMENTS: Record<string, string> = {
  "−": "-",
  "‐": "-",
  "‑": "-",
  "≤": "<=",
  "≥": ">=",
  "≈": "~",
  "→": "->",
  "←": "<-",
  "…": "...",
  "●": "*",
  "▲": "^",
  "■": "#",
  "′": "'",
  "″": '"',
  " ": " ",
  "\t": " ",
};

// Characters of WinAnsi (CP1252) outside Latin-1 that the built-in fonts can show.
const WIN_ANSI_EXTRA = new Set("€‚ƒ„†‡ˆ‰Š‹ŒŽ‘’“”•–—˜™š›œžŸ");

/** Text the built-in fonts can show: known symbols spelled in ASCII, anything else "?". */
export function pdfSafeText(text: string): string {
  let out = "";
  for (const char of text) {
    const code = char.codePointAt(0) ?? 0;
    const replacement = REPLACEMENTS[char];
    if (replacement !== undefined) {
      out += replacement;
    } else if (char === "\n" || (code >= 0x20 && code <= 0x7e) || (code >= 0xa1 && code <= 0xff)) {
      out += char;
    } else if (WIN_ANSI_EXTRA.has(char)) {
      out += char;
    } else {
      out += "?";
    }
  }
  return out;
}

function formatBytes(bytes: number): string {
  if (bytes < 1024) {
    return `${bytes} B`;
  }
  const units = ["KiB", "MiB", "GiB", "TiB"];
  let value = bytes / 1024;
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  return `${value.toFixed(1)} ${units[unit]} (${bytes} bytes)`;
}

interface Column {
  readonly header: string;
  readonly width: number;
}

const PAGE_MARGIN = 50;
const CELL_PAD = 3;
const BODY_FONT = "Helvetica";
const BOLD_FONT = "Helvetica-Bold";
const MONO_FONT = "Courier";

class ReportWriter {
  readonly doc: PDFKit.PDFDocument;
  readonly left = PAGE_MARGIN;
  readonly width: number;

  constructor(doc: PDFKit.PDFDocument) {
    this.doc = doc;
    this.width = doc.page.width - PAGE_MARGIN * 2;
  }

  get bottom(): number {
    return this.doc.page.height - PAGE_MARGIN;
  }

  ensure(height: number): void {
    if (this.doc.y + height > this.bottom) {
      this.doc.addPage();
      this.doc.y = PAGE_MARGIN;
    }
  }

  heading(text: string): void {
    this.ensure(40);
    this.doc.moveDown(0.6);
    this.doc.font(BOLD_FONT).fontSize(12).fillColor("#000000");
    this.doc.text(pdfSafeText(text), this.left, this.doc.y, { width: this.width });
    this.doc.moveDown(0.25);
  }

  paragraph(text: string, options: { font?: string; size?: number; color?: string } = {}): void {
    const safe = pdfSafeText(text);
    this.doc.font(options.font ?? BODY_FONT).fontSize(options.size ?? 9);
    this.ensure(this.doc.heightOfString(safe, { width: this.width }) + 2);
    this.doc.fillColor(options.color ?? "#000000");
    this.doc.text(safe, this.left, this.doc.y, { width: this.width });
    this.doc.fillColor("#000000");
  }

  bullets(items: readonly string[], empty: string): void {
    if (items.length === 0) {
      this.paragraph(empty);
      return;
    }
    for (const item of items) {
      this.paragraph(`- ${item}`);
      this.doc.moveDown(0.15);
    }
  }

  keyValues(rows: ReadonlyArray<readonly [string, string]>): void {
    const keyWidth = 120;
    this.doc.fontSize(9);
    for (const [key, value] of rows) {
      const safeValue = pdfSafeText(value);
      this.doc.font(BODY_FONT);
      const height = Math.max(
        this.doc.heightOfString(safeValue, { width: this.width - keyWidth }),
        this.doc.heightOfString(key, { width: keyWidth }),
      );
      this.ensure(height + 2);
      const y = this.doc.y;
      this.doc.font(BOLD_FONT).text(pdfSafeText(key), this.left, y, { width: keyWidth - 6 });
      this.doc.font(BODY_FONT).text(safeValue, this.left + keyWidth, y, {
        width: this.width - keyWidth,
      });
      this.doc.y = y + height + 2;
    }
  }

  #rowHeight(cells: readonly string[], columns: readonly Column[], font: string): number {
    this.doc.font(font).fontSize(8);
    let height = 0;
    cells.forEach((cell, index) => {
      const width = (columns[index]?.width ?? 50) - CELL_PAD * 2;
      height = Math.max(height, this.doc.heightOfString(cell, { width }));
    });
    return height + CELL_PAD * 2;
  }

  #drawRow(
    cells: readonly string[],
    columns: readonly Column[],
    font: string,
    fill?: string,
  ): void {
    const height = this.#rowHeight(cells, columns, font);
    const y = this.doc.y;
    if (fill !== undefined) {
      this.doc.save().rect(this.left, y, this.width, height).fill(fill).restore();
    }
    this.doc.font(font).fontSize(8).fillColor("#000000");
    let x = this.left;
    cells.forEach((cell, index) => {
      const width = columns[index]?.width ?? 50;
      this.doc.text(cell, x + CELL_PAD, y + CELL_PAD, { width: width - CELL_PAD * 2 });
      x += width;
    });
    this.doc
      .save()
      .moveTo(this.left, y + height)
      .lineTo(this.left + this.width, y + height)
      .lineWidth(0.5)
      .strokeColor("#999999")
      .stroke()
      .restore();
    this.doc.y = y + height;
  }

  table(columns: readonly Column[], rows: ReadonlyArray<readonly string[]>): void {
    const header = columns.map((column) => pdfSafeText(column.header));
    const headerHeight = this.#rowHeight(header, columns, BOLD_FONT);
    this.ensure(headerHeight + 30);
    this.#drawRow(header, columns, BOLD_FONT, "#e8e8e8");
    for (const row of rows) {
      const cells = row.map(pdfSafeText);
      const height = this.#rowHeight(cells, columns, BODY_FONT);
      if (this.doc.y + height > this.bottom) {
        this.doc.addPage();
        this.doc.y = PAGE_MARGIN;
        this.#drawRow(header, columns, BOLD_FONT, "#e8e8e8");
      }
      this.#drawRow(cells, columns, BODY_FONT);
    }
  }

  fileEntry(file: ReportFile, maxUploadBytes: number): void {
    const path = pdfSafeText(file.path);
    const meta = pdfSafeText(`${file.role}, ${formatBytes(file.bytes)}`);
    let where: string;
    let link: string | undefined;
    switch (file.location.kind) {
      case "hub":
        where = `In the HUB: ${file.location.folder}/${file.location.name}`;
        break;
      case "link":
        where =
          file.location.reason === "too_large"
            ? `Not uploaded (over ${formatBytes(maxUploadBytes)}). Station link, Entra sign-in required: ${file.location.url}`
            : `Kept in the station. Station link, Entra sign-in required: ${file.location.url}`;
        link = file.location.url;
        break;
    }
    const safeWhere = pdfSafeText(where);
    this.doc.font(BOLD_FONT).fontSize(8);
    const h1 = this.doc.heightOfString(`${path} (${meta})`, { width: this.width });
    this.doc.font(MONO_FONT).fontSize(7);
    const h2 = this.doc.heightOfString(`SHA-256 ${file.sha256}`, { width: this.width });
    this.doc.font(BODY_FONT).fontSize(7.5);
    const h3 = this.doc.heightOfString(safeWhere, { width: this.width });
    this.ensure(h1 + h2 + h3 + 8);
    this.doc.font(BOLD_FONT).fontSize(8).text(`${path} (${meta})`, this.left, this.doc.y, {
      width: this.width,
    });
    this.doc.font(MONO_FONT).fontSize(7).text(`SHA-256 ${file.sha256}`, this.left, this.doc.y, {
      width: this.width,
    });
    this.doc
      .font(BODY_FONT)
      .fontSize(7.5)
      .text(safeWhere, this.left, this.doc.y, {
        width: this.width,
        ...(link === undefined ? {} : { link }),
      });
    this.doc.y += 5;
  }
}

function captureRecordRows(record: CaptureRecord): Array<[string, string]> {
  const device = record.device.marketingName
    ? `${record.device.marketingName} (${record.device.model}), ${record.device.osName} ${record.device.osVersion}, LiDAR ${record.device.hasLidar ? "yes" : "no"}`
    : `${record.device.model}, ${record.device.osName} ${record.device.osVersion}, LiDAR ${record.device.hasLidar ? "yes" : "no"}`;
  return [
    ["Address", record.address.formatted],
    [
      "Confirmed on site",
      record.address.confirmedOnSite
        ? `Yes${record.address.confirmedAt ? `, ${record.address.confirmedAt}` : ""}`
        : "No",
    ],
    ["HUB project", `${record.hub.projectName ?? "(no name)"} (deal ${record.hub.dealId})`],
    ["Operator", record.operator.name],
    ["Device", device],
    ["App", `Chapter Capture ${record.app.version} (build ${record.app.build})`],
    ["Visited at", record.visitedAt],
  ];
}

function captureRows(record: CaptureRecord): string[][] {
  return record.captures.map((capture) => {
    const notes: string[] = [];
    if (capture.coverageNotes.trim() !== "") {
      notes.push(`Coverage: ${capture.coverageNotes}`);
    }
    if (capture.omittedRooms.length > 0) {
      notes.push(
        `Omitted: ${capture.omittedRooms.map((room) => (room.reason ? `${room.name} (${room.reason})` : room.name)).join("; ")}`,
      );
    }
    if (capture.inaccessibleRooms.length > 0) {
      notes.push(
        `Inaccessible: ${capture.inaccessibleRooms.map((room) => (room.reason ? `${room.name} (${room.reason})` : room.name)).join("; ")}`,
      );
    }
    return [
      `${capture.label}\n${capture.areaKey}`,
      capture.mode,
      capture.captureId,
      `${capture.capturedAt}${capture.finishedAt ? `\nto ${capture.finishedAt}` : ""}`,
      notes.length === 0 ? "None" : notes.join("\n"),
    ];
  });
}

/** Renders the verdict report. Deterministic for the same input (dates come from the verdict). */
export function renderVerdictReport(input: ReportInput): Promise<Buffer> {
  const { verdict } = input;
  const evaluated = new Date(verdict.evaluatedAt);
  const doc = new PDFDocument({
    size: "LETTER",
    margin: PAGE_MARGIN,
    info: {
      Title: `${REPORT_TITLE} ${verdict.verdictId}`,
      Author: "Chapter Capture station",
      Subject: `Verdict ${verdict.outcome} for package ${input.packageId}`,
      Creator: "Chapter Capture station",
      Producer: "Chapter Capture station",
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

  const w = new ReportWriter(doc);
  doc.font(BOLD_FONT).fontSize(18).text(REPORT_TITLE, w.left, PAGE_MARGIN, { width: w.width });
  if (input.captureRecord !== undefined) {
    w.paragraph(input.captureRecord.address.formatted, { size: 11 });
  }
  w.paragraph(`HUB deal ${input.dealId} - visit ${verdict.visitId}, revision ${verdict.revision}`, {
    size: 9,
    color: "#444444",
  });

  w.heading(`Outcome: ${OUTCOME_LABEL[verdict.outcome]}`);
  w.paragraph(outcomeInPlainWords(verdict), { font: BOLD_FONT, size: 10 });
  doc.moveDown(0.3);
  w.paragraph(verdict.summary, { size: 10 });

  w.heading("Package and verdict");
  w.keyValues([
    ["Task", verdict.task],
    ["Package id", input.packageId],
    ["Visit id", verdict.visitId],
    ["Revision", String(verdict.revision)],
    ["HUB deal id", input.dealId],
    ["Verdict id", verdict.verdictId],
    ["Evaluated at", verdict.evaluatedAt],
    ["Evaluator", `${verdict.evaluator.name} ${verdict.evaluator.version}`],
  ]);

  w.heading("Checks");
  w.table(
    [
      { header: "Rule", width: 150 },
      { header: "Check", width: 252 },
      { header: "Result", width: w.width - 402 },
    ],
    verdict.checks.map((check) => [
      check.ruleId,
      check.title,
      check.status === "not_applicable" ? "not applicable" : check.status,
    ]),
  );

  w.heading(`Findings (${verdict.findings.length})`);
  if (verdict.findings.length === 0) {
    w.paragraph("No findings.");
  } else {
    w.table(
      [
        { header: "Severity", width: 54 },
        { header: "Rule", width: 82 },
        { header: "Finding", width: 166 },
        { header: "File", width: 100 },
        { header: "Next action", width: w.width - 402 },
      ],
      verdict.findings.map((finding) => {
        const details = [finding.message];
        if (finding.measured !== undefined) {
          details.push(`Measured: ${finding.measured}`);
        }
        if (finding.expected !== undefined) {
          details.push(`Expected: ${finding.expected}`);
        }
        return [
          finding.severity,
          finding.ruleId,
          details.join("\n"),
          finding.filePath ?? "-",
          finding.nextAction,
        ];
      }),
    );
  }

  w.heading("Limitations");
  w.bullets(verdict.limitations, "None.");

  w.heading("Next actions");
  w.bullets(verdict.nextActions, "None.");

  w.heading("Capture record");
  if (input.captureRecord === undefined) {
    w.paragraph("No capture record is stored for this package.");
  } else {
    w.keyValues(captureRecordRows(input.captureRecord));
    doc.moveDown(0.4);
    w.table(
      [
        { header: "Floor or area", width: 80 },
        { header: "Mode", width: 50 },
        { header: "Capture id", width: 130 },
        { header: "Captured", width: 100 },
        { header: "Notes", width: w.width - 360 },
      ],
      captureRows(input.captureRecord),
    );
  }

  w.heading("Files");
  w.paragraph(
    `Files up to ${formatBytes(input.maxUploadBytes)} of the roles the HUB receives are in the HUB folders below. Every other file stays in the station's immutable storage and opens through its station link after Entra sign-in. There are no public links.`,
    { size: 8, color: "#444444" },
  );
  doc.moveDown(0.3);
  w.paragraph(`This report: ${input.reportLocation.folder}/${input.reportLocation.name}`, {
    size: 8,
  });
  doc.moveDown(0.3);
  for (const file of input.files) {
    w.fileEntry(file, input.maxUploadBytes);
  }

  w.heading("Statement");
  w.paragraph(verdict.statement, { size: 9 });
  doc.moveDown(0.2);
  w.paragraph(REPORT_NOT_CERTIFICATION, { font: BOLD_FONT, size: 9 });

  doc.end();
  return done;
}

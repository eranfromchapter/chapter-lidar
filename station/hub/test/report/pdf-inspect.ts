// Reads the structure of a report PDF written by pdfkit (uncompressed object syntax, Flate
// content streams): base fonts, each page's content stream, colours used, text show operations.

import { inflateSync } from "node:zlib";

export interface PdfStructure {
  /** BaseFont of every font object. */
  readonly baseFonts: readonly string[];
  /** Font resource name (F1, F2, …) to BaseFont. */
  readonly fontResources: ReadonlyMap<string, string>;
  /** Inflated content stream of each page, in page order. */
  readonly pages: readonly string[];
}

function objectBody(pdf: string, id: number): string {
  const start = pdf.indexOf(`\n${id} 0 obj`);
  if (start < 0) {
    throw new Error(`object ${id} not found`);
  }
  const end = pdf.indexOf("endobj", start);
  return pdf.slice(start, end);
}

function streamOf(bytes: Buffer, pdf: string, id: number): Buffer {
  const start = pdf.indexOf(`\n${id} 0 obj`);
  const header = pdf.indexOf("stream\n", start) + "stream\n".length;
  const end = pdf.indexOf("\nendstream", header);
  const raw = bytes.subarray(header, end);
  return objectBody(pdf, id).includes("/FlateDecode") ? inflateSync(raw) : raw;
}

export function pdfStructure(data: Uint8Array): PdfStructure {
  const bytes = Buffer.from(data);
  // latin1 keeps byte offsets equal to string offsets.
  const pdf = bytes.toString("latin1");
  const baseFonts = [...pdf.matchAll(/\/Type \/Font[^]*?\/BaseFont \/([^\s/>]+)/g)].map(
    (m) => m[1] as string,
  );
  const fontResources = new Map<string, string>();
  for (const m of pdf.matchAll(/\/(F\d+) (\d+) 0 R/g)) {
    const body = objectBody(pdf, Number(m[2]));
    const base = /\/BaseFont \/([^\s/>]+)/.exec(body)?.[1];
    if (base !== undefined) {
      fontResources.set(m[1] as string, base);
    }
  }
  // Pages in order: the Pages tree's Kids.
  const kids = /\/Type \/Pages[^]*?\/Kids \[([^\]]*)\]/.exec(pdf)?.[1] ?? "";
  const pageIds = [...kids.matchAll(/(\d+) 0 R/g)].map((m) => Number(m[1]));
  const pages = pageIds.map((pageId) => {
    const contents = /\/Contents (\d+) 0 R/.exec(objectBody(pdf, pageId))?.[1];
    return contents === undefined ? "" : streamOf(bytes, pdf, Number(contents)).toString("latin1");
  });
  return { baseFonts, fontResources, pages };
}

/** Every fill and stroke colour set in a content stream, as #RRGGBB. */
export function coloursOf(content: string): string[] {
  const hex = (v: string) =>
    Math.round(Number(v) * 255)
      .toString(16)
      .padStart(2, "0")
      .toUpperCase();
  return [...content.matchAll(/(?:^|\s)([\d.]+) ([\d.]+) ([\d.]+) (?:scn|SCN|rg|RG)\b/g)].map(
    (m) => `#${hex(m[1] as string)}${hex(m[2] as string)}${hex(m[3] as string)}`,
  );
}

/** Glyph ids (embedded fonts) or codes (standard fonts) of every text show, with its font. */
export function textShows(
  content: string,
  fonts: ReadonlyMap<string, string>,
): Array<{ font: string; codes: string[] }> {
  const out: Array<{ font: string; codes: string[] }> = [];
  let font = "";
  for (const m of content.matchAll(/\/(F\d+) [\d.]+ Tf|\[((?:<[0-9a-fA-F]*>|[\s\d.-])*)\] TJ/g)) {
    if (m[1] !== undefined) {
      font = fonts.get(m[1]) ?? m[1];
      continue;
    }
    const hexes = [...(m[2] ?? "").matchAll(/<([0-9a-fA-F]*)>/g)].map((h) => h[1] as string);
    const embedded = font.includes("+");
    const width = embedded ? 4 : 2;
    const codes = hexes.flatMap((h) => h.match(new RegExp(`.{${width}}`, "g")) ?? []);
    out.push({ font, codes });
  }
  return out;
}

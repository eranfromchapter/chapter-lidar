// Design tokens of the spatial report (artboards 1f-1aa, system 1ab): colours, type, page grid.
// Everything is in points on a US Letter landscape page (792 x 612), origin top-left, y down.

/** Colours (hex exact). Meaning never depends on hue alone (B&W proof 1ac). */
export const COLOR = {
  ink: "#1F2429",
  muted: "#6B6557",
  line: "#D9CCBC",
  nude: "#E8DDD0",
  wet: "#EFE6DA",
  ground: "#F5EFE6",
  surface: "#FAF5EE",
  ready: "#2E5E2E",
  limited: "#9A6A1E",
  limitedText: "#7A5214",
  blocked: "#8B2E2E",
  logo: "#231F20",
} as const;

export type ColorToken = keyof typeof COLOR;

/** Font names as registered with pdfkit. Times and Courier are the PDF standard fonts. */
export const FONT = {
  sans: "Inter",
  semibold: "Inter-SB",
  serif: "Times-Roman",
  mono: "Courier",
} as const;

export type FontName = (typeof FONT)[keyof typeof FONT];

export interface TextStyle {
  readonly font: FontName;
  readonly size: number;
  /** Line height (CSS line-height), points. */
  readonly line: number;
  readonly color: string;
  /** Letter spacing, points. */
  readonly tracking?: number;
  /** Upper-cased before measuring and drawing (CSS text-transform). */
  readonly upper?: boolean;
}

export function style(base: TextStyle, change: Partial<TextStyle>): TextStyle {
  return { ...base, ...change };
}

/** Type scale (spatial-report spec 3.2). */
export const TYPE = {
  kicker: { font: FONT.sans, size: 7.5, line: 9, color: COLOR.muted, tracking: 1.5, upper: true },
  kickerInner: {
    font: FONT.sans,
    size: 7.5,
    line: 9,
    color: COLOR.muted,
    tracking: 1.2,
    upper: true,
  },
  title: { font: FONT.serif, size: 21, line: 24, color: COLOR.ink },
  subline: { font: FONT.sans, size: 9.75, line: 12, color: COLOR.muted },
  section: { font: FONT.serif, size: 16.5, line: 19, color: COLOR.ink },
  roomTitle: { font: FONT.serif, size: 22.5, line: 26, color: COLOR.ink },
  roomTitleLong: { font: FONT.serif, size: 16.5, line: 19, color: COLOR.ink },
  verdictWord: { font: FONT.semibold, size: 12, line: 14, color: COLOR.ink },
  tileValue: { font: FONT.semibold, size: 11.25, line: 13, color: COLOR.ink },
  body: { font: FONT.sans, size: 9.75, line: 12, color: COLOR.ink },
  table: { font: FONT.sans, size: 9, line: 11, color: COLOR.ink },
  tableBold: { font: FONT.semibold, size: 9, line: 11, color: COLOR.ink },
  tableMono: { font: FONT.mono, size: 9, line: 11, color: COLOR.ink },
  dense: { font: FONT.sans, size: 8.25, line: 10, color: COLOR.ink },
  denseMono: { font: FONT.mono, size: 8.25, line: 10, color: COLOR.ink },
  header: { font: FONT.sans, size: 8.25, line: 10, color: COLOR.muted },
  caption: { font: FONT.sans, size: 7.5, line: 9, color: COLOR.muted },
  footnote: { font: FONT.sans, size: 7.5, line: 9.5, color: COLOR.muted },
  ids: { font: FONT.mono, size: 7.5, line: 9, color: COLOR.muted },
} as const satisfies Record<string, TextStyle>;

/** Page geometry (spec 3.3-3.5). */
export const PAGE = {
  width: 792,
  height: 612,
  left: 36,
  right: 756,
  contentTop: 102,
  contentBottom: 528,
  contentWidth: 720,
  contentHeight: 426,
} as const;

/** Width of `n` of the 12 grid columns (49 pt, 12 pt gutters). */
export function span(n: number): number {
  return n * 49 + (n - 1) * 12;
}

/** Line weights. */
export const RULE = 0.75;

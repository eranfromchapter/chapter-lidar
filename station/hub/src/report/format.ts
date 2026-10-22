// Text formatting of the spatial report: WinAnsi-safe text, sizes, numbers in the measurement
// engine's rounding, dates in the report's time zone, plurals and number words.

import {
  CUBIC_METRES_PER_CUBIC_FOOT,
  SQUARE_METRES_PER_SQUARE_FOOT,
  decimals,
  feetInches,
} from "./metrics/units.js";

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
  " ": " ",
  "\t": " ",
};

// Characters of WinAnsi (CP1252) outside Latin-1: Times, Courier and the embedded Inter (cut to
// WinAnsi) all have them.
const WIN_ANSI_EXTRA = new Set("€‚ƒ„†‡ˆ‰Š‹ŒŽ‘’“”•–—˜™š›œžŸ");

/** Text the report's fonts can show: known symbols spelled in ASCII, anything else "?". */
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

/** `1.2 MiB (1258291 bytes)`; under 1 KiB `512 B`. */
export function formatBytes(bytes: number): string {
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

// MARK: Numbers

/** Thousands separators on a number written by `decimals()`: `2196.3` -> `2,196.3`. */
export function grouped(text: string): string {
  const negative = text.startsWith("-");
  const body = negative ? text.slice(1) : text;
  const [whole = "", fraction] = body.split(".");
  const withCommas = whole.replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  return `${negative ? "-" : ""}${withCommas}${fraction === undefined ? "" : `.${fraction}`}`;
}

/** A number with `places` decimals (engine rounding) and thousands separators. */
export function fixed(value: number, places: number): string {
  return grouped(decimals(value, places) ?? "-");
}

/** Square metres as square feet, one decimal: `2,196.3`. */
export function sqFt(squareMetres: number): string {
  return fixed(squareMetres / SQUARE_METRES_PER_SQUARE_FOOT, 1);
}

/** Cubic metres as cubic feet, one decimal: `6,598.1`. */
export function cuFt(cubicMetres: number): string {
  return fixed(cubicMetres / CUBIC_METRES_PER_CUBIC_FOOT, 1);
}

/** A length in metres as feet-inches to 0.1 in: `19' 4.3"`. */
export function ftIn(metres: number): string {
  return feetInches(metres);
}

/** A dimension pair, larger side first: `19' 4.3" × 11' 7.8"`. */
export function dimensionPair(a: number, b: number): string {
  return `${feetInches(Math.max(a, b))} × ${feetInches(Math.min(a, b))}`;
}

// MARK: Words

const NUMBER_WORDS = [
  "Zero",
  "One",
  "Two",
  "Three",
  "Four",
  "Five",
  "Six",
  "Seven",
  "Eight",
  "Nine",
];

/** "One"…"Nine", digits from 10 (sentence start). */
export function numberWord(n: number): string {
  return n >= 0 && n < 10 ? (NUMBER_WORDS[n] as string) : String(n);
}

/** `1 room`, `2 rooms`; with `plural` for irregular words. */
export function plural(n: number, word: string, pluralWord = `${word}s`): string {
  return `${n} ${n === 1 ? word : pluralWord}`;
}

// MARK: Dates

/** Default time zone of printed dates and times (the plan sheet's print zone too). */
export const DEFAULT_REPORT_TIME_ZONE = "America/New_York";

interface DateParts {
  year: string;
  month: string;
  monthLong: string;
  monthShort: string;
  day: string;
  hour: string;
  minute: string;
}

const formatters = new Map<string, Intl.DateTimeFormat>();

function partsOf(iso: string, timeZone: string): DateParts {
  let formatter = formatters.get(timeZone);
  if (formatter === undefined) {
    formatter = new Intl.DateTimeFormat("en-US", {
      timeZone,
      year: "numeric",
      month: "long",
      day: "numeric",
      hour: "2-digit",
      minute: "2-digit",
      hourCycle: "h23",
    });
    formatters.set(timeZone, formatter);
  }
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) {
    throw new RangeError(`not a date: ${iso}`);
  }
  const parts = Object.fromEntries(formatter.formatToParts(date).map((p) => [p.type, p.value]));
  const monthLong = String(parts.month);
  return {
    year: String(parts.year),
    month: monthLong,
    monthLong,
    monthShort: monthLong.slice(0, 3),
    day: String(parts.day),
    hour: String(parts.hour).padStart(2, "0"),
    minute: String(parts.minute).padStart(2, "0"),
  };
}

/** `January 25, 2025`. */
export function longDate(iso: string, timeZone: string): string {
  const p = partsOf(iso, timeZone);
  return `${p.monthLong} ${p.day}, ${p.year}`;
}

/** `Jan 25, 2025`. */
export function shortDate(iso: string, timeZone: string): string {
  const p = partsOf(iso, timeZone);
  return `${p.monthShort} ${p.day}, ${p.year}`;
}

/** `Jan 25, 2025 14:02` (24-hour clock). */
export function shortDateTime(iso: string, timeZone: string): string {
  const p = partsOf(iso, timeZone);
  return `${p.monthShort} ${p.day}, ${p.year} ${p.hour}:${p.minute}`;
}

/** `14:02`. */
export function time(iso: string, timeZone: string): string {
  const p = partsOf(iso, timeZone);
  return `${p.hour}:${p.minute}`;
}

/** The calendar day of `iso` in the zone, `YYYY-MM-DD` order key. */
export function dayKey(iso: string, timeZone: string): string {
  const p = partsOf(iso, timeZone);
  return `${p.year}-${p.monthLong}-${p.day.padStart(2, "0")}`;
}

/**
 * A span of days: one day `{long}`; days of one year `January 24 to January 25, 2025` (`to`
 * joiner) or with an en dash `Jan 24–Jan 25, 2025` for short forms.
 */
export function dateSpan(
  firstIso: string,
  lastIso: string,
  timeZone: string,
  style: "long" | "short",
  joiner: string,
): string {
  const first = partsOf(firstIso, timeZone);
  const last = partsOf(lastIso, timeZone);
  const month = (p: DateParts) => (style === "long" ? p.monthLong : p.monthShort);
  if (first.year === last.year && first.month === last.month && first.day === last.day) {
    return `${month(last)} ${last.day}, ${last.year}`;
  }
  const head =
    first.year === last.year
      ? `${month(first)} ${first.day}`
      : `${month(first)} ${first.day}, ${first.year}`;
  return `${head}${joiner}${month(last)} ${last.day}, ${last.year}`;
}

/** True when `timeZone` is an IANA zone this runtime knows. */
export function isTimeZone(timeZone: string): boolean {
  try {
    new Intl.DateTimeFormat("en-US", { timeZone });
    return true;
  } catch {
    return false;
  }
}

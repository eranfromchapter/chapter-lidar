// Minimal ASCII DXF reader: group pairs, sections, header variables and entity types. Enough to
// tell whether the file opens, what units it declares and what kind of entities it holds.

import { decodeUtf8 } from "../package.js";
import { ascii, type ParseResult } from "./common.js";

export interface DxfEntity {
  type: string;
  layer?: string;
  /** Group 70 flags, kept for POLYLINE (mesh and polyface flags). */
  flags?: number;
}

export interface DxfFile {
  /** Header variables by name ($INSUNITS ...), first value group only. */
  header: Map<string, string>;
  /** Entities of the ENTITIES section. */
  entities: DxfEntity[];
  /** Entities inside BLOCK definitions (BLOCK and ENDBLK markers excluded). */
  blockEntities: DxfEntity[];
  sections: string[];
}

const BINARY_SENTINEL = "AutoCAD Binary DXF";

/** Parses an ASCII DXF. Binary DXF is reported as not readable by this station. */
export function parseDxf(bytes: Uint8Array): ParseResult<DxfFile> {
  if (ascii(bytes, 0, BINARY_SENTINEL.length) === BINARY_SENTINEL) {
    return { ok: false, reason: "binary DXF is not supported; export ASCII DXF" };
  }
  const text = decodeUtf8(bytes) ?? new TextDecoder("latin1").decode(bytes);
  const lines = text.split(/\r?\n/);
  if (lines.length > 0 && lines[lines.length - 1] === "") {
    lines.pop();
  }
  if (lines.length % 2 !== 0) {
    return { ok: false, reason: "odd number of lines: group codes and values do not pair up" };
  }
  const pairs: Array<[number, string]> = [];
  for (let i = 0; i < lines.length; i += 2) {
    const codeText = (lines[i] as string).trim();
    if (!/^-?\d+$/.test(codeText)) {
      return { ok: false, reason: `line ${i + 1} is not a group code: "${codeText.slice(0, 20)}"` };
    }
    pairs.push([Number(codeText), (lines[i + 1] as string).trim()]);
  }

  const header = new Map<string, string>();
  const entities: DxfEntity[] = [];
  const blockEntities: DxfEntity[] = [];
  const sections: string[] = [];
  let section: string | undefined;
  let sawEof = false;
  let current: DxfEntity | undefined;
  let headerVar: string | undefined;
  let inBlock = false;

  for (let i = 0; i < pairs.length; i += 1) {
    const [code, value] = pairs[i] as [number, string];
    if (code === 0) {
      current = undefined;
      headerVar = undefined;
      if (value === "EOF") {
        if (section !== undefined) {
          return { ok: false, reason: `EOF inside section ${section}` };
        }
        sawEof = true;
        break;
      }
      if (value === "SECTION") {
        if (section !== undefined) {
          return { ok: false, reason: `section ${section} is not closed` };
        }
        const next = pairs[i + 1];
        if (next === undefined || next[0] !== 2) {
          return { ok: false, reason: "SECTION without a name" };
        }
        section = next[1];
        sections.push(section);
        i += 1;
        continue;
      }
      if (value === "ENDSEC") {
        if (section === undefined) {
          return { ok: false, reason: "ENDSEC without SECTION" };
        }
        section = undefined;
        inBlock = false;
        continue;
      }
      if (section === "ENTITIES") {
        current = { type: value };
        entities.push(current);
      } else if (section === "BLOCKS") {
        if (value === "BLOCK") {
          inBlock = true;
        } else if (value === "ENDBLK") {
          inBlock = false;
        } else if (inBlock) {
          current = { type: value };
          blockEntities.push(current);
        }
      }
      continue;
    }
    if (section === "HEADER") {
      if (code === 9) {
        headerVar = value;
      } else if (headerVar !== undefined && !header.has(headerVar)) {
        header.set(headerVar, value);
      }
      continue;
    }
    if (current !== undefined) {
      if (code === 8 && current.layer === undefined) {
        current.layer = value;
      } else if (code === 70 && current.flags === undefined) {
        const flags = Number(value);
        if (Number.isInteger(flags)) {
          current.flags = flags;
        }
      }
    }
  }
  if (section !== undefined) {
    return { ok: false, reason: `section ${section} is not closed (file truncated?)` };
  }
  if (!sawEof) {
    return { ok: false, reason: "no EOF marker (file truncated?)" };
  }
  if (!sections.includes("ENTITIES")) {
    return { ok: false, reason: "no ENTITIES section" };
  }
  return { ok: true, value: { header, entities, blockEntities, sections } };
}

/** DXF $INSUNITS codes and their names. */
export const INSUNITS_NAMES: Readonly<Record<number, string>> = {
  0: "unitless",
  1: "inches",
  2: "feet",
  3: "miles",
  4: "millimetres",
  5: "centimetres",
  6: "metres",
  7: "kilometres",
  8: "microinches",
  9: "mils",
  10: "yards",
  14: "decimetres",
};

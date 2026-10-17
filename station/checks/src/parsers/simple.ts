// Sanity readers for formats the station only needs to recognise: PDF, images, SVG, OBJ and MTL.

import { decodeUtf8 } from "../package.js";
import { ascii, containsAscii, fail, ok, view, type ParseResult } from "./common.js";

/** PDF: %PDF- header in the first 1024 bytes, startxref and %%EOF in the last 1024 bytes. */
export function parsePdf(bytes: Uint8Array): ParseResult<{ version: string }> {
  const head = ascii(bytes, 0, Math.min(1024, bytes.length));
  const at = head.indexOf("%PDF-");
  if (at === -1) {
    return fail("no %PDF- header");
  }
  const version = /^%PDF-(\d\.\d)/.exec(head.slice(at))?.[1];
  if (version === undefined) {
    return fail("PDF header has no version");
  }
  const tailStart = Math.max(0, bytes.length - 1024);
  if (!containsAscii(bytes, "%%EOF", tailStart)) {
    return fail("no %%EOF trailer (file truncated?)");
  }
  if (!containsAscii(bytes, "startxref", tailStart)) {
    return fail("no startxref before the trailer");
  }
  return ok({ version });
}

export type ImageKind = "jpeg" | "heic" | "png" | "webp" | "ktx2";

/** JPEG: SOI marker FF D8 FF and an EOI marker FF D9 after it. */
function isJpeg(bytes: Uint8Array): boolean {
  if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8 || bytes[2] !== 0xff) {
    return false;
  }
  for (let i = bytes.length - 2; i >= 3; i -= 1) {
    if (bytes[i] === 0xff && bytes[i + 1] === 0xd9) {
      return true;
    }
  }
  return false;
}

const HEIF_BRANDS = new Set(["heic", "heix", "hevc", "hevx", "heim", "heis", "mif1", "msf1"]);

/** HEIC/HEIF: an ISO BMFF ftyp box whose major or compatible brand is a HEIF brand. */
function isHeic(bytes: Uint8Array): boolean {
  if (bytes.length < 16 || ascii(bytes, 4, 4) !== "ftyp") {
    return false;
  }
  const size = view(bytes).getUint32(0, false);
  if (size < 16 || size > bytes.length) {
    return false;
  }
  if (HEIF_BRANDS.has(ascii(bytes, 8, 4))) {
    return true;
  }
  for (let at = 16; at + 4 <= size; at += 4) {
    if (HEIF_BRANDS.has(ascii(bytes, at, 4))) {
      return true;
    }
  }
  return false;
}

const PNG_SIGNATURE = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

/** PNG: signature, IHDR as the first chunk and an IEND chunk at the end. */
function isPng(bytes: Uint8Array): boolean {
  if (bytes.length < 8 + 25 + 12 || PNG_SIGNATURE.some((value, i) => bytes[i] !== value)) {
    return false;
  }
  return ascii(bytes, 12, 4) === "IHDR" && ascii(bytes, bytes.length - 8, 4) === "IEND";
}

function isWebp(bytes: Uint8Array): boolean {
  return bytes.length >= 12 && ascii(bytes, 0, 4) === "RIFF" && ascii(bytes, 8, 4) === "WEBP";
}

function isKtx2(bytes: Uint8Array): boolean {
  return bytes.length >= 12 && ascii(bytes, 1, 6) === "KTX 20";
}

/** Identifies an image among the allowed kinds. */
export function parseImage(
  bytes: Uint8Array,
  allowed: readonly ImageKind[],
): ParseResult<{ kind: ImageKind }> {
  const tests: Record<ImageKind, (b: Uint8Array) => boolean> = {
    jpeg: isJpeg,
    heic: isHeic,
    png: isPng,
    webp: isWebp,
    ktx2: isKtx2,
  };
  for (const kind of allowed) {
    if (tests[kind](bytes)) {
      return ok({ kind });
    }
  }
  return fail(`not a complete ${allowed.map((kind) => kind.toUpperCase()).join(" or ")} image`);
}

/** SVG: UTF-8 text with an <svg element. */
export function parseSvg(bytes: Uint8Array): ParseResult<{ length: number }> {
  const text = decodeUtf8(bytes);
  if (text === undefined) {
    return fail("not UTF-8 text");
  }
  if (!/<svg[\s>]/.test(text) || !text.includes("</svg>")) {
    return fail("no complete <svg> element");
  }
  return ok({ length: text.length });
}

export interface ObjFile {
  vertexCount: number;
  faceCount: number;
  /** Material library file names from mtllib lines, as written. */
  mtllibs: string[];
}

/** Splits a text file into logical lines (backslash continuation joined), comments removed. */
function logicalLines(text: string): string[] {
  const out: string[] = [];
  let pending = "";
  for (const raw of text.split(/\r?\n/)) {
    if (raw.endsWith("\\")) {
      pending += `${raw.slice(0, -1)} `;
      continue;
    }
    const line = `${pending}${raw}`.trim();
    pending = "";
    if (line.length > 0 && !line.startsWith("#")) {
      out.push(line);
    }
  }
  return out;
}

/** OBJ: at least one vertex and one face; every face index refers to an existing vertex. */
export function parseObj(bytes: Uint8Array): ParseResult<ObjFile> {
  const text = decodeUtf8(bytes);
  if (text === undefined) {
    return fail("not UTF-8 text");
  }
  let vertexCount = 0;
  let faceCount = 0;
  const mtllibs: string[] = [];
  const lines = logicalLines(text);
  for (const [index, line] of lines.entries()) {
    const [keyword, ...rest] = line.split(/\s+/);
    if (keyword === "v") {
      if (rest.length < 3 || rest.slice(0, 3).some((value) => !Number.isFinite(Number(value)))) {
        return fail(`vertex line ${index + 1} does not hold three numbers`);
      }
      vertexCount += 1;
    } else if (keyword === "f") {
      if (rest.length < 3) {
        return fail(`face line ${index + 1} has fewer than three vertices`);
      }
      for (const ref of rest) {
        const v = Number(ref.split("/")[0]);
        const resolved = v < 0 ? vertexCount + v + 1 : v;
        if (!Number.isInteger(v) || v === 0 || resolved < 1 || resolved > vertexCount) {
          return fail(`face line ${index + 1} refers to a missing vertex "${ref}"`);
        }
      }
      faceCount += 1;
    } else if (keyword === "mtllib") {
      mtllibs.push(...rest);
    }
  }
  if (vertexCount === 0 || faceCount === 0) {
    return fail(`no mesh: ${vertexCount} vertices, ${faceCount} faces`);
  }
  return ok({ vertexCount, faceCount, mtllibs });
}

export interface MtlFile {
  materialCount: number;
  /** Texture file names from map_* and bump/disp/decal/refl lines, as written. */
  textures: string[];
}

const MTL_TEXTURE_KEYWORDS = new Set([
  "map_ka",
  "map_kd",
  "map_ks",
  "map_ns",
  "map_d",
  "map_bump",
  "map_ke",
  "map_pr",
  "map_pm",
  "map_ps",
  "map_norm",
  "bump",
  "disp",
  "decal",
  "refl",
  "norm",
]);

/** MTL: at least one newmtl; texture references collected (file name is the last token). */
export function parseMtl(bytes: Uint8Array): ParseResult<MtlFile> {
  const text = decodeUtf8(bytes);
  if (text === undefined) {
    return fail("not UTF-8 text");
  }
  let materialCount = 0;
  const textures: string[] = [];
  for (const line of logicalLines(text)) {
    const tokens = line.split(/\s+/);
    const keyword = (tokens[0] ?? "").toLowerCase();
    if (keyword === "newmtl") {
      materialCount += 1;
    } else if (MTL_TEXTURE_KEYWORDS.has(keyword) && tokens.length >= 2) {
      textures.push(tokens[tokens.length - 1] as string);
    }
  }
  if (materialCount === 0) {
    return fail("no newmtl material");
  }
  return ok({ materialCount, textures });
}

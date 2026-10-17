// LAS 1.0-1.4 public header reader and point data scan (counts and extents).

import { ascii, fail, ok, view, type ParseResult } from "./common.js";

/** Minimum point record length per point data record format 0-10. */
export const MIN_RECORD_LENGTH: Readonly<Record<number, number>> = {
  0: 20,
  1: 28,
  2: 26,
  3: 34,
  4: 57,
  5: 63,
  6: 30,
  7: 36,
  8: 38,
  9: 59,
  10: 67,
};

export interface LasHeader {
  versionMajor: number;
  versionMinor: number;
  systemIdentifier: string;
  headerSize: number;
  offsetToPointData: number;
  vlrCount: number;
  /** Raw point data record format byte (bit 7 set means LAZ compression). */
  pointFormatByte: number;
  recordLength: number;
  legacyPointCount: number;
  /** 64-bit point count (LAS 1.4 only). */
  pointCount64?: bigint;
  scale: [number, number, number];
  offset: [number, number, number];
  min: [number, number, number];
  max: [number, number, number];
  /** LAS 1.4: start of the first extended VLR and how many there are. */
  evlrStart?: bigint;
  evlrCount?: number;
  fileLength: number;
}

/** Parses the public header block. Fails only when the header itself cannot be read. */
export function parseLasHeader(bytes: Uint8Array): ParseResult<LasHeader> {
  if (bytes.length < 227) {
    return fail(`${bytes.length} bytes is shorter than a LAS header (227)`);
  }
  if (ascii(bytes, 0, 4) !== "LASF") {
    return fail("no LASF signature");
  }
  const v = view(bytes);
  const versionMajor = bytes[24] as number;
  const versionMinor = bytes[25] as number;
  const headerSize = v.getUint16(94, true);
  const offsetToPointData = v.getUint32(96, true);
  if (headerSize < 227 || headerSize > bytes.length) {
    return fail(`header size ${headerSize} is not between 227 and the file length`);
  }
  if (offsetToPointData < headerSize || offsetToPointData > bytes.length) {
    return fail(`offset to point data ${offsetToPointData} is outside the file`);
  }
  const recordLength = v.getUint16(105, true);
  if (recordLength === 0) {
    return fail("point record length is 0");
  }
  const scale: [number, number, number] = [
    v.getFloat64(131, true),
    v.getFloat64(139, true),
    v.getFloat64(147, true),
  ];
  if (scale.some((value) => !Number.isFinite(value) || value === 0)) {
    return fail("scale factors are zero or not finite");
  }
  const header: LasHeader = {
    versionMajor,
    versionMinor,
    systemIdentifier: ascii(bytes, 26, 32).replace(/\0+$/, ""),
    headerSize,
    offsetToPointData,
    vlrCount: v.getUint32(100, true),
    pointFormatByte: bytes[104] as number,
    recordLength,
    legacyPointCount: v.getUint32(107, true),
    scale,
    offset: [v.getFloat64(155, true), v.getFloat64(163, true), v.getFloat64(171, true)],
    max: [v.getFloat64(179, true), v.getFloat64(195, true), v.getFloat64(211, true)],
    min: [v.getFloat64(187, true), v.getFloat64(203, true), v.getFloat64(219, true)],
    fileLength: bytes.length,
  };
  if (versionMajor === 1 && versionMinor >= 4) {
    if (headerSize < 375) {
      return fail(`LAS 1.4 header size ${headerSize} is below 375`);
    }
    header.evlrStart = v.getBigUint64(235, true);
    header.evlrCount = v.getUint32(243, true);
    header.pointCount64 = v.getBigUint64(247, true);
  }
  return ok(header);
}

/** Point count the header declares (64-bit count for 1.4, legacy count otherwise). */
export function declaredPointCount(header: LasHeader): bigint {
  return header.pointCount64 ?? BigInt(header.legacyPointCount);
}

export interface LasDataScan {
  /** Whole point records between the point data offset and the end of point data. */
  recordCount: number;
  /** Bytes left over that do not make a whole record. */
  remainderBytes: number;
  /** Extents of the scanned records (scaled and offset), undefined when there are none. */
  min?: [number, number, number];
  max?: [number, number, number];
}

/** Scans the point records: how many there are and their real extents. */
export function scanLasPoints(bytes: Uint8Array, header: LasHeader): LasDataScan {
  let end = bytes.length;
  if (header.evlrCount !== undefined && header.evlrCount > 0 && header.evlrStart !== undefined) {
    const start = Number(header.evlrStart);
    if (start >= header.offsetToPointData && start <= bytes.length) {
      end = start;
    }
  }
  const available = Math.max(0, end - header.offsetToPointData);
  const recordCount = Math.floor(available / header.recordLength);
  const remainderBytes = available - recordCount * header.recordLength;
  if (recordCount === 0 || header.recordLength < 12) {
    return { recordCount, remainderBytes };
  }
  const v = view(bytes);
  const imin = [Infinity, Infinity, Infinity];
  const imax = [-Infinity, -Infinity, -Infinity];
  for (let i = 0; i < recordCount; i += 1) {
    const base = header.offsetToPointData + i * header.recordLength;
    for (let axis = 0; axis < 3; axis += 1) {
      const value = v.getInt32(base + axis * 4, true);
      if (value < (imin[axis] as number)) {
        imin[axis] = value;
      }
      if (value > (imax[axis] as number)) {
        imax[axis] = value;
      }
    }
  }
  const real = (ints: number[]) =>
    ints.map(
      (value, axis) => (header.offset[axis] as number) + value * (header.scale[axis] as number),
    ) as [number, number, number];
  return { recordCount, remainderBytes, min: real(imin), max: real(imax) };
}

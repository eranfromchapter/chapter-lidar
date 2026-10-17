// RFC 4180 CSV reader with one extension: a record that starts with "#" is a comment line (the
// room CSV ends with a "# Reported floor area is not a verified construction quantity." note).

import { decodeUtf8 } from "../package.js";
import { fail, ok, type ParseResult } from "./common.js";

export interface CsvFile {
  header: string[];
  rows: string[][];
  comments: string[];
}

export function parseCsv(bytes: Uint8Array): ParseResult<CsvFile> {
  const text = decodeUtf8(bytes);
  if (text === undefined) {
    return fail("not UTF-8 text");
  }
  const records: string[][] = [];
  const comments: string[] = [];
  let field = "";
  let record: string[] = [];
  let inQuotes = false;
  let atRecordStart = true;
  let i = 0;
  const endRecord = () => {
    record.push(field);
    records.push(record);
    record = [];
    field = "";
    atRecordStart = true;
  };
  while (i < text.length) {
    const ch = text[i] as string;
    if (inQuotes) {
      if (ch === '"') {
        if (text[i + 1] === '"') {
          field += '"';
          i += 2;
          continue;
        }
        inQuotes = false;
        i += 1;
        continue;
      }
      field += ch;
      i += 1;
      continue;
    }
    if (atRecordStart && ch === "#") {
      const end = text.indexOf("\n", i);
      const line = end === -1 ? text.slice(i) : text.slice(i, end);
      comments.push(line.replace(/\r$/, ""));
      i = end === -1 ? text.length : end + 1;
      continue;
    }
    atRecordStart = false;
    if (ch === '"') {
      if (field.length > 0) {
        return fail(`stray quote in record ${records.length + 1}`);
      }
      inQuotes = true;
      i += 1;
    } else if (ch === ",") {
      record.push(field);
      field = "";
      i += 1;
    } else if (ch === "\r" && text[i + 1] === "\n") {
      endRecord();
      i += 2;
    } else if (ch === "\n") {
      endRecord();
      i += 1;
    } else {
      field += ch;
      i += 1;
    }
  }
  if (inQuotes) {
    return fail("unterminated quoted field");
  }
  if (!atRecordStart) {
    endRecord();
  }
  const nonEmpty = records.filter((row) => !(row.length === 1 && row[0] === ""));
  const header = nonEmpty[0];
  if (header === undefined) {
    return fail("no header row");
  }
  if (header.some((name) => name.trim() === "")) {
    return fail("header row has an empty column name");
  }
  const rows = nonEmpty.slice(1);
  const bad = rows.findIndex((row) => row.length !== header.length);
  if (bad !== -1) {
    return fail(
      `row ${bad + 2} has ${(rows[bad] as string[]).length} fields; the header has ${header.length}`,
    );
  }
  return ok({ header, rows, comments });
}

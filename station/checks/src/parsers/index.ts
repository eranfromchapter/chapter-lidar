// Reads a package file according to its manifest role.

import {
  formatErrors,
  validateCaptureModel,
  validateCaptureRecord,
  validateFieldControls,
  type CaptureModel,
  type Role,
  type ValidationResult,
} from "@chapter/capture-contract";
import { parseJsonBytes } from "../package.js";
import { fail, ok, type ParseResult } from "./common.js";
import { parseCsv, type CsvFile } from "./csv.js";
import { parseDxf, type DxfFile } from "./dxf.js";
import { parseGltf, type GltfFile } from "./gltf.js";
import { parseLasHeader, type LasHeader } from "./las.js";
import {
  parseImage,
  parseMtl,
  parseObj,
  parsePdf,
  parseSvg,
  type ImageKind,
  type MtlFile,
  type ObjFile,
} from "./simple.js";

export type ParsedFile =
  | { kind: "json"; value: unknown }
  | { kind: "capture_model"; value: CaptureModel }
  | { kind: "binary" }
  | { kind: "dxf"; value: DxfFile }
  | { kind: "csv"; value: CsvFile }
  | { kind: "pdf" }
  | { kind: "image"; imageKind: ImageKind }
  | { kind: "svg" }
  | { kind: "gltf"; value: GltfFile }
  | { kind: "obj"; value: ObjFile }
  | { kind: "mtl"; value: MtlFile }
  | { kind: "las"; value: LasHeader };

/** Human name of the format expected for a role, used in findings. */
export const ROLE_FORMAT: Readonly<Record<Role, string>> = {
  capture_record: "capture record JSON",
  raw_roomplan_json: "RoomPlan JSON",
  raw_depth: "depth samples",
  capture_model: "capture model JSON",
  plan_dxf: "DXF",
  rooms_csv: "CSV",
  plan_pdf: "PDF",
  spatial_report_pdf: "PDF",
  plan_png: "PNG",
  plan_svg: "SVG",
  mesh_glb: "GLB/glTF",
  mesh_obj: "OBJ",
  mesh_mtl: "MTL",
  texture: "texture image",
  point_cloud_las: "LAS",
  photo: "JPEG/HEIC photo",
  field_controls: "field controls JSON",
};

function schemaChecked(
  bytes: Uint8Array,
  validate: (data: unknown) => ValidationResult<unknown>,
): ParseResult<unknown> {
  const data = parseJsonBytes(bytes);
  if (data === undefined) {
    return fail("not UTF-8 JSON");
  }
  const result = validate(data);
  if (!result.ok) {
    const lines = formatErrors(result.errors.slice(0, 3));
    const more = result.errors.length > 3 ? ` (+${result.errors.length - 3} more)` : "";
    return fail(`does not match the contract schema: ${lines.replace(/\n/g, "; ")}${more}`);
  }
  return ok(result.value);
}

function wrap<T>(result: ParseResult<T>, make: (value: T) => ParsedFile): ParseResult<ParsedFile> {
  return result.ok ? ok(make(result.value)) : result;
}

/** Parses a nonempty file by role. */
export function parseByRole(role: Role, bytes: Uint8Array): ParseResult<ParsedFile> {
  switch (role) {
    case "capture_record":
      return wrap(schemaChecked(bytes, validateCaptureRecord), (value) => ({
        kind: "json",
        value,
      }));
    case "field_controls":
      return wrap(schemaChecked(bytes, validateFieldControls), (value) => ({
        kind: "json",
        value,
      }));
    case "capture_model":
      return wrap(schemaChecked(bytes, validateCaptureModel), (value) => ({
        kind: "capture_model",
        value: value as CaptureModel,
      }));
    case "raw_roomplan_json": {
      const data = parseJsonBytes(bytes);
      return data === undefined ? fail("not UTF-8 JSON") : ok({ kind: "json", value: data });
    }
    case "raw_depth":
      return ok({ kind: "binary" });
    case "plan_dxf":
      return wrap(parseDxf(bytes), (value) => ({ kind: "dxf", value }));
    case "rooms_csv":
      return wrap(parseCsv(bytes), (value) => ({ kind: "csv", value }));
    case "plan_pdf":
    case "spatial_report_pdf":
      return wrap(parsePdf(bytes), () => ({ kind: "pdf" }));
    case "plan_png":
      return wrap(parseImage(bytes, ["png"]), (value) => ({
        kind: "image",
        imageKind: value.kind,
      }));
    case "plan_svg":
      return wrap(parseSvg(bytes), () => ({ kind: "svg" }));
    case "mesh_glb":
      return wrap(parseGltf(bytes), (value) => ({ kind: "gltf", value }));
    case "mesh_obj":
      return wrap(parseObj(bytes), (value) => ({ kind: "obj", value }));
    case "mesh_mtl":
      return wrap(parseMtl(bytes), (value) => ({ kind: "mtl", value }));
    case "texture":
      return wrap(parseImage(bytes, ["png", "jpeg", "webp", "ktx2"]), (value) => ({
        kind: "image",
        imageKind: value.kind,
      }));
    case "point_cloud_las":
      return wrap(parseLasHeader(bytes), (value) => ({ kind: "las", value }));
    case "photo":
      return wrap(parseImage(bytes, ["jpeg", "heic", "png"]), (value) => ({
        kind: "image",
        imageKind: value.kind,
      }));
  }
}

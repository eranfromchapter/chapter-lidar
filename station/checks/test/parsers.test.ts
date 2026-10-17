// Parser sanity on the fixture files and on hand-made broken inputs.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { parseCsv } from "../src/parsers/csv.js";
import { parseDxf } from "../src/parsers/dxf.js";
import { parseGltf, sceneBounds } from "../src/parsers/gltf.js";
import { declaredPointCount, parseLasHeader, scanLasPoints } from "../src/parsers/las.js";
import { parseImage, parseMtl, parseObj, parsePdf, parseSvg } from "../src/parsers/simple.js";
import { loadGood, pathOf } from "./helpers.js";

const box = loadGood("box-room");
const bytesOf = (role: string) => box.files.get(pathOf(box, role)) as Uint8Array;
const text = (value: string) => new TextEncoder().encode(value);

describe("DXF", () => {
  it("reads the fixture plan: units and entities", () => {
    const result = parseDxf(bytesOf("plan_dxf"));
    assert.ok(result.ok);
    assert.equal(result.value.header.get("$INSUNITS"), "4");
    assert.deepEqual([...new Set(result.value.entities.map((e) => e.type))].sort(), [
      "ARC",
      "LINE",
      "LWPOLYLINE",
      "TEXT",
    ]);
  });

  it("rejects truncated, unpaired and binary files", () => {
    assert.equal(parseDxf(text("  0\nSECTION\n  2\nENTITIES\n")).ok, false);
    assert.equal(parseDxf(text("  0\nSECTION\n  2\n")).ok, false);
    assert.equal(parseDxf(text("AutoCAD Binary DXF\r\n\x1a\0")).ok, false);
    assert.equal(parseDxf(text("  0\nSECTION\n  2\nENTITIES\n  0\nENDSEC\n  0\nEOF\n")).ok, true);
  });
});

describe("CSV", () => {
  it("reads the room CSV with quoted feet-inch cells and the trailing note", () => {
    const result = parseCsv(bytesOf("rooms_csv"));
    assert.ok(result.ok);
    assert.equal(result.value.header.length, 13);
    assert.equal(result.value.rows.length, 1);
    assert.equal(result.value.rows[0]?.[10], `13' 1.48"`);
    assert.equal(result.value.comments.length, 1);
  });

  it("rejects unterminated quotes and empty files", () => {
    assert.equal(parseCsv(text('a,b\n"1,2\n')).ok, false);
    assert.equal(parseCsv(text("")).ok, false);
  });
});

describe("GLB", () => {
  it("reads the fixture mesh and its bounds", () => {
    const result = parseGltf(bytesOf("mesh_glb"));
    assert.ok(result.ok);
    assert.equal(result.value.container, "glb");
    assert.ok(result.value.bin !== undefined);
    const bounds = sceneBounds(result.value.json, () => result.value.bin);
    assert.ok(bounds !== undefined);
    assert.ok(Math.abs(bounds.max[1] - 2.7) < 1e-6);
  });

  it("rejects a GLB whose header length differs from the file", () => {
    const bytes = new Uint8Array(bytesOf("mesh_glb"));
    new DataView(bytes.buffer).setUint32(8, bytes.length + 4, true);
    assert.equal(parseGltf(bytes).ok, false);
  });

  it("reads glTF JSON and rejects other text", () => {
    assert.equal(parseGltf(text('{"asset":{"version":"2.0"}}')).ok, true);
    assert.equal(parseGltf(text('{"asset":{"version":"1.0"}}')).ok, false);
    assert.equal(parseGltf(text("hello")).ok, false);
  });
});

describe("LAS", () => {
  it("reads the fixture header and finds the data consistent", () => {
    const bytes = bytesOf("point_cloud_las");
    const result = parseLasHeader(bytes);
    assert.ok(result.ok);
    assert.equal(result.value.versionMinor, 4);
    assert.equal(result.value.pointFormatByte, 7);
    assert.equal(result.value.systemIdentifier, "Chapter Capture");
    const scan = scanLasPoints(bytes, result.value);
    assert.equal(BigInt(scan.recordCount), declaredPointCount(result.value));
    assert.equal(scan.remainderBytes, 0);
  });

  it("rejects short files and missing signatures", () => {
    assert.equal(parseLasHeader(new Uint8Array(100)).ok, false);
    assert.equal(parseLasHeader(new Uint8Array(400)).ok, false);
  });
});

describe("other formats", () => {
  it("recognises the fixture PDF, PNG, SVG, OBJ, MTL and JPEG", () => {
    assert.ok(parsePdf(bytesOf("plan_pdf")).ok);
    assert.ok(parseImage(bytesOf("plan_png"), ["png"]).ok);
    assert.ok(parseSvg(bytesOf("plan_svg")).ok);
    const obj = parseObj(bytesOf("mesh_obj"));
    assert.ok(obj.ok);
    assert.deepEqual(obj.value.mtllibs, ["mesh.mtl"]);
    const mtl = parseMtl(bytesOf("mesh_mtl"));
    assert.ok(mtl.ok);
    assert.deepEqual(mtl.value.textures, ["mesh-texture.png"]);
    assert.ok(parseImage(bytesOf("photo"), ["jpeg"]).ok);
  });

  it("recognises HEIC by its ftyp brand", () => {
    const heic = new Uint8Array(24);
    const view = new DataView(heic.buffer);
    view.setUint32(0, 24, false);
    heic.set(text("ftypheic"), 4);
    heic.set(text("mif1heic"), 16);
    assert.ok(parseImage(heic, ["jpeg", "heic"]).ok);
    assert.equal(parseImage(heic, ["jpeg"]).ok, false);
  });

  it("rejects an OBJ face that points at a missing vertex, and a JPEG without its end marker", () => {
    assert.equal(parseObj(text("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 4\n")).ok, false);
    assert.equal(parseObj(text("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 -1\n")).ok, true);
    assert.equal(parseImage(new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0, 0]), ["jpeg"]).ok, false);
  });
});

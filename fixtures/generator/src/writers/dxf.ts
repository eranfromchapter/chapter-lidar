// ASCII DXF R2013 (AC1027) plan writer. Units: millimetres ($INSUNITS 4). Plan entities only
// (LINE, ARC, LWPOLYLINE, TEXT) on the seven plan layers. Plan y is the model's -z so the plan
// is not mirrored when seen from above.

import type { CaptureModel } from "@chapter/capture-contract";
import { polygonArea } from "../geometry.js";
import { fixed, type P2, type V3 } from "../util.js";

export const DXF_LAYERS = [
  "A-WALL",
  "A-DOOR",
  "A-GLAZ",
  "A-OPEN",
  "A-AREA",
  "A-ANNO-TEXT",
  "A-FLOR-OBJ",
] as const;

const MM = 1000;

function quaternionYawDeg(q: [number, number, number, number]): number {
  return (2 * Math.atan2(q[1], q[3]) * 180) / Math.PI;
}

class DxfBuilder {
  private readonly lines: string[] = [];

  constructor(private handle = 0x40) {}

  readonly modelSpaceRecord = "1F";

  nextHandle(): string {
    this.handle += 1;
    return this.handle.toString(16).toUpperCase();
  }

  get handleSeed(): string {
    return (this.handle + 1).toString(16).toUpperCase();
  }

  group(code: number, value: string | number): void {
    this.lines.push(String(code).padStart(3, " "), String(value));
  }

  text(): string {
    return `${this.lines.join("\n")}\n`;
  }

  entity(type: string, layer: string, subclass: string): void {
    this.group(0, type);
    this.group(5, this.nextHandle());
    this.group(330, this.modelSpaceRecord);
    this.group(100, "AcDbEntity");
    this.group(8, layer);
    this.group(100, subclass);
  }

  point(base: number, x: number, y: number): void {
    this.group(base, fixed(x, 3));
    this.group(base + 10, fixed(y, 3));
  }
}

/** Plan point in millimetres. */
function pt(point: V3 | P2): P2 {
  const z = point.length === 3 ? point[2] : point[1];
  return [point[0] * MM, -z * MM];
}

export function writeDxf(model: CaptureModel): string {
  const b = new DxfBuilder();
  const wallsById = new Map(model.walls.map((wall) => [wall.id, wall]));

  // Entities first (handles), assembled into sections afterwards.
  // Entity handles start well above the table and block handles.
  const body = new DxfBuilder(0x2ff);
  const extent = { minX: Infinity, minY: Infinity, maxX: -Infinity, maxY: -Infinity };
  const grow = ([x, y]: P2) => {
    extent.minX = Math.min(extent.minX, x);
    extent.minY = Math.min(extent.minY, y);
    extent.maxX = Math.max(extent.maxX, x);
    extent.maxY = Math.max(extent.maxY, y);
  };
  const line = (layer: string, from: P2, to: P2) => {
    grow(from);
    grow(to);
    body.entity("LINE", layer, "AcDbLine");
    body.point(10, from[0], from[1]);
    body.group(30, "0.0");
    body.point(11, to[0], to[1]);
    body.group(31, "0.0");
  };
  const polyline = (layer: string, points: P2[]) => {
    body.entity("LWPOLYLINE", layer, "AcDbPolyline");
    body.group(90, points.length);
    body.group(70, 1);
    for (const point of points) {
      grow(point);
      body.point(10, point[0], point[1]);
    }
  };
  const label = (layer: string, at: P2, height: number, value: string) => {
    grow(at);
    body.entity("TEXT", layer, "AcDbText");
    body.point(10, at[0], at[1]);
    body.group(30, "0.0");
    body.group(40, fixed(height, 3));
    body.group(1, value);
    body.group(7, "Standard");
    body.group(100, "AcDbText");
  };

  for (const wall of model.walls) {
    line("A-WALL", pt(wall.start), pt(wall.end));
  }
  const spanOf = (opening: { wallId: string; offsetM: number; widthM: number }) => {
    const wall = wallsById.get(opening.wallId);
    if (wall === undefined) {
      throw new Error(`Unknown wall ${opening.wallId}`);
    }
    const [sx, , sz] = wall.start;
    const [ex, , ez] = wall.end;
    const length = Math.hypot(ex - sx, ez - sz);
    const at = (distance: number): P2 =>
      pt([sx + ((ex - sx) * distance) / length, 0, sz + ((ez - sz) * distance) / length]);
    return {
      from: at(opening.offsetM - opening.widthM / 2),
      to: at(opening.offsetM + opening.widthM / 2),
    };
  };
  for (const opening of model.doors) {
    const { from, to } = spanOf(opening);
    line("A-DOOR", from, to);
    // Door swing arc around the hinge (span start), a quarter circle.
    const angle = (Math.atan2(to[1] - from[1], to[0] - from[0]) * 180) / Math.PI;
    body.entity("ARC", "A-DOOR", "AcDbCircle");
    body.point(10, from[0], from[1]);
    body.group(30, "0.0");
    body.group(40, fixed(opening.widthM * MM, 3));
    body.group(100, "AcDbArc");
    body.group(50, fixed(angle, 3));
    body.group(51, fixed(angle + 90, 3));
    grow([from[0] - opening.widthM * MM, from[1] - opening.widthM * MM]);
    grow([from[0] + opening.widthM * MM, from[1] + opening.widthM * MM]);
  }
  for (const opening of model.windows) {
    const { from, to } = spanOf(opening);
    line("A-GLAZ", from, to);
  }
  for (const opening of model.openings) {
    const { from, to } = spanOf(opening);
    line("A-OPEN", from, to);
  }
  for (const room of model.rooms) {
    polyline(
      "A-AREA",
      room.polygon.map((p) => pt(p)),
    );
    const cx = room.polygon.reduce((s, p) => s + p[0], 0) / room.polygon.length;
    const cz = room.polygon.reduce((s, p) => s + p[2], 0) / room.polygon.length;
    const area = polygonArea(room.polygon.map(([x, , z]) => [x, z] as P2));
    label("A-ANNO-TEXT", pt([cx, 0, cz]), 150, room.label);
    label(
      "A-ANNO-TEXT",
      [pt([cx, 0, cz])[0], pt([cx, 0, cz])[1] - 250],
      120,
      `${fixed(area, 2)} m2`,
    );
  }
  for (const object of model.objects) {
    const half = [object.box.sizeM[0] / 2, object.box.sizeM[2] / 2];
    const yaw = (quaternionYawDeg(object.box.rotation) * Math.PI) / 180;
    const cos = Math.cos(yaw);
    const sin = Math.sin(yaw);
    const corners: P2[] = (
      [
        [-1, -1],
        [-1, 1],
        [1, 1],
        [1, -1],
      ] as Array<[number, number]>
    ).map(([sx, sz]) => {
      const lx = sx * (half[0] as number);
      const lz = sz * (half[1] as number);
      return pt([
        object.box.center[0] + lx * cos + lz * sin,
        0,
        object.box.center[2] - lx * sin + lz * cos,
      ]);
    });
    polyline("A-FLOR-OBJ", corners);
  }
  if (!Number.isFinite(extent.minX)) {
    extent.minX = extent.minY = extent.maxX = extent.maxY = 0;
  }

  // HEADER
  b.group(0, "SECTION");
  b.group(2, "HEADER");
  b.group(9, "$ACADVER");
  b.group(1, "AC1027");
  b.group(9, "$HANDSEED");
  b.group(5, body.handleSeed);
  b.group(9, "$EXTMIN");
  b.group(10, fixed(extent.minX, 3));
  b.group(20, fixed(extent.minY, 3));
  b.group(30, "0.0");
  b.group(9, "$EXTMAX");
  b.group(10, fixed(extent.maxX, 3));
  b.group(20, fixed(extent.maxY, 3));
  b.group(30, "0.0");
  b.group(9, "$LUNITS");
  b.group(70, 2);
  b.group(9, "$MEASUREMENT");
  b.group(70, 1);
  b.group(9, "$INSUNITS");
  b.group(70, 4);
  b.group(0, "ENDSEC");

  b.group(0, "SECTION");
  b.group(2, "CLASSES");
  b.group(0, "ENDSEC");

  // TABLES
  b.group(0, "SECTION");
  b.group(2, "TABLES");
  const table = (name: string, handle: string, count: number, records: () => void) => {
    b.group(0, "TABLE");
    b.group(2, name);
    b.group(5, handle);
    b.group(330, "0");
    b.group(100, "AcDbSymbolTable");
    b.group(70, count);
    records();
    b.group(0, "ENDTAB");
  };
  table("LTYPE", "5", 3, () => {
    const ltype = (handle: string, name: string, description: string) => {
      b.group(0, "LTYPE");
      b.group(5, handle);
      b.group(330, "5");
      b.group(100, "AcDbSymbolTableRecord");
      b.group(100, "AcDbLinetypeTableRecord");
      b.group(2, name);
      b.group(70, 0);
      b.group(3, description);
      b.group(72, 65);
      b.group(73, 0);
      b.group(40, "0.0");
    };
    ltype("14", "ByBlock", "");
    ltype("15", "ByLayer", "");
    ltype("16", "Continuous", "Solid line");
  });
  table("LAYER", "2", DXF_LAYERS.length + 1, () => {
    const layer = (handle: string, name: string) => {
      b.group(0, "LAYER");
      b.group(5, handle);
      b.group(330, "2");
      b.group(100, "AcDbSymbolTableRecord");
      b.group(100, "AcDbLayerTableRecord");
      b.group(2, name);
      b.group(70, 0);
      b.group(62, 7);
      b.group(6, "Continuous");
    };
    layer("10", "0");
    DXF_LAYERS.forEach((name, index) => layer((0x20 + index).toString(16).toUpperCase(), name));
  });
  table("STYLE", "3", 1, () => {
    b.group(0, "STYLE");
    b.group(5, "11");
    b.group(330, "3");
    b.group(100, "AcDbSymbolTableRecord");
    b.group(100, "AcDbTextStyleTableRecord");
    b.group(2, "Standard");
    b.group(70, 0);
    b.group(40, "0.0");
    b.group(41, "1.0");
    b.group(50, "0.0");
    b.group(71, 0);
    b.group(42, "2.5");
    b.group(3, "txt");
    b.group(4, "");
  });
  table("APPID", "9", 1, () => {
    b.group(0, "APPID");
    b.group(5, "12");
    b.group(330, "9");
    b.group(100, "AcDbSymbolTableRecord");
    b.group(100, "AcDbRegAppTableRecord");
    b.group(2, "ACAD");
    b.group(70, 0);
  });
  table("BLOCK_RECORD", "1", 2, () => {
    for (const [handle, name] of [
      ["1F", "*Model_Space"],
      ["1B", "*Paper_Space"],
    ] as const) {
      b.group(0, "BLOCK_RECORD");
      b.group(5, handle);
      b.group(330, "1");
      b.group(100, "AcDbSymbolTableRecord");
      b.group(100, "AcDbBlockTableRecord");
      b.group(2, name);
      b.group(70, 0);
      b.group(280, 1);
      b.group(281, 0);
    }
  });
  b.group(0, "ENDSEC");

  // BLOCKS
  b.group(0, "SECTION");
  b.group(2, "BLOCKS");
  for (const [recordHandle, name, blockHandle, endHandle, paper] of [
    ["1F", "*Model_Space", "20F", "210", 0],
    ["1B", "*Paper_Space", "1C", "1D", 1],
  ] as const) {
    b.group(0, "BLOCK");
    b.group(5, blockHandle);
    b.group(330, recordHandle);
    b.group(100, "AcDbEntity");
    if (paper === 1) {
      b.group(67, 1);
    }
    b.group(8, "0");
    b.group(100, "AcDbBlockBegin");
    b.group(2, name);
    b.group(70, 0);
    b.group(10, "0.0");
    b.group(20, "0.0");
    b.group(30, "0.0");
    b.group(3, name);
    b.group(1, "");
    b.group(0, "ENDBLK");
    b.group(5, endHandle);
    b.group(330, recordHandle);
    b.group(100, "AcDbEntity");
    if (paper === 1) {
      b.group(67, 1);
    }
    b.group(8, "0");
    b.group(100, "AcDbBlockEnd");
  }
  b.group(0, "ENDSEC");

  // ENTITIES
  b.group(0, "SECTION");
  b.group(2, "ENTITIES");
  const entityText = body.text();
  // OBJECTS
  const objects = new DxfBuilder();
  objects.group(0, "SECTION");
  objects.group(2, "OBJECTS");
  objects.group(0, "DICTIONARY");
  objects.group(5, "C");
  objects.group(330, "0");
  objects.group(100, "AcDbDictionary");
  objects.group(281, 1);
  objects.group(0, "ENDSEC");
  objects.group(0, "EOF");
  return `${b.text()}${entityText}  0\nENDSEC\n${objects.text()}`;
}

// glTF 2.0 reader: GLB container or glTF JSON, accessor reading, scene bounds and the horizontal
// floor test. Only what the station checks need; this is not a full validator.

import { decodeUtf8 } from "../package.js";
import { ascii, fail, ok, view, type ParseResult } from "./common.js";

const GLB_MAGIC = 0x46546c67; // "glTF"
const CHUNK_JSON = 0x4e4f534a;
const CHUNK_BIN = 0x004e4942;

export interface GltfBuffer {
  uri?: string;
  byteLength?: number;
}

export interface GltfJson {
  asset?: { version?: unknown };
  scene?: number;
  scenes?: Array<{ nodes?: number[] }>;
  nodes?: Array<{
    mesh?: number;
    children?: number[];
    matrix?: number[];
    translation?: number[];
    rotation?: number[];
    scale?: number[];
  }>;
  meshes?: Array<{
    primitives?: Array<{ attributes?: Record<string, number>; indices?: number; mode?: number }>;
  }>;
  accessors?: Array<{
    bufferView?: number;
    byteOffset?: number;
    componentType?: number;
    count?: number;
    type?: string;
    min?: number[];
    max?: number[];
    sparse?: unknown;
  }>;
  bufferViews?: Array<{
    buffer?: number;
    byteOffset?: number;
    byteLength?: number;
    byteStride?: number;
  }>;
  buffers?: GltfBuffer[];
  images?: Array<{ uri?: string; bufferView?: number }>;
}

export interface GltfFile {
  container: "glb" | "gltf";
  json: GltfJson;
  /** BIN chunk of a GLB, when present. */
  bin?: Uint8Array;
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function checkJson(value: unknown): ParseResult<GltfJson> {
  if (!isObject(value)) {
    return fail("glTF JSON is not an object");
  }
  const asset = value.asset;
  if (!isObject(asset) || typeof asset.version !== "string" || !asset.version.startsWith("2.")) {
    return fail("asset.version is not 2.x");
  }
  for (const key of [
    "scenes",
    "nodes",
    "meshes",
    "accessors",
    "bufferViews",
    "buffers",
    "images",
  ]) {
    if (value[key] !== undefined && !Array.isArray(value[key])) {
      return fail(`${key} is not an array`);
    }
  }
  return ok(value as GltfJson);
}

/** Parses a GLB container, or glTF JSON when the bytes do not start with the GLB magic. */
export function parseGltf(bytes: Uint8Array): ParseResult<GltfFile> {
  if (bytes.length >= 4 && ascii(bytes, 0, 4) === "glTF") {
    if (bytes.length < 20) {
      return fail("GLB shorter than its header");
    }
    const v = view(bytes);
    if (v.getUint32(0, true) !== GLB_MAGIC) {
      return fail("bad GLB magic");
    }
    const version = v.getUint32(4, true);
    if (version !== 2) {
      return fail(`GLB version ${version}, expected 2`);
    }
    const length = v.getUint32(8, true);
    if (length !== bytes.length) {
      return fail(`GLB header length ${length} but the file has ${bytes.length} bytes`);
    }
    let at = 12;
    let json: unknown;
    let bin: Uint8Array | undefined;
    let first = true;
    while (at + 8 <= bytes.length) {
      const chunkLength = v.getUint32(at, true);
      const chunkType = v.getUint32(at + 4, true);
      const start = at + 8;
      const end = start + chunkLength;
      if (end > bytes.length) {
        return fail("GLB chunk runs past the end of the file");
      }
      const data = bytes.subarray(start, end);
      if (first) {
        if (chunkType !== CHUNK_JSON) {
          return fail("first GLB chunk is not JSON");
        }
        const text = decodeUtf8(data);
        if (text === undefined) {
          return fail("GLB JSON chunk is not UTF-8");
        }
        try {
          json = JSON.parse(text) as unknown;
        } catch {
          return fail("GLB JSON chunk is not valid JSON");
        }
        first = false;
      } else if (chunkType === CHUNK_BIN && bin === undefined) {
        bin = data;
      }
      at = end;
    }
    if (first) {
      return fail("GLB has no JSON chunk");
    }
    if (at !== bytes.length) {
      return fail("GLB has trailing bytes after its chunks");
    }
    const checked = checkJson(json);
    if (!checked.ok) {
      return checked;
    }
    return ok(
      bin === undefined
        ? { container: "glb", json: checked.value }
        : { container: "glb", json: checked.value, bin },
    );
  }
  const text = decodeUtf8(bytes);
  if (text === undefined) {
    return fail("neither a GLB container nor UTF-8 glTF JSON");
  }
  let json: unknown;
  try {
    json = JSON.parse(text) as unknown;
  } catch {
    return fail("neither a GLB container nor glTF JSON");
  }
  const checked = checkJson(json);
  return checked.ok ? ok({ container: "gltf", json: checked.value }) : checked;
}

/** Decodes a data: URI (base64 or percent-encoded). Undefined when it is not one. */
export function decodeDataUri(uri: string): Uint8Array | undefined {
  const match = /^data:[^,]*?(;base64)?,(.*)$/s.exec(uri);
  if (match === null) {
    return undefined;
  }
  try {
    if (match[1] !== undefined) {
      return new Uint8Array(Buffer.from(match[2] as string, "base64"));
    }
    return new TextEncoder().encode(decodeURIComponent(match[2] as string));
  } catch {
    return undefined;
  }
}

type Mat4 = number[];

const IDENTITY: Mat4 = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];

/** Column-major 4x4 product a * b. */
function multiply(a: Mat4, b: Mat4): Mat4 {
  const out = new Array<number>(16).fill(0);
  for (let col = 0; col < 4; col += 1) {
    for (let row = 0; row < 4; row += 1) {
      let sum = 0;
      for (let k = 0; k < 4; k += 1) {
        sum += (a[k * 4 + row] as number) * (b[col * 4 + k] as number);
      }
      out[col * 4 + row] = sum;
    }
  }
  return out;
}

function localMatrix(node: NonNullable<GltfJson["nodes"]>[number]): Mat4 {
  if (Array.isArray(node.matrix) && node.matrix.length === 16) {
    return node.matrix.map(Number);
  }
  const [tx, ty, tz] = (node.translation ?? [0, 0, 0]).map(Number) as [number, number, number];
  const [qx, qy, qz, qw] = (node.rotation ?? [0, 0, 0, 1]).map(Number) as [
    number,
    number,
    number,
    number,
  ];
  const [sx, sy, sz] = (node.scale ?? [1, 1, 1]).map(Number) as [number, number, number];
  // Rotation matrix from a unit quaternion, column-major, then scaled per column.
  const r = [
    1 - 2 * (qy * qy + qz * qz),
    2 * (qx * qy + qz * qw),
    2 * (qx * qz - qy * qw),
    2 * (qx * qy - qz * qw),
    1 - 2 * (qx * qx + qz * qz),
    2 * (qy * qz + qx * qw),
    2 * (qx * qz + qy * qw),
    2 * (qy * qz - qx * qw),
    1 - 2 * (qx * qx + qy * qy),
  ] as number[];
  return [
    (r[0] as number) * sx,
    (r[1] as number) * sx,
    (r[2] as number) * sx,
    0,
    (r[3] as number) * sy,
    (r[4] as number) * sy,
    (r[5] as number) * sy,
    0,
    (r[6] as number) * sz,
    (r[7] as number) * sz,
    (r[8] as number) * sz,
    0,
    tx,
    ty,
    tz,
    1,
  ];
}

export type Vec3 = [number, number, number];

function transformPoint(m: Mat4, p: Vec3): Vec3 {
  const [x, y, z] = p;
  return [
    (m[0] as number) * x + (m[4] as number) * y + (m[8] as number) * z + (m[12] as number),
    (m[1] as number) * x + (m[5] as number) * y + (m[9] as number) * z + (m[13] as number),
    (m[2] as number) * x + (m[6] as number) * y + (m[10] as number) * z + (m[14] as number),
  ];
}

/** One mesh primitive placed in the scene. */
export interface PlacedPrimitive {
  matrix: Mat4;
  attributes: Record<string, number>;
  indices?: number;
  mode: number;
}

/** Every primitive of the default scene (or of all root nodes) with its world matrix. */
export function placedPrimitives(json: GltfJson): PlacedPrimitive[] {
  const nodes = json.nodes ?? [];
  let roots: number[];
  const sceneIndex = json.scene ?? 0;
  const scene = json.scenes?.[sceneIndex];
  if (scene !== undefined) {
    roots = scene.nodes ?? [];
  } else {
    const children = new Set(nodes.flatMap((node) => node.children ?? []));
    roots = nodes.map((_, index) => index).filter((index) => !children.has(index));
  }
  const out: PlacedPrimitive[] = [];
  const visit = (index: number, parent: Mat4, depth: number) => {
    const node = nodes[index];
    if (node === undefined || depth > 64) {
      return;
    }
    const world = multiply(parent, localMatrix(node));
    if (node.mesh !== undefined) {
      for (const primitive of json.meshes?.[node.mesh]?.primitives ?? []) {
        if (primitive.attributes === undefined) {
          continue;
        }
        const placed: PlacedPrimitive = {
          matrix: world,
          attributes: primitive.attributes,
          mode: primitive.mode ?? 4,
        };
        if (primitive.indices !== undefined) {
          placed.indices = primitive.indices;
        }
        out.push(placed);
      }
    }
    for (const child of node.children ?? []) {
      visit(child, world, depth + 1);
    }
  };
  for (const root of roots) {
    visit(root, IDENTITY, 0);
  }
  return out;
}

export interface Bounds {
  min: Vec3;
  max: Vec3;
}

function grow(bounds: Bounds, p: Vec3): void {
  for (let axis = 0; axis < 3; axis += 1) {
    bounds.min[axis] = Math.min(bounds.min[axis] as number, p[axis] as number);
    bounds.max[axis] = Math.max(bounds.max[axis] as number, p[axis] as number);
  }
}

/** Resolves buffer bytes by buffer index. Undefined when the buffer is not available. */
export type BufferSource = (index: number) => Uint8Array | undefined;

const COMPONENT_SIZE: Record<number, number> = {
  5120: 1,
  5121: 1,
  5122: 2,
  5123: 2,
  5125: 4,
  5126: 4,
};
const TYPE_SIZE: Record<string, number> = { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4 };

/** Reads an accessor as numbers. Undefined when it cannot be read safely (sparse, out of range). */
export function readAccessor(
  json: GltfJson,
  index: number,
  buffers: BufferSource,
): { values: number[]; components: number } | undefined {
  const accessor = json.accessors?.[index];
  if (
    accessor === undefined ||
    accessor.sparse !== undefined ||
    accessor.bufferView === undefined
  ) {
    return undefined;
  }
  const componentSize = COMPONENT_SIZE[accessor.componentType ?? -1];
  const components = TYPE_SIZE[accessor.type ?? ""];
  const count = accessor.count;
  if (componentSize === undefined || components === undefined || !Number.isInteger(count)) {
    return undefined;
  }
  const bufferView = json.bufferViews?.[accessor.bufferView];
  if (bufferView === undefined || bufferView.buffer === undefined) {
    return undefined;
  }
  const buffer = buffers(bufferView.buffer);
  if (buffer === undefined) {
    return undefined;
  }
  const viewStart = bufferView.byteOffset ?? 0;
  const viewLength = bufferView.byteLength ?? 0;
  if (viewStart + viewLength > buffer.length) {
    return undefined;
  }
  const elementSize = componentSize * components;
  const stride = bufferView.byteStride ?? elementSize;
  const start = viewStart + (accessor.byteOffset ?? 0);
  const n = count as number;
  if (n > 0 && start + stride * (n - 1) + elementSize > viewStart + viewLength) {
    return undefined;
  }
  const v = view(buffer);
  const values: number[] = [];
  for (let i = 0; i < n; i += 1) {
    for (let c = 0; c < components; c += 1) {
      const at = start + i * stride + c * componentSize;
      switch (accessor.componentType) {
        case 5120:
          values.push(v.getInt8(at));
          break;
        case 5121:
          values.push(v.getUint8(at));
          break;
        case 5122:
          values.push(v.getInt16(at, true));
          break;
        case 5123:
          values.push(v.getUint16(at, true));
          break;
        case 5125:
          values.push(v.getUint32(at, true));
          break;
        default:
          values.push(v.getFloat32(at, true));
      }
    }
  }
  return { values, components };
}

/**
 * World-space bounds of every POSITION accessor in the scene, from the accessor min/max (required
 * by glTF for POSITION). Falls back to reading the data when min/max are absent. Undefined when
 * neither is available.
 */
export function sceneBounds(json: GltfJson, buffers: BufferSource): Bounds | undefined {
  const bounds: Bounds = {
    min: [Infinity, Infinity, Infinity],
    max: [-Infinity, -Infinity, -Infinity],
  };
  let any = false;
  for (const primitive of placedPrimitives(json)) {
    const index = primitive.attributes.POSITION;
    if (index === undefined) {
      continue;
    }
    const accessor = json.accessors?.[index];
    const min = accessor?.min;
    const max = accessor?.max;
    if (Array.isArray(min) && Array.isArray(max) && min.length === 3 && max.length === 3) {
      for (const x of [min[0], max[0]] as number[]) {
        for (const y of [min[1], max[1]] as number[]) {
          for (const z of [min[2], max[2]] as number[]) {
            grow(bounds, transformPoint(primitive.matrix, [x, y, z]));
            any = true;
          }
        }
      }
      continue;
    }
    const data = readAccessor(json, index, buffers);
    if (data === undefined || data.components !== 3) {
      return undefined;
    }
    for (let i = 0; i < data.values.length; i += 3) {
      grow(bounds, transformPoint(primitive.matrix, data.values.slice(i, i + 3) as Vec3));
      any = true;
    }
  }
  return any ? bounds : undefined;
}

/**
 * Area (m2) of triangles that are horizontal (normal within `maxTiltDeg` of the Y axis) and lie
 * at the lowest Y of the scene, within `toleranceM`. Undefined when the triangle data cannot be
 * read (for example the geometry buffer is missing).
 */
export function horizontalFloorArea(
  json: GltfJson,
  buffers: BufferSource,
  minY: number,
  toleranceM: number,
  maxTiltDeg = 5,
): number | undefined {
  const cosLimit = Math.cos((maxTiltDeg * Math.PI) / 180);
  let area = 0;
  let readAny = false;
  for (const primitive of placedPrimitives(json)) {
    const positionIndex = primitive.attributes.POSITION;
    if (positionIndex === undefined || primitive.mode !== 4) {
      continue;
    }
    const positions = readAccessor(json, positionIndex, buffers);
    if (positions === undefined || positions.components !== 3) {
      return undefined;
    }
    const vertexCount = positions.values.length / 3;
    let indices: number[];
    if (primitive.indices !== undefined) {
      const read = readAccessor(json, primitive.indices, buffers);
      if (read === undefined || read.components !== 1) {
        return undefined;
      }
      indices = read.values;
    } else {
      indices = Array.from({ length: vertexCount }, (_, i) => i);
    }
    readAny = true;
    const point = (i: number): Vec3 =>
      transformPoint(primitive.matrix, positions.values.slice(i * 3, i * 3 + 3) as Vec3);
    for (let t = 0; t + 2 < indices.length; t += 3) {
      const [ia, ib, ic] = [indices[t], indices[t + 1], indices[t + 2]] as [number, number, number];
      if (ia >= vertexCount || ib >= vertexCount || ic >= vertexCount) {
        return undefined;
      }
      const a = point(ia);
      const b = point(ib);
      const c = point(ic);
      if ([a, b, c].some((p) => Math.abs(p[1] - minY) > toleranceM)) {
        continue;
      }
      const u: Vec3 = [b[0] - a[0], b[1] - a[1], b[2] - a[2]];
      const w: Vec3 = [c[0] - a[0], c[1] - a[1], c[2] - a[2]];
      const n: Vec3 = [
        u[1] * w[2] - u[2] * w[1],
        u[2] * w[0] - u[0] * w[2],
        u[0] * w[1] - u[1] * w[0],
      ];
      const length = Math.hypot(n[0], n[1], n[2]);
      if (length === 0) {
        continue;
      }
      if (Math.abs(n[1]) / length >= cosLimit) {
        area += length / 2;
      }
    }
  }
  return readAny ? area : undefined;
}

// GLB 2.0 writer: one mesh, one node, POSITION + NORMAL + uint16 indices, +Y up, metres.

import { positionBounds, type Mesh } from "../mesh.js";
import { concatBytes, utf8 } from "../util.js";

export const GENERATOR_TAG = "chapter-fixtures 1.0.0";

export interface GlbOptions {
  /** Node and mesh name. */
  name: string;
  /** Writes the vertical axis as +Z instead of +Y (the "Z-up mesh" defect). */
  zUp?: boolean;
  /**
   * Points the only buffer at an external file and writes no BIN chunk. Used by the "missing
   * glTF BIN companion" defect: the companion file is not in the package.
   */
  externalBufferUri?: string;
}

function pad4(bytes: Uint8Array, fill: number): Uint8Array {
  const rest = bytes.length % 4;
  if (rest === 0) {
    return bytes;
  }
  const out = new Uint8Array(bytes.length + (4 - rest));
  out.fill(fill);
  out.set(bytes);
  return out;
}

/** Applies the Z-up mutation: vertical axis becomes +Z, (x, y, z) -> (x, -z, y). */
function zUpTransform(values: number[]): number[] {
  const out: number[] = [];
  for (let i = 0; i < values.length; i += 3) {
    out.push(values[i] as number, -(values[i + 2] as number), values[i + 1] as number);
  }
  return out;
}

export interface GltfParts {
  json: Record<string, unknown>;
  bin: Uint8Array;
}

/** Builds the glTF JSON and the binary buffer of a mesh. */
export function gltfParts(mesh: Mesh, options: GlbOptions): GltfParts {
  const positions = options.zUp === true ? zUpTransform(mesh.positions) : mesh.positions;
  const normals = options.zUp === true ? zUpTransform(mesh.normals) : mesh.normals;
  const vertexCount = positions.length / 3;
  if (vertexCount > 65535) {
    throw new Error("Fixture mesh too large for uint16 indices");
  }
  const positionBytes = new Uint8Array(positions.length * 4);
  const normalBytes = new Uint8Array(normals.length * 4);
  const indexBytes = new Uint8Array(mesh.indices.length * 2);
  const positionView = new DataView(positionBytes.buffer);
  const normalView = new DataView(normalBytes.buffer);
  const indexView = new DataView(indexBytes.buffer);
  positions.forEach((value, i) => positionView.setFloat32(i * 4, value, true));
  normals.forEach((value, i) => normalView.setFloat32(i * 4, value, true));
  mesh.indices.forEach((value, i) => indexView.setUint16(i * 2, value, true));
  const bounds = positionBounds(positions.map((value) => Math.fround(value)));
  const paddedIndices = pad4(indexBytes, 0);
  const bin = concatBytes([positionBytes, normalBytes, paddedIndices]);
  const json = {
    asset: { version: "2.0", generator: GENERATOR_TAG },
    scene: 0,
    scenes: [{ name: options.name, nodes: [0] }],
    nodes: [{ name: options.name, mesh: 0 }],
    meshes: [
      {
        name: options.name,
        primitives: [{ attributes: { POSITION: 0, NORMAL: 1 }, indices: 2, material: 0, mode: 4 }],
      },
    ],
    materials: [
      {
        name: "plain",
        doubleSided: true,
        pbrMetallicRoughness: {
          baseColorFactor: [0.8, 0.8, 0.8, 1],
          metallicFactor: 0,
          roughnessFactor: 1,
        },
      },
    ],
    accessors: [
      {
        bufferView: 0,
        componentType: 5126,
        count: vertexCount,
        type: "VEC3",
        min: bounds.min.map((value) => Math.fround(value)),
        max: bounds.max.map((value) => Math.fround(value)),
      },
      { bufferView: 1, componentType: 5126, count: vertexCount, type: "VEC3" },
      { bufferView: 2, componentType: 5123, count: mesh.indices.length, type: "SCALAR" },
    ],
    bufferViews: [
      { buffer: 0, byteOffset: 0, byteLength: positionBytes.length, target: 34962 },
      {
        buffer: 0,
        byteOffset: positionBytes.length,
        byteLength: normalBytes.length,
        target: 34962,
      },
      {
        buffer: 0,
        byteOffset: positionBytes.length + normalBytes.length,
        byteLength: indexBytes.length,
        target: 34963,
      },
    ],
    buffers: [
      options.externalBufferUri === undefined
        ? { byteLength: bin.length }
        : { uri: options.externalBufferUri, byteLength: bin.length },
    ],
  };
  return { json, bin };
}

/** Binary glTF (GLB) container. */
export function writeGlb(mesh: Mesh, options: GlbOptions): Uint8Array {
  const { json, bin } = gltfParts(mesh, options);
  const jsonChunk = pad4(utf8(JSON.stringify(json)), 0x20);
  const withBin = options.externalBufferUri === undefined;
  const total = 12 + 8 + jsonChunk.length + (withBin ? 8 + bin.length : 0);
  const header = new Uint8Array(12);
  const headerView = new DataView(header.buffer);
  headerView.setUint32(0, 0x46546c67, true);
  headerView.setUint32(4, 2, true);
  headerView.setUint32(8, total, true);
  const jsonHeader = new Uint8Array(8);
  const jsonHeaderView = new DataView(jsonHeader.buffer);
  jsonHeaderView.setUint32(0, jsonChunk.length, true);
  jsonHeaderView.setUint32(4, 0x4e4f534a, true);
  const parts = [header, jsonHeader, jsonChunk];
  if (withBin) {
    const binHeader = new Uint8Array(8);
    const binHeaderView = new DataView(binHeader.buffer);
    binHeaderView.setUint32(0, bin.length, true);
    binHeaderView.setUint32(4, 0x004e4942, true);
    parts.push(binHeader, bin);
  }
  return concatBytes(parts);
}

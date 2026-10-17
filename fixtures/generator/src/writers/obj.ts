// OBJ + MTL writer. Relative companion paths only; the MTL points at one tiny texture file.

import type { Mesh } from "../mesh.js";
import { fixed } from "../util.js";

export const MTL_NAME = "mesh.mtl";
export const TEXTURE_NAME = "mesh-texture.png";

export function writeObj(mesh: Mesh, name: string): string {
  const lines: string[] = [
    "# Chapter fixtures reference mesh (synthetic). Metres, +Y up.",
    `mtllib ${MTL_NAME}`,
    `o ${name}`,
  ];
  const count = mesh.positions.length / 3;
  for (let i = 0; i < count; i += 1) {
    lines.push(
      `v ${fixed(mesh.positions[i * 3] as number, 6)} ${fixed(mesh.positions[i * 3 + 1] as number, 6)} ${fixed(mesh.positions[i * 3 + 2] as number, 6)}`,
    );
  }
  for (let i = 0; i < count; i += 1) {
    lines.push(
      `vt ${fixed((mesh.uvs[i * 2] as number) * 0.25, 6)} ${fixed((mesh.uvs[i * 2 + 1] as number) * 0.25, 6)}`,
    );
  }
  for (let i = 0; i < count; i += 1) {
    lines.push(
      `vn ${fixed(mesh.normals[i * 3] as number, 6)} ${fixed(mesh.normals[i * 3 + 1] as number, 6)} ${fixed(mesh.normals[i * 3 + 2] as number, 6)}`,
    );
  }
  lines.push("usemtl plain", "s off");
  for (let i = 0; i < mesh.indices.length; i += 3) {
    const face = [0, 1, 2].map((k) => {
      const index = (mesh.indices[i + k] as number) + 1;
      return `${index}/${index}/${index}`;
    });
    lines.push(`f ${face.join(" ")}`);
  }
  return `${lines.join("\n")}\n`;
}

export function writeMtl(): string {
  return `${[
    "# Chapter fixtures material (synthetic).",
    "newmtl plain",
    "Ka 1.000000 1.000000 1.000000",
    "Kd 0.800000 0.800000 0.800000",
    "Ks 0.000000 0.000000 0.000000",
    "d 1.000000",
    "illum 1",
    `map_Kd ${TEXTURE_NAME}`,
  ].join("\n")}\n`;
}

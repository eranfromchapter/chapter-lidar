// truth.json: exact dimensions of a synthetic fixture, computed from the declarative shape and
// not from the generated files, so tests can compare the two.

import {
  localObjects,
  localPolygon2,
  localWalls,
  polygonArea,
  polygonPerimeter,
  toLocal,
} from "./geometry.js";
import type { FixtureSpec } from "./spec.js";
import { DEAL_ID, PLACEHOLDER_ADDRESS } from "./spec.js";
import { round6, type V3 } from "./util.js";

export interface TruthJson {
  fixture: string;
  description: string;
  units: "m";
  hub: { dealId: string; address: string };
  visitId: string;
  /** Tolerances the fixture claims, for tests. */
  notes: string[];
  captures: Array<{
    captureId: string;
    areaKey: string;
    label: string;
    /** Capture frame: house frame rotated about +Y and moved. Identity for single-floor fixtures. */
    frame: { rotYDeg: number; translateM: V3 };
    /** Bounding box of the room surfaces (floor, ceiling and walls) in the capture frame. */
    boundsM: { min: V3; max: V3 };
    rooms: Array<{
      id: string;
      label: string;
      /** Axis-aligned extent of the outline along the capture frame's X axis. */
      widthM: number;
      /** Axis-aligned extent of the outline along the capture frame's Z axis. */
      lengthM: number;
      heightM: number;
      areaM2: number;
      perimeterM: number;
    }>;
    walls: Array<{ id: string; lengthM: number; heightM: number }>;
    openings: Array<{
      id: string;
      kind: string;
      wallId: string;
      offsetM: number;
      bottomM: number;
      widthM: number;
      heightM: number;
    }>;
    objects: Array<{ id: string; category: string; centerM: V3; sizeM: V3 }>;
    /** The two perpendicular long distances of the field controls, in metres. */
    controlDistances: Array<{ axis: "A" | "B"; from: string; to: string; lengthM: number }>;
  }>;
  floorToFloorM?: number;
  /** Stair void notch of the floor that has it (a rectangle; sides do not depend on the frame). */
  stairVoid?: { areaKey: string; shortSideM: number; longSideM: number; areaM2: number };
  landmarks: Array<{
    id: string;
    label: string;
    /** Position in each capture's own frame. */
    positionM: Record<string, V3>;
  }>;
}

export function buildTruth(
  fixture: FixtureSpec,
  visitId: string,
  captureIds: Map<string, string>,
): TruthJson {
  const captures = fixture.captures.map((capture) => {
    const min: V3 = [Infinity, 0, Infinity];
    const max: V3 = [-Infinity, 0, -Infinity];
    let height = 0;
    for (const room of capture.rooms) {
      height = Math.max(height, room.heightM);
      for (const [x, z] of localPolygon2(capture, room.polygon)) {
        min[0] = Math.min(min[0], x);
        max[0] = Math.max(max[0], x);
        min[2] = Math.min(min[2], z);
        max[2] = Math.max(max[2], z);
      }
    }
    max[1] = height;
    return {
      captureId: captureIds.get(capture.areaKey) as string,
      areaKey: capture.areaKey,
      label: capture.label,
      frame: { rotYDeg: capture.frame.rotYDeg, translateM: capture.frame.translate },
      boundsM: { min: min.map(round6) as V3, max: max.map(round6) as V3 },
      rooms: capture.rooms.map((room) => {
        const plan = localPolygon2(capture, room.polygon);
        const xs = plan.map((p) => p[0]);
        const zs = plan.map((p) => p[1]);
        return {
          id: room.id,
          label: room.label,
          widthM: round6(Math.max(...xs) - Math.min(...xs)),
          lengthM: round6(Math.max(...zs) - Math.min(...zs)),
          heightM: room.heightM,
          areaM2: round6(polygonArea(room.polygon)),
          perimeterM: round6(polygonPerimeter(room.polygon)),
        };
      }),
      walls: localWalls(capture).map((wall) => ({
        id: wall.id,
        lengthM: round6(wall.lengthM),
        heightM: wall.heightM,
      })),
      openings: capture.openings.map((opening) => ({
        id: opening.id,
        kind: opening.kind,
        wallId: opening.wallId,
        offsetM: opening.offsetM,
        bottomM: opening.bottomM,
        widthM: opening.widthM,
        heightM: opening.heightM,
      })),
      objects: localObjects(capture).map((object) => ({
        id: object.spec.id,
        category: object.spec.category,
        centerM: object.center,
        sizeM: object.sizeM,
      })),
      controlDistances: capture.distances.map((distance) => ({
        axis: distance.axis,
        from: distance.from,
        to: distance.to,
        lengthM: distance.lengthM,
      })),
    };
  });
  const truth: TruthJson = {
    fixture: fixture.name,
    description: fixture.description,
    units: "m",
    hub: { dealId: DEAL_ID, address: PLACEHOLDER_ADDRESS },
    visitId,
    notes: [
      "Walls are scanned surfaces with thickness 0; wall centrelines coincide with room outlines.",
      "Lengths are exact; generated geometry equals these values to 0.1 mm or better.",
      "Depth samples and the LAS file carry seeded uniform noise of up to 5 mm per axis.",
    ],
    captures,
    landmarks: fixture.landmarks.map((landmark) => ({
      id: landmark.id,
      label: landmark.label,
      positionM: Object.fromEntries(
        landmark.areaKeys.map((areaKey) => {
          const capture = fixture.captures.find((c) => c.areaKey === areaKey);
          if (capture === undefined) {
            throw new Error(`Unknown areaKey ${areaKey}`);
          }
          return [areaKey, toLocal(capture.frame, landmark.position)];
        }),
      ),
    })),
  };
  if (fixture.floorToFloor !== undefined) {
    truth.floorToFloorM = fixture.floorToFloor.valueM;
  }
  if (fixture.stairVoid !== undefined) {
    const v = fixture.stairVoid;
    truth.stairVoid = {
      areaKey: v.floorAreaKey,
      shortSideM: round6(Math.min(v.maxX - v.minX, v.maxZ - v.minZ)),
      longSideM: round6(Math.max(v.maxX - v.minX, v.maxZ - v.minZ)),
      areaM2: round6((v.maxX - v.minX) * (v.maxZ - v.minZ)),
    };
  }
  return truth;
}

// Field controls (tape or laser, entered on site) that match the synthetic geometry exactly.

import type { CaptureRecord, FieldControls, Measurement } from "@chapter/capture-contract";
import type { CaptureSpec, FixtureSpec } from "./spec.js";
import { DEAL_ID, OPERATOR_NAME, PLACEHOLDER_ADDRESS } from "./spec.js";
import { atLeast, round6 } from "./util.js";

export const RECORDED_AT = "2026-10-17T15:00:00Z";
export const VISITED_AT = "2026-10-17T13:55:00Z";
export const CONFIRMED_AT = "2026-10-17T13:58:20Z";

export interface CaptureIds {
  captureId: string;
  areaKey: string;
}

type Unit = "mm" | "cm" | "m";

/** A measurement whose entered text agrees exactly with its millimetre value. */
export function measurement(valueMm: number, unit: Unit, method: "tape" | "laser"): Measurement {
  const mm = round6(valueMm);
  const text =
    unit === "mm" ? String(mm) : unit === "cm" ? String(round6(mm / 10)) : (mm / 1000).toFixed(3);
  return { valueMm: mm, enteredUnit: unit, enteredText: text, method, recordedAt: RECORDED_AT };
}

export function buildFieldControls(
  fixture: FixtureSpec,
  visitId: string,
  ids: Map<string, CaptureIds>,
  photoPaths: Map<string, string>,
): FieldControls {
  const ref = (areaKey: string) => {
    const found = ids.get(areaKey);
    if (found === undefined) {
      throw new Error(`Unknown areaKey ${areaKey}`);
    }
    return { captureId: found.captureId, areaKey: found.areaKey };
  };
  const roomLabel = (capture: CaptureSpec, wallId: string): string => {
    const wall = capture.walls.find((candidate) => candidate.id === wallId);
    const room = capture.rooms.find((candidate) => candidate.id === wall?.roomIds[0]);
    if (room === undefined) {
      throw new Error(`No room for wall ${wallId}`);
    }
    return room.label;
  };
  const distances: FieldControls["distances"] = [];
  const ceilingHeights: FieldControls["ceilingHeights"] = [];
  const openings: FieldControls["openings"] = [];
  fixture.captures.forEach((capture) => {
    const capRef = ref(capture.areaKey);
    capture.distances.forEach((distance, index) => {
      distances.push({
        id: `${capture.areaKey}-distance-${distance.axis.toLowerCase()}`,
        capture: capRef,
        axis: distance.axis,
        from: distance.from,
        to: distance.to,
        // Alternate unit and instrument so both entry styles are exercised.
        measurement: measurement(distance.lengthM * 1000, index === 0 ? "m" : "mm", "laser"),
      });
    });
    capture.rooms.forEach((room) => {
      ceilingHeights.push({
        id: `${capture.areaKey}-ceiling-${room.id}`,
        capture: capRef,
        room: room.label,
        location: "Centre of room",
        measurement: measurement(room.heightM * 1000, "cm", "tape"),
      });
    });
    capture.openings.forEach((opening) => {
      openings.push({
        id: `${capture.areaKey}-opening-${opening.id}`,
        capture: capRef,
        room: roomLabel(capture, opening.wallId),
        label: opening.label,
        width: measurement(opening.widthM * 1000, "mm", "tape"),
        height: measurement(opening.heightM * 1000, "mm", "tape"),
      });
    });
  });
  const floorToFloor: FieldControls["floorToFloor"] = [];
  if (fixture.floorToFloor !== undefined) {
    const f = fixture.floorToFloor;
    floorToFloor.push({
      id: `${f.lowerAreaKey}-${f.upperAreaKey}-stair`,
      lower: ref(f.lowerAreaKey),
      upper: ref(f.upperAreaKey),
      location: f.location,
      measurement: measurement(f.valueM * 1000, "cm", "laser"),
    });
  }
  const landmarks: FieldControls["landmarks"] = fixture.landmarks.map((landmark) => {
    const photos = landmark.areaKeys
      .map((areaKey) => photoPaths.get(areaKey))
      .filter((path): path is string => path !== undefined);
    return {
      id: landmark.id,
      label: landmark.label,
      description: landmark.description,
      captures: atLeast(landmark.areaKeys.map(ref), 2),
      photoPaths: photos,
    };
  });
  return {
    schemaVersion: "1.0.0",
    visitId,
    distances,
    ceilingHeights,
    openings,
    floorToFloor,
    landmarks,
  };
}

/** Builds the capture record of a visit. */
export function buildCaptureRecord(
  fixture: FixtureSpec,
  visitId: string,
  ids: Map<string, CaptureIds>,
): CaptureRecord {
  return {
    schemaVersion: "1.0.0",
    visitId,
    hub: { dealId: DEAL_ID, projectName: `Fixture ${fixture.name}` },
    address: { formatted: PLACEHOLDER_ADDRESS, confirmedOnSite: true, confirmedAt: CONFIRMED_AT },
    operator: { name: OPERATOR_NAME, userId: "00000000-0000-4000-8000-000000000001" },
    device: {
      model: "iPhone17,1",
      marketingName: "iPhone 16 Pro",
      osName: "iOS",
      osVersion: "26.0.1",
      hasLidar: true,
    },
    app: { version: "1.0.0", build: "fixture" },
    visitedAt: VISITED_AT,
    captures: atLeast(
      fixture.captures.map((capture, index) => {
        const minute = String(2 + index * 30).padStart(2, "0");
        const end = String(20 + index * 30).padStart(2, "0");
        return {
          captureId: (ids.get(capture.areaKey) as CaptureIds).captureId,
          areaKey: capture.areaKey,
          label: capture.label,
          mode: capture.mode,
          units: { length: "m" as const, display: "metric" as const },
          capturedAt: `2026-10-17T14:${minute}:11Z`,
          finishedAt: `2026-10-17T14:${end}:40Z`,
          coverageNotes: capture.coverageNotes,
          omittedRooms: [],
          inaccessibleRooms: [],
        };
      }),
      1,
    ),
  };
}

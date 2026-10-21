// "What revision N adds" (web-review §6.3.4, addendum D7): the phone's next-revision notice
// (tiles, compact line, "answers limitation i", the verdict card's suffix) and the diff of two
// station revisions.

import type { Verdict } from "@chapter/capture-contract";
import { describe, expect, it } from "vitest";
import {
  answeredLimitation,
  changedControls,
  inProgressLine,
  noticeCompactLine,
  noticeTiles,
  stationDiff,
  visibleTiles,
} from "@/lib/revision-diff";
import type { NextRevisionChange, NextRevisionNotice, StationPackage } from "@/lib/station-types";
import { contractExampleCase } from "./support/fixtures";
import { sampleLimitedVerdict, sampleNextRevision } from "./support/scenarios";

const verdict = sampleLimitedVerdict();
const record = undefined;

describe("the phone's revision 2 of the 424 sample (as drawn)", () => {
  const notice = sampleNextRevision(verdict, "2026-10-21T17:00:00Z");

  it("words the compact Contents line", () => {
    expect(noticeCompactLine(notice.changes)).toBe("+ primary closet · + 1 control · + 3 photos");
  });

  it("builds the drawn tiles with the answered limitation", () => {
    expect(noticeTiles(notice, verdict, record)).toEqual([
      { title: "Primary closet scanned", sub: "answers limitation 1 · coverage" },
      { title: "Room 4 ceiling height, tape", sub: "2,490 mm" },
      { title: "3 photos", sub: "primary closet · general, ceiling, opening" },
    ]);
  });

  it("says how many next actions the revision answers", () => {
    expect(inProgressLine(notice, verdict)).toBe(
      "Revision 2 is in progress on the phone with 1 of the 2 next actions.",
    );
  });
});

describe("answersNextAction to a limitation index (G-7)", () => {
  it("finds the limitation as the station words it, with the capture label prefix", () => {
    const second = verdict.nextActions[1] as string;
    expect(answeredLimitation({ answersNextAction: second }, verdict, undefined)).toBe(2);
    expect(answeredLimitation({ answersNextAction: "Something else" }, verdict, undefined)).toBe(
      undefined,
    );
    expect(answeredLimitation({}, verdict, undefined)).toBe(undefined);
    expect(answeredLimitation({ answersNextAction: second }, null, undefined)).toBe(undefined);
  });

  it("uses the message alone for a finding without a capture", () => {
    const plain: Verdict = {
      ...verdict,
      limitations: ["Ceiling heights are approximate.", "Room 4 is missing."],
      findings: [
        {
          ruleId: "coverage.rooms",
          severity: "limitation",
          message: "Room 4 is missing.",
          nextAction: "Scan Room 4.",
        },
      ],
      nextActions: ["Scan Room 4."],
    };
    expect(answeredLimitation({ answersNextAction: "Scan Room 4." }, plain, undefined)).toBe(2);
  });
});

describe("the verdict card's suffix", () => {
  const change = (answersNextAction?: string): NextRevisionChange => ({
    kind: "added",
    subject: "capture",
    title: "Primary closet",
    detail: "Scanned · one room · 5 files",
    ...(answersNextAction === undefined ? {} : { answersNextAction }),
  });
  const notice = (changes: NextRevisionChange[]): NextRevisionNotice => ({
    revision: 2,
    updatedAt: "2026-10-21T17:00:00Z",
    changes,
  });
  const withActions = (actions: string[]): Verdict => ({ ...verdict, nextActions: actions });

  it.each([
    [[], ["A", "B"], "Revision 2 is in progress on the phone."],
    [["A"], ["A"], "Revision 2 is in progress on the phone with this next action."],
    [["A", "B"], ["A", "B"], "Revision 2 is in progress on the phone with both."],
    [["A", "B", "C"], ["A", "B", "C"], "Revision 2 is in progress on the phone with all 3."],
    [
      ["A", "A"],
      ["A", "B", "C"],
      "Revision 2 is in progress on the phone with 1 of the 3 next actions.",
    ],
    [["Z"], ["A"], "Revision 2 is in progress on the phone."],
  ])("answers %j of %j: %s", (answered, actions, line) => {
    expect(
      inProgressLine(notice(answered.map((action) => change(action))), withActions(actions)),
    ).toBe(line);
  });
});

describe("tiles of every change subject", () => {
  const notice: NextRevisionNotice = {
    revision: 3,
    updatedAt: "2026-10-21T17:00:00Z",
    changes: [
      {
        kind: "added",
        subject: "capture",
        title: "Garage",
        detail: "Scanned · exterior · 7 files",
      },
      {
        kind: "changed",
        subject: "field_control",
        title: "Floor 1 long distance A",
        detail: "Field control · changed to 7,520 mm · 24' 8\"",
      },
      {
        kind: "added",
        subject: "field_control",
        title: "Landmark Stair post",
        detail: "Field control · 2 floors",
      },
      { kind: "added", subject: "photos", title: "1 photo", detail: "Garage · door" },
      { kind: "added", subject: "photos", title: "4 photos", detail: "Kitchen · general" },
      {
        kind: "changed",
        subject: "room_names",
        title: "Floor 1 room names",
        detail: "Room 3 → Office · 2 files",
      },
      {
        kind: "removed",
        subject: "retired_file",
        title: "Spatial report PDF from the phone",
        detail: "Retired · the station makes the spatial report · 1 file",
      },
    ],
  };

  it("words each tile", () => {
    expect(noticeTiles(notice, null, undefined)).toEqual([
      { title: "Garage scanned", sub: "scanned · exterior · 7 files" },
      { title: "Floor 1 long distance A", sub: "changed to 7,520 mm" },
      { title: "Landmark Stair post", sub: "field control · 2 floors" },
      { title: "1 photo", sub: "garage · door" },
      { title: "4 photos", sub: "kitchen · general" },
      { title: "Floor 1 room names", sub: "Room 3 → Office · 2 files" },
      {
        title: "Spatial report PDF from the phone",
        sub: "Retired · the station makes the spatial report · 1 file",
      },
    ]);
  });

  it("counts controls and photos once each in the compact line", () => {
    expect(noticeCompactLine(notice.changes)).toBe(
      "+ garage · + 2 controls · + 5 photos · + room names · − phone report",
    );
  });

  it("shows six tiles and counts the rest", () => {
    const tiles = noticeTiles(notice, null, undefined);
    expect(visibleTiles(tiles).shown).toHaveLength(6);
    expect(visibleTiles(tiles).more).toBe(1);
  });
});

describe("two station revisions", () => {
  const base = contractExampleCase().pkg;
  const controls = base.fieldControls;
  if (controls === undefined) {
    throw new Error("the contract example has field controls");
  }
  const controlsFile = base.files.find((file) => file.role === "field_controls");

  function revision(changes: Partial<StationPackage>): StationPackage {
    return {
      ...base,
      packageId: "99999999-9999-4999-8999-999999999999",
      revision: 2,
      supersedesPackageId: base.packageId,
      status: "uploading",
      ...changes,
    };
  }

  it("names a new capture with its mode and files", () => {
    const newCapture = {
      captureId: "c0000000-0000-4000-8000-000000000001",
      areaKey: "primary-closet",
    };
    const after = revision({
      captures: [...base.captures, newCapture],
      files: [
        ...base.files,
        {
          path: `Original Exports/primary-closet/${newCapture.captureId}/plan.dxf`,
          role: "plan_dxf",
          ...newCapture,
          sha256: "a".repeat(64),
          bytes: 100,
          status: "pending",
        },
      ],
    });
    const diff = stationDiff(base, after);
    expect(diff.tiles[0]).toEqual({ title: "Primary closet scanned", sub: "new capture · 1 file" });
    expect(diff.compact).toBe("+ primary closet");
  });

  it("names a removed capture", () => {
    const [kept, dropped] = base.captures;
    const after = revision({
      captures: kept === undefined ? [] : [kept],
      files: base.files.filter((file) => file.captureId !== dropped?.captureId),
    });
    const diff = stationDiff(base, after);
    expect(diff.tiles[0]).toEqual({ title: "Floor 2 removed", sub: "not in revision 2" });
    expect(diff.compact).toBe("− floor 2");
  });

  it("lists added and changed controls of every kind once both are sealed", () => {
    const [distance] = controls.distances;
    const [ceiling] = controls.ceilingHeights;
    const [opening] = controls.openings;
    if (distance === undefined || ceiling === undefined || opening === undefined) {
      throw new Error("the contract example has a distance, a ceiling height and an opening");
    }
    const changed = {
      ...controls,
      distances: [
        {
          ...distance,
          measurement: { ...distance.measurement, valueMm: 7520, method: "tape" as const },
        },
        ...controls.distances.slice(1),
      ],
      ceilingHeights: [
        ...controls.ceilingHeights,
        {
          ...ceiling,
          id: "new-ceiling",
          room: "Room 4",
          measurement: { ...ceiling.measurement, valueMm: 2490, method: "tape" as const },
        },
      ],
      openings: [
        ...controls.openings,
        {
          ...opening,
          id: "new-opening",
          room: "Hall",
          label: "door",
          width: { ...opening.width, valueMm: 812 },
        },
      ],
    };
    const tiles = changedControls(controls, changed);
    expect(tiles).toEqual([
      { title: "Distance A, tape", sub: `${distance.from} to ${distance.to} · 7,520 mm` },
      { title: "Room 4 ceiling height, tape", sub: "2,490 mm" },
      { title: `Hall door, ${opening.width.method}`, sub: "812 mm wide" },
    ]);
    const after = revision({
      status: "checks_queued",
      fieldControls: changed,
      files: base.files.map((file) =>
        file === controlsFile ? { ...file, sha256: "b".repeat(64) } : file,
      ),
    });
    expect(stationDiff(base, after).compact).toBe("+ 3 controls");
  });

  it("says the field controls changed while the new revision is not sealed", () => {
    const { fieldControls: _controls, ...unsealed } = revision({
      files: base.files.map((file) =>
        file === controlsFile ? { ...file, sha256: "c".repeat(64) } : file,
      ),
    });
    const diff = stationDiff(base, unsealed);
    expect(diff.tiles).toEqual([
      { title: "Field controls updated", sub: "field-controls.json changed" },
    ]);
    expect(diff.compact).toBe("+ controls");
  });

  it("counts added photos and other changed files", () => {
    const photo = base.files.find((file) => file.role === "photo");
    const dxf = base.files.find((file) => file.role === "plan_dxf");
    if (photo === undefined || dxf === undefined) {
      throw new Error("the contract example has a photo and a plan DXF");
    }
    const after = revision({
      files: [
        ...base.files.map((file) => (file === dxf ? { ...file, sha256: "d".repeat(64) } : file)),
        { ...photo, path: photo.path.replace(/[^/]+$/, "photo-9001.jpg"), sha256: "e".repeat(64) },
        { ...photo, path: photo.path.replace(/[^/]+$/, "photo-9002.jpg"), sha256: "f".repeat(64) },
      ],
    });
    const diff = stationDiff(base, after);
    expect(diff.tiles).toEqual([
      { title: "2 photos", sub: "floor 1" },
      { title: "1 file changed", sub: "Plan DXF" },
    ]);
    expect(diff.compact).toBe("+ 2 photos · 1 file changed");
  });
});

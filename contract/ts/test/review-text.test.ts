// The shared verdict words (web-review 5, spatial-report 8.5 merged by critique R-15c/R-15d):
// check rows, counts, headlines, rule set label and the not-scanned room texts.

import assert from "node:assert/strict";
import { join } from "node:path";
import { describe, it } from "node:test";
import {
  OUTCOME_WORD,
  RESULT_WORD,
  checkCounts,
  checkRows,
  countsLine,
  lowerFirst,
  notScannedRoomText,
  notScannedRooms,
  notScannedText,
  ruleResult,
  ruleSetLabel,
  sortCheckRows,
  verdictHeadline,
  type CaptureRecord,
  type Finding,
  type Verdict,
} from "../src/index.js";
import { examplesDir, readJson } from "./paths.js";

const verdict = readJson(join(examplesDir, "verdict", "valid", "limited.json")) as Verdict;
const record = readJson(
  join(examplesDir, "capture-record", "valid", "two-captures.json"),
) as CaptureRecord;

function finding(change: Partial<Finding>): Finding {
  return {
    ruleId: "coverage.rooms",
    severity: "info",
    message: "Message.",
    nextAction: "None",
    ...change,
  };
}

describe("lowerFirst", () => {
  it("lower-cases the first letter only when the second is lower case", () => {
    assert.equal(
      lowerFirst("Preliminary existing-condition plans"),
      "preliminary existing-condition plans",
    );
    assert.equal(lowerFirst("PDF plans"), "PDF plans");
    assert.equal(lowerFirst("A plan"), "A plan");
    assert.equal(lowerFirst("3D model"), "3D model");
    assert.equal(lowerFirst("X"), "X");
    assert.equal(lowerFirst(""), "");
  });
});

describe("ruleResult", () => {
  const check = { ruleId: "coverage.rooms", title: "Coverage", status: "passed" } as const;

  it("is not applicable whenever the station says so", () => {
    assert.equal(
      ruleResult({ ...check, status: "not_applicable" }, [finding({ severity: "blocker" })]),
      "not_applicable",
    );
  });

  it("is blocked with a blocker finding of its rule only", () => {
    assert.equal(
      ruleResult({ ...check, status: "failed" }, [finding({ severity: "blocker" })]),
      "blocked",
    );
    assert.equal(
      ruleResult(check, [finding({ severity: "blocker", ruleId: "units.scale" })]),
      "passed",
    );
  });

  it("is limited when the check failed or a limitation finding names it", () => {
    assert.equal(ruleResult({ ...check, status: "failed" }, []), "limited");
    assert.equal(ruleResult(check, [finding({ severity: "limitation" })]), "limited");
  });

  it("is passed otherwise", () => {
    assert.equal(ruleResult(check, [finding({})]), "passed");
  });
});

describe("checkRows", () => {
  it("gives one row per check of the contract example, in order, with its result", () => {
    const rows = checkRows(verdict);
    assert.deepEqual(
      rows.map((row) => [row.ruleId, row.title, row.result, row.word, row.glyph, row.tone]),
      [
        ["manifest.fingerprints", "Fingerprints", "passed", "Passed", "circle", "success"],
        ["units.scale", "Units and scale", "passed", "Passed", "circle", "success"],
        ["floors.registration", "Floor registration", "limited", "Limited", "triangle", "warning"],
        ["coverage.rooms", "Coverage", "limited", "Limited", "triangle", "warning"],
      ],
    );
  });

  it("shows each finding with its measured and expected values", () => {
    const [, scale, floors, coverage] = checkRows(verdict);
    assert.deepEqual(
      scale?.found.map((block) => [block.message, block.values]),
      [
        [
          "Plan distances agree with tape controls.",
          "Measured: Distance A -0.4%, B +0.2% vs tape · Expected: Within 1% or 25.4 mm, whichever is larger",
        ],
      ],
    );
    assert.equal(
      floors?.found[0]?.values,
      "Measured: 1 shared landmark · Expected: 2 shared landmarks",
    );
    assert.equal(coverage?.found[0]?.values, undefined);
  });

  it("lists distinct next actions without None", () => {
    const rows = checkRows(verdict);
    assert.deepEqual(rows[1]?.nextActions, []);
    assert.deepEqual(rows[2]?.nextActions, ["Record a second landmark at the stair."]);
  });

  it("prefixes the capture label only when the package has several captures", () => {
    const coverage = (rows: ReturnType<typeof checkRows>) =>
      rows.find((row) => row.ruleId === "coverage.rooms")?.found[0]?.message;
    assert.equal(coverage(checkRows(verdict)), "Primary closet not scanned (locked).");
    assert.equal(
      coverage(checkRows(verdict, record)),
      "Floor 1: Primary closet not scanned (locked).",
    );
    const one = structuredClone(record);
    one.captures = [one.captures[0] as CaptureRecord["captures"][0]];
    assert.equal(coverage(checkRows(verdict, one)), "Primary closet not scanned (locked).");
  });

  it("falls back to the areaKey for a capture missing from the record", () => {
    const changed = structuredClone(verdict);
    const item = changed.findings.find((entry) => entry.ruleId === "coverage.rooms") as Finding;
    item.captureId = "00000000-0000-4000-8000-0000000000ff";
    item.areaKey = "basement";
    const row = checkRows(changed, record).find((entry) => entry.ruleId === "coverage.rooms");
    assert.equal(row?.found[0]?.message, "basement: Primary closet not scanned (locked).");
  });

  it("orders a row's findings blocker, limitation, info and keeps station order inside", () => {
    const changed = structuredClone(verdict);
    changed.checks = [{ ruleId: "coverage.rooms", title: "Coverage", status: "failed" }];
    changed.findings = [
      finding({ message: "Info 1." }),
      finding({ severity: "limitation", message: "Limitation 1.", nextAction: "Act A." }),
      finding({ severity: "blocker", message: "Blocker 1.", nextAction: "Act B." }),
      finding({ severity: "limitation", message: "Limitation 2.", nextAction: "Act A." }),
    ];
    const [row] = checkRows(changed);
    assert.deepEqual(
      row?.found.map((block) => block.message),
      ["Blocker 1.", "Limitation 1.", "Limitation 2.", "Info 1."],
    );
    assert.deepEqual(row?.nextActions, ["Act B.", "Act A."]);
    assert.equal(row?.result, "blocked");
  });

  it("adds a row for findings whose rule has no check, from the worst severity", () => {
    const changed = structuredClone(verdict);
    changed.findings.push(
      finding({ ruleId: "orientation.compass", severity: "info" }),
      finding({ ruleId: "orientation.compass", severity: "limitation", nextAction: "Read again." }),
      finding({ ruleId: "legacy.rule", severity: "info" }),
    );
    const rows = checkRows(changed);
    assert.deepEqual(
      rows.slice(4).map((row) => [row.ruleId, row.title, row.result, row.found.length]),
      [
        ["orientation.compass", "orientation.compass", "limited", 2],
        ["legacy.rule", "legacy.rule", "passed", 1],
      ],
    );
  });
});

describe("sortCheckRows, checkCounts and countsLine", () => {
  const rows = checkRows({
    ...verdict,
    checks: [
      { ruleId: "a.passed", title: "A", status: "passed" },
      { ruleId: "b.na", title: "B", status: "not_applicable" },
      { ruleId: "c.limited", title: "C", status: "failed" },
      { ruleId: "d.blocked", title: "D", status: "failed" },
      { ruleId: "e.passed", title: "E", status: "passed" },
    ],
    findings: [finding({ ruleId: "d.blocked", severity: "blocker" })],
  });

  it("sorts blocked, limited, passed, not applicable, stable inside", () => {
    assert.deepEqual(
      sortCheckRows(rows).map((row) => row.ruleId),
      ["d.blocked", "c.limited", "a.passed", "e.passed", "b.na"],
    );
  });

  it("counts rules, not findings", () => {
    assert.deepEqual(checkCounts(rows), {
      blockers: 1,
      limitations: 1,
      passed: 2,
      notApplicable: 1,
    });
    assert.equal(
      countsLine(checkCounts(checkRows(verdict))),
      "0 blockers · 2 limitations · 2 passed · 0 not applicable",
    );
  });

  it("writes singular and plural", () => {
    assert.equal(
      countsLine(checkCounts(rows)),
      "1 blocker · 1 limitation · 2 passed · 1 not applicable",
    );
    assert.equal(
      countsLine({ blockers: 0, limitations: 2, passed: 5, notApplicable: 2 }),
      "0 blockers · 2 limitations · 5 passed · 2 not applicable",
    );
  });
});

describe("verdict words", () => {
  it("names the outcomes and results", () => {
    assert.deepEqual(OUTCOME_WORD, { ready: "Ready", limited: "Limited", blocked: "Blocked" });
    assert.deepEqual(RESULT_WORD, {
      passed: "Passed",
      limited: "Limited",
      blocked: "Blocked",
      not_applicable: "Not applicable",
    });
  });

  it("writes the headline of each outcome", () => {
    assert.equal(
      verdictHeadline({ outcome: "ready", task: "Preliminary existing-condition plans" }),
      "Ready for preliminary existing-condition plans",
    );
    assert.equal(verdictHeadline(verdict), "Limited: usable with named limitations");
    assert.equal(
      verdictHeadline({ outcome: "blocked", task: verdict.task }),
      "Blocked: missing information prevents the task",
    );
  });

  it("labels the rule set as name v version", () => {
    assert.equal(
      ruleSetLabel({ name: "station-checks", version: "1.1.0" }),
      "station-checks v1.1.0",
    );
    assert.equal(ruleSetLabel({ name: "other/checks", version: "2.0.0" }), "other/checks v2.0.0");
    assert.equal(ruleSetLabel({ name: "constructor", version: "1.0.0" }), "constructor v1.0.0");
  });

  it("prints the station checks as station-checks, the name the design draws", () => {
    // The evaluator every station verdict carries (station/checks EVALUATOR), as in the
    // verdict example and the sample-424 report fixtures.
    assert.equal(verdict.evaluator.name, "chapter-capture-station/checks");
    assert.equal(ruleSetLabel(verdict.evaluator), `station-checks v${verdict.evaluator.version}`);
    assert.equal(
      ruleSetLabel({ name: "chapter-capture-station/checks", version: "1.1.0" }),
      "station-checks v1.1.0",
    );
  });
});

describe("not-scanned rooms", () => {
  function withRooms(
    floor1: Partial<Pick<CaptureRecord["captures"][0], "omittedRooms" | "inaccessibleRooms">>,
    floor2: Partial<Pick<CaptureRecord["captures"][0], "omittedRooms" | "inaccessibleRooms">> = {},
  ): CaptureRecord {
    const copy = structuredClone(record);
    Object.assign(copy.captures[0] as object, { omittedRooms: [], inaccessibleRooms: [] }, floor1);
    Object.assign(copy.captures[1] as object, { omittedRooms: [], inaccessibleRooms: [] }, floor2);
    return copy;
  }

  it("prints None when every room was scanned", () => {
    assert.equal(notScannedText(withRooms({})), "None");
  });

  it("prints one capture's rooms joined with a middle dot (the drawn sample)", () => {
    const one = withRooms({
      omittedRooms: [{ name: "Primary closet", reason: "locked" }],
      inaccessibleRooms: [{ name: "Storage room" }],
    });
    one.captures = [one.captures[0] as CaptureRecord["captures"][0]];
    assert.equal(notScannedText(one), "Primary closet (locked) · Storage room (could not enter)");
  });

  it("words each kind with and without a reason", () => {
    const rooms = notScannedRooms(
      withRooms({
        omittedRooms: [{ name: "Attic", reason: "no access hatch" }, { name: "Garage" }],
        inaccessibleRooms: [{ name: "Storage room" }, { name: "Cellar", reason: "flooded" }],
      }),
    );
    assert.deepEqual(
      rooms.map((room) => notScannedRoomText(room)),
      [
        "Attic (no access hatch)",
        "Garage (not scanned)",
        "Storage room (could not enter)",
        "Cellar (could not enter: flooded)",
      ],
    );
    assert.deepEqual(
      rooms.map((room) => notScannedRoomText(room, true)),
      [
        "Attic (Floor 1, no access hatch)",
        "Garage (Floor 1, not scanned)",
        "Storage room (Floor 1, could not enter)",
        "Cellar (Floor 1, could not enter: flooded)",
      ],
    );
  });

  it("prefixes each capture's list with its label when the visit has several", () => {
    assert.equal(
      notScannedText(
        withRooms(
          { inaccessibleRooms: [{ name: "Primary closet", reason: "locked" }] },
          { omittedRooms: [{ name: "Attic" }], inaccessibleRooms: [{ name: "Storage room" }] },
        ),
      ),
      "Floor 1: Primary closet (could not enter: locked)\nFloor 2: Attic (not scanned) · Storage room (could not enter)",
    );
    assert.equal(
      notScannedText(withRooms({}, { omittedRooms: [{ name: "Attic" }] })),
      "Floor 2: Attic (not scanned)",
    );
  });

  it("keeps the capture of every room", () => {
    const rooms = notScannedRooms(withRooms({}, { omittedRooms: [{ name: "Attic" }] }));
    assert.deepEqual(rooms, [
      {
        captureId: "a81d5f03-6c2e-4b97-8d14-2f9e7b3c5a60",
        areaKey: "floor-2",
        floorLabel: "Floor 2",
        name: "Attic",
        kind: "omitted",
      },
    ]);
  });
});

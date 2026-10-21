// Capture record 1.1.0 (compass spec 4.1): readers accept 1.0.0 and 1.1.0; the compass fields
// are optional, only allowed in a 1.1.0 document, present together, and never together with
// headingIssue.

import assert from "node:assert/strict";
import { join } from "node:path";
import { describe, it } from "node:test";
import { formatErrors, validateCaptureRecord, type CaptureRecord } from "../src/index.js";
import { examplesDir, readJson } from "./paths.js";

const v100 = readJson(
  join(examplesDir, "capture-record", "valid", "two-captures.json"),
) as CaptureRecord;
const v110 = readJson(
  join(examplesDir, "capture-record", "valid", "compass-two-captures.json"),
) as CaptureRecord;

type MutableCapture = Record<string, unknown>;

function changed(
  record: CaptureRecord,
  change: (copy: CaptureRecord, floor1: MutableCapture, floor2: MutableCapture) => void,
): CaptureRecord {
  const copy = structuredClone(record);
  change(
    copy,
    copy.captures[0] as unknown as MutableCapture,
    copy.captures[1] as unknown as MutableCapture,
  );
  return copy;
}

function assertValid(record: unknown): void {
  const result = validateCaptureRecord(record);
  assert.ok(result.ok, result.ok ? "" : formatErrors(result.errors));
}

/** Fails unless the record is rejected with an error at each pointer (and possibly at the root). */
function assertRejectedAt(record: unknown, pointers: string[]): void {
  const result = validateCaptureRecord(record);
  assert.equal(result.ok, false, "expected the record to fail the schema");
  const at = new Set(result.errors.map((error) => error.instancePath));
  for (const pointer of pointers) {
    assert.ok(at.has(pointer), `no error at ${pointer}:\n${formatErrors(result.errors)}`);
  }
  const stray = [...at].filter((pointer) => pointer !== "" && !pointers.includes(pointer));
  assert.deepEqual(stray, [], formatErrors(result.errors));
}

describe("capture record schema versions", () => {
  it("accepts 1.0.0 and 1.1.0", () => {
    assert.equal(v100.schemaVersion, "1.0.0");
    assert.equal(v110.schemaVersion, "1.1.0");
    assertValid(v100);
    assertValid(v110);
  });

  it("accepts a 1.0.0 record relabelled 1.1.0, so writers can always write 1.1.0", () => {
    assertValid(changed(v100, (record) => (record.schemaVersion = "1.1.0")));
  });

  it("rejects any other version", () => {
    for (const version of ["1.2.0", "2.0.0", "1.1", ""]) {
      assertRejectedAt({ ...v110, schemaVersion: version }, ["/schemaVersion"]);
    }
  });

  it("rejects each 1.1.0 field in a 1.0.0 record, at the field", () => {
    assertRejectedAt(
      changed(v110, (record) => (record.schemaVersion = "1.0.0")),
      [
        "/captures/0/heading",
        "/captures/0/headingAccuracy",
        "/captures/0/headingSource",
        "/captures/0/headingRecordedAt",
        "/captures/1/headingIssue",
      ],
    );
  });
});

describe("capture record 1.1.0 compass fields", () => {
  it("allows a capture without any compass field (no reading taken)", () => {
    assertValid(
      changed(v110, (_record, _floor1, floor2) => {
        delete floor2["headingIssue"];
      }),
    );
  });

  it("requires heading, headingAccuracy, headingSource and headingRecordedAt together", () => {
    for (const key of ["heading", "headingAccuracy", "headingSource", "headingRecordedAt"]) {
      assertRejectedAt(
        changed(v110, (_record, floor1) => {
          delete floor1[key];
        }),
        ["/captures/0"],
      );
    }
  });

  it("never has headingIssue together with heading", () => {
    assertRejectedAt(
      changed(v110, (_record, floor1) => (floor1["headingIssue"] = "rejected")),
      ["/captures/0"],
    );
  });

  it("keeps heading in [0, 360)", () => {
    for (const heading of [0, 0.1, 212.4, 359.9]) {
      assertValid(changed(v110, (_record, floor1) => (floor1["heading"] = heading)));
    }
    for (const heading of [360, 360.5, -0.1]) {
      assertRejectedAt(
        changed(v110, (_record, floor1) => (floor1["heading"] = heading)),
        ["/captures/0/heading"],
      );
    }
  });

  it("stores headingAccuracy as a whole number of degrees from 1 to 180", () => {
    for (const accuracy of [1, 8, 30, 180]) {
      assertValid(changed(v110, (_record, floor1) => (floor1["headingAccuracy"] = accuracy)));
    }
    for (const accuracy of [0, 2.5, 181, -1]) {
      assertRejectedAt(
        changed(v110, (_record, floor1) => (floor1["headingAccuracy"] = accuracy)),
        ["/captures/0/headingAccuracy"],
      );
    }
  });

  it("closes headingSource and headingIssue", () => {
    assertRejectedAt(
      changed(v110, (_record, floor1) => (floor1["headingSource"] = "grid")),
      ["/captures/0/headingSource"],
    );
    assertRejectedAt(
      changed(v110, (_record, _floor1, floor2) => (floor2["headingIssue"] = "noisy")),
      ["/captures/1/headingIssue"],
    );
    for (const issue of ["rejected", "not_calibrated", "unavailable"]) {
      assertValid(changed(v110, (_record, _floor1, floor2) => (floor2["headingIssue"] = issue)));
    }
  });

  it("takes headingRecordedAt as a UTC timestamp with whole seconds", () => {
    assertRejectedAt(
      changed(v110, (_record, floor1) => (floor1["headingRecordedAt"] = "2026-10-17T14:02:20.5Z")),
      ["/captures/0/headingRecordedAt"],
    );
  });
});

// Orientation words on the web (compass spec §9, web-review addendum D1), from the contract's
// evaluator over the shared test vectors: the boundaries 10 verified, 11 approximate,
// 30 approximate, 31 not verified; magnetic 5 approximate; missing not verified.

import { compassState, type CompassState } from "@chapter/capture-contract";
import { describe, expect, it } from "vitest";
import {
  compassRecordSentence,
  compassRecordText,
  orientationSentence,
  orientationText,
} from "@/lib/compass";
import type { CaptureRecord } from "@/lib/station-types";
import { readJson } from "./support/fixtures";

interface Vector {
  name: string;
  capture: Parameters<typeof compassState>[0];
  expected: { kind: CompassState["kind"]; reason?: string };
}

const vectors = readJson<Vector[]>("contract/test-vectors/compass-states.json");
const capture = (fields: Record<string, unknown>) =>
  ({
    capturedAt: "2026-10-17T14:02:11Z",
    finishedAt: "2026-10-17T14:21:40Z",
    headingRecordedAt: "2026-10-17T14:02:20Z",
    ...fields,
  }) as Parameters<typeof compassState>[0];

describe("plan card Orientation (D1)", () => {
  it.each([
    [
      { heading: 212.4, headingAccuracy: 10, headingSource: "true" },
      "Verified · true north from the compass, ±10°. The plan sheet shows the north arrow.",
    ],
    [
      { heading: 212.4, headingAccuracy: 11, headingSource: "true" },
      "Approximate · compass ±11°, true north. The plan sheet shows an approximate north arrow.",
    ],
    [
      { heading: 212.4, headingAccuracy: 30, headingSource: "true" },
      "Approximate · compass ±30°, true north. The plan sheet shows an approximate north arrow.",
    ],
    [
      { heading: 212.4, headingAccuracy: 31, headingSource: "true" },
      "Not verified · compass accuracy ±31°. North is not shown.",
    ],
    [
      { heading: 87.5, headingAccuracy: 5, headingSource: "magnetic" },
      "Approximate · compass ±5°, magnetic north. The plan sheet shows an approximate north arrow.",
    ],
    [{ headingRecordedAt: undefined }, "Not verified · no compass reading. North is not shown."],
    [
      { headingRecordedAt: undefined, headingIssue: "rejected" },
      "Not verified · the compass reading was rejected. North is not shown.",
    ],
    [
      { headingRecordedAt: undefined, headingIssue: "not_calibrated" },
      "Not verified · the compass was not calibrated. North is not shown.",
    ],
    [
      { headingRecordedAt: undefined, headingIssue: "unavailable" },
      "Not verified · no compass on the phone. North is not shown.",
    ],
  ])("%j reads %s", (fields, text) => {
    expect(orientationSentence(compassState(capture(fields)))).toBe(text);
  });

  it("covers every state of the shared compass vectors", () => {
    expect(vectors.length).toBeGreaterThan(20);
    for (const vector of vectors) {
      const sentence = orientationSentence(compassState(vector.capture));
      const prefix = {
        verified: "Verified · ",
        approximate: "Approximate · ",
        not_verified: "Not verified · ",
      }[vector.expected.kind];
      expect(sentence.startsWith(prefix), vector.name).toBe(true);
    }
  });
});

describe("capture record Compass (D1)", () => {
  it.each([
    [{ heading: 212.4, headingAccuracy: 8, headingSource: "true" }, "Verified · 212° true, ±8°"],
    [
      { heading: 87.5, headingAccuracy: 12, headingSource: "magnetic" },
      "Approximate · 88° magnetic, ±12°",
    ],
    [{ headingRecordedAt: undefined }, "Not read · orientation not verified"],
    [
      { headingRecordedAt: undefined, headingIssue: "not_calibrated" },
      "Not read · orientation not verified",
    ],
    [
      { headingRecordedAt: undefined, headingIssue: "rejected" },
      "Rejected · orientation not verified",
    ],
    [
      { heading: 10, headingAccuracy: 42, headingSource: "true" },
      "±42° · orientation not verified",
    ],
  ])("one capture %j reads %s", (fields, text) => {
    expect(compassRecordSentence(compassState(capture(fields)))).toBe(text);
  });

  it("joins each floor's word when the visit has several captures", () => {
    const record = readJson<CaptureRecord>(
      "contract/examples/capture-record/valid/compass-two-captures.json",
    );
    expect(compassRecordText(record)).toBe("Floor 1 verified · Floor 2 not verified");
    const [first] = record.captures;
    expect(compassRecordText({ ...record, captures: [first] })).toBe("Verified · 212° true, ±8°");
    expect(orientationText(record.captures[1] as CaptureRecord["captures"][number])).toBe(
      "Not verified · the compass reading was rejected. North is not shown.",
    );
  });
});

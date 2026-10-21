// Compass spec 13.2: the shared evaluator gives every vector in
// contract/test-vectors/compass-states.json its expected state, symbol, detail and word. The
// Swift CaptureContract runs the same file (CompassTests), so phone and station agree.

import assert from "node:assert/strict";
import { join } from "node:path";
import { describe, it } from "node:test";
import {
  COMPASS_APPROXIMATE_MAX,
  COMPASS_VERIFIED_MAX,
  compassDetail,
  compassState,
  compassWord,
  formatAccuracy,
  formatHeading,
  formatErrors,
  isUsable,
  northSymbol,
  validateCaptureRecord,
  type CaptureRecord,
  type CompassFields,
  type NorthSymbol,
} from "../src/index.js";
import { contractDir, examplesDir, readJson } from "./paths.js";

interface Vector {
  name: string;
  capture: CompassFields;
  rotationCcw: number;
  expected: {
    kind: "verified" | "approximate" | "not_verified";
    reason?: string;
    accuracy?: number;
    word: string;
    symbol: NorthSymbol;
    detail: string;
  };
}

const vectors = readJson(join(contractDir, "test-vectors", "compass-states.json")) as Vector[];
const record = readJson(
  join(examplesDir, "capture-record", "valid", "compass-two-captures.json"),
) as CaptureRecord;

function assertSymbol(actual: NorthSymbol, expected: NorthSymbol, label: string): void {
  if (actual.kind === "arrow" && expected.kind === "arrow") {
    assert.ok(Math.abs(actual.angleCcw - expected.angleCcw) < 1e-9, `${label}: angle`);
    assert.deepEqual({ ...actual, angleCcw: 0 }, { ...expected, angleCcw: 0 }, label);
  } else {
    assert.deepEqual(actual, expected, label);
  }
}

describe("compass test vectors", () => {
  it("covers every state and reason", () => {
    assert.ok(vectors.length >= 30);
    const seen = new Set(vectors.map((vector) => vector.expected.reason ?? vector.expected.kind));
    for (const value of [
      "verified",
      "approximate",
      "no_reading",
      "rejected",
      "inaccurate",
      "not_calibrated",
      "unavailable",
    ]) {
      assert.ok(seen.has(value), value);
    }
  });

  it("every vector's capture fields are valid in a 1.1.0 capture record", () => {
    for (const vector of vectors) {
      const document = structuredClone(record);
      const base = { ...document.captures[0] } as Record<string, unknown>;
      for (const key of Object.keys(base).filter((key) => key.startsWith("heading"))) {
        delete base[key];
      }
      delete base["finishedAt"];
      document.captures = [{ ...base, ...vector.capture } as CaptureRecord["captures"][0]];
      const result = validateCaptureRecord(document);
      assert.ok(result.ok, `${vector.name}: ${result.ok ? "" : formatErrors(result.errors)}`);
    }
  });

  for (const vector of vectors) {
    it(vector.name, () => {
      const state = compassState(vector.capture);
      const { expected } = vector;
      assert.equal(state.kind, expected.kind);
      if (state.kind === "not_verified") {
        assert.equal(state.reason, expected.reason);
        assert.equal(state.accuracy, expected.accuracy);
      } else {
        assert.equal(expected.reason, undefined);
        assert.equal(state.heading, vector.capture.heading);
        assert.equal(state.accuracy, vector.capture.headingAccuracy);
        assert.equal(state.source, vector.capture.headingSource);
      }
      assertSymbol(northSymbol(state, vector.rotationCcw), expected.symbol, vector.name);
      assert.equal(compassDetail(state), expected.detail);
      assert.equal(compassWord(state), expected.word);
      assert.equal(isUsable(state), expected.kind !== "not_verified");
    });
  }
});

describe("compass evaluator", () => {
  it("uses the thresholds ±10° and ±30°", () => {
    assert.equal(COMPASS_VERIFIED_MAX, 10);
    assert.equal(COMPASS_APPROXIMATE_MAX, 30);
  });

  it("reads the example record: Floor 1 verified, Floor 2 rejected", () => {
    assert.deepEqual(
      record.captures.map((capture) => compassWord(compassState(capture))),
      ["verified", "not verified"],
    );
  });

  it("rejects a heading without its accuracy, source or time (not a valid 1.1.0 record)", () => {
    const capture = record.captures[0] as CompassFields;
    for (const key of ["headingAccuracy", "headingSource", "headingRecordedAt"] as const) {
      const broken = { ...capture };
      delete broken[key];
      assert.deepEqual(compassState(broken), { kind: "not_verified", reason: "rejected" }, key);
    }
  });

  it("ignores headingIssue when a heading is present", () => {
    const capture = {
      ...(record.captures[0] as CompassFields),
      headingIssue: "unavailable" as const,
    };
    assert.equal(compassState(capture).kind, "verified");
  });

  it("defaults the drawing rotation to 0", () => {
    const state = compassState(record.captures[0] as CompassFields);
    assert.deepEqual(northSymbol(state), northSymbol(state, 0));
  });

  it("formats headings half up, mod 360, without the degree sign", () => {
    const cases: [number, string][] = [
      [212.4, "212"],
      [212.5, "213"],
      [359.4, "359"],
      [359.5, "0"],
      [360, "0"],
      [0, "0"],
      [-0.4, "0"],
      [-0.6, "359"],
      [720.2, "0"],
    ];
    for (const [degrees, text] of cases) {
      assert.equal(formatHeading(degrees), text, String(degrees));
    }
    assert.equal(formatAccuracy(8), "8");
  });

  it("never uses a character the phone PDF writer cannot print", () => {
    const texts = vectors.flatMap((vector) => {
      const state = compassState(vector.capture);
      const symbol = northSymbol(state, vector.rotationCcw);
      const lines = symbol.kind === "arrow" ? symbol.lines : [symbol.box, symbol.caption];
      return [...lines, compassDetail(state)];
    });
    for (const text of texts) {
      assert.doesNotMatch(text, /[−′″≈]/, text);
    }
  });
});

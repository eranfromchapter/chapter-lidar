// Check 11: floor registration. Two captures are registered when at least two shared landmarks in
// the field controls name both of them. Every capture of the visit must be connected to the
// others through registered pairs; otherwise "floor alignment not established" is a limitation.
// Separate capture origins are not evidence of alignment, so nothing in the models is used.

import type { CaptureInfo, CheckContext } from "../context.js";
import { NO_ACTION, count, finding } from "../finding.js";
import type { CheckOutput, StationFinding } from "../types.js";

export const MIN_SHARED_LANDMARKS = 2;

export function checkRegistration(ctx: CheckContext): CheckOutput {
  const findings: StationFinding[] = [];
  const captures = ctx.captures();
  const controlsPath = ctx.controlsPath();
  if (captures.length < 2) {
    findings.push(
      finding({
        ruleId: "floors.registration",
        severity: "info",
        message: "One capture in this visit; no floor registration is needed.",
        filePath: ctx.recordPath(),
        measured: count(captures.length, "capture"),
        nextAction: NO_ACTION,
      }),
    );
    return { findings, notApplicable: true };
  }
  const controls = ctx.pkg.fieldControls;
  if (controls === undefined && ctx.firstOfRole("field_controls") !== undefined) {
    findings.push(
      finding({
        ruleId: "floors.registration",
        severity: "info",
        message: "Floor registration not evaluated: the field controls cannot be read.",
        filePath: controlsPath,
        measured: "not evaluated",
        nextAction: NO_ACTION,
      }),
    );
    return { findings, notApplicable: true };
  }

  const key = (capture: { captureId: string; areaKey: string }) =>
    `${capture.captureId}|${capture.areaKey}`;
  const index = new Map(captures.map((capture, i) => [key(capture), i]));
  const shared = captures.map(() => captures.map(() => 0));
  for (const landmark of controls?.landmarks ?? []) {
    const seen = [
      ...new Set(
        landmark.captures
          .map((capture) => index.get(key(capture)))
          .filter((i): i is number => i !== undefined),
      ),
    ];
    for (const a of seen) {
      for (const b of seen) {
        if (a !== b) {
          (shared[a] as number[])[b] = ((shared[a] as number[])[b] as number) + 1;
        }
      }
    }
  }
  // Connected components over registered pairs.
  const component = captures.map((_, i) => i);
  const find = (i: number): number => {
    let root = i;
    while (component[root] !== root) {
      root = component[root] as number;
    }
    return root;
  };
  for (let a = 0; a < captures.length; a += 1) {
    for (let b = a + 1; b < captures.length; b += 1) {
      if (((shared[a] as number[])[b] as number) >= MIN_SHARED_LANDMARKS) {
        component[find(b)] = find(a);
      }
    }
  }
  const groups = new Map<number, CaptureInfo[]>();
  captures.forEach((capture, i) => {
    const root = find(i);
    groups.set(root, [...(groups.get(root) ?? []), capture]);
  });
  const pairText = (a: number, b: number) =>
    `${(captures[a] as CaptureInfo).label} - ${(captures[b] as CaptureInfo).label}: ${count((shared[a] as number[])[b] as number, "shared landmark")}`;
  const pairs: string[] = [];
  for (let a = 0; a < captures.length; a += 1) {
    for (let b = a + 1; b < captures.length; b += 1) {
      pairs.push(pairText(a, b));
    }
  }
  const floorToFloor = controls?.floorToFloor.length ?? 0;
  if (groups.size > 1) {
    const listed = [...groups.values()]
      .map((group) => group.map((capture) => capture.label).join(" + "))
      .join(" and ");
    findings.push(
      finding({
        ruleId: "floors.registration",
        severity: "limitation",
        message: `Floor alignment not established between ${listed}: fewer than ${MIN_SHARED_LANDMARKS} shared landmarks link them.`,
        filePath: controlsPath,
        measured: `${pairs.join("; ")}; ${count(floorToFloor, "floor-to-floor level")}`,
        expected: `every capture linked to the others by at least ${MIN_SHARED_LANDMARKS} shared landmarks`,
        nextAction:
          "Record at least two landmarks visible from both floors (for example at the stair) with photos on the next visit.",
      }),
    );
    return { findings };
  }
  findings.push(
    finding({
      ruleId: "floors.registration",
      severity: "info",
      message:
        "Every capture is registered to the others through pairs of captures that share at least two landmarks.",
      filePath: controlsPath,
      measured: `${pairs.join("; ")}; ${count(floorToFloor, "floor-to-floor level")}`,
      expected: `at least ${MIN_SHARED_LANDMARKS} shared landmarks`,
      nextAction: NO_ACTION,
    }),
  );
  return { findings };
}

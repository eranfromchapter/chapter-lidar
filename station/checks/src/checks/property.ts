// Check 3: the package belongs to the HUB property (address after normalization) and its files
// belong to the visit and captures the capture record registers.

import type { CheckContext } from "../context.js";
import { NO_ACTION, finding, scopeOf } from "../finding.js";
import { addressesMatch, normalizeAddress } from "../address.js";
import type { CheckOutput, StationFinding } from "../types.js";

export function checkProperty(ctx: CheckContext): CheckOutput {
  const findings: StationFinding[] = [];
  const record = ctx.pkg.captureRecord;
  const recordEntry = ctx.firstOfRole("capture_record");
  if (record === undefined) {
    if (recordEntry !== undefined && ctx.bytes(recordEntry.path) !== undefined) {
      // Present but empty or invalid: check 2 already blocks the package.
      findings.push(
        finding({
          ruleId: "property.address",
          severity: "info",
          message:
            "Property not evaluated: the capture record cannot be read (see files.parseable).",
          filePath: recordEntry.path,
          measured: "capture record unreadable",
          nextAction: NO_ACTION,
        }),
      );
      return { findings, notApplicable: true };
    }
    if (recordEntry !== undefined) {
      return { findings, notApplicable: true }; // Listed but missing: check 1 blocks.
    }
    findings.push(
      finding({
        ruleId: "property.address",
        severity: "blocker",
        message:
          "The package has no capture record, so the property and floors cannot be confirmed.",
        filePath: ctx.manifestPath,
        measured: "no capture_record file in the manifest",
        expected: "Source Register/{visitId}/capture-record.json",
        nextAction: "Re-seal the package on the device with its capture record and re-upload.",
      }),
    );
    return { findings };
  }
  const recordPath = ctx.recordPath();
  const recorded = record.address.formatted;

  if (normalizeAddress(ctx.hubAddress).length === 0) {
    findings.push(
      finding({
        ruleId: "property.address",
        severity: "blocker",
        message: "No HUB address was supplied, so the property cannot be confirmed.",
        filePath: recordPath,
        measured: `recorded "${recorded}"; HUB address empty`,
        expected: "the HUB project address",
        nextAction: "Check the HUB project link of this visit (deal id) and run the checks again.",
      }),
    );
  } else if (!addressesMatch(recorded, ctx.hubAddress)) {
    findings.push(
      finding({
        ruleId: "property.address",
        severity: "blocker",
        message: "Capture record address does not match the HUB project address.",
        filePath: recordPath,
        measured: `recorded "${recorded}"`,
        expected: `HUB "${ctx.hubAddress}" (after normalization)`,
        nextAction:
          "Confirm the property with the sales team; correct the HUB project link or recapture at the confirmed address.",
      }),
    );
  } else {
    findings.push(
      finding({
        ruleId: "property.address",
        severity: "info",
        message: record.address.confirmedOnSite
          ? "Capture record address matches the HUB address and was confirmed on site."
          : "Capture record address matches the HUB address; the operator did not confirm it on site.",
        filePath: recordPath,
        measured: `recorded "${recorded}"; confirmed on site: ${record.address.confirmedOnSite ? "yes" : "no"}`,
        expected: `HUB "${ctx.hubAddress}"`,
        nextAction: NO_ACTION,
      }),
    );
  }

  // The files belong to this visit and to captures the record registers.
  const manifest = ctx.pkg.manifest;
  if (record.visitId !== manifest.visitId) {
    findings.push(
      finding({
        ruleId: "property.address",
        severity: "blocker",
        message: "Capture record belongs to a different visit than the manifest.",
        filePath: recordPath,
        measured: `capture record visitId ${record.visitId}`,
        expected: `manifest visitId ${manifest.visitId}`,
        nextAction: "Re-seal the package on the device so every file belongs to one visit.",
      }),
    );
  }
  const controls = ctx.pkg.fieldControls;
  if (controls !== undefined && controls.visitId !== manifest.visitId) {
    findings.push(
      finding({
        ruleId: "property.address",
        severity: "blocker",
        message: "Field controls belong to a different visit than the manifest.",
        filePath: ctx.controlsPath(),
        measured: `field controls visitId ${controls.visitId}`,
        expected: `manifest visitId ${manifest.visitId}`,
        nextAction: "Re-seal the package on the device so every file belongs to one visit.",
      }),
    );
  }
  const registered = new Map(
    record.captures.map((capture) => [capture.captureId, capture.areaKey]),
  );
  const reported = new Set<string>();
  for (const entry of manifest.files) {
    if (entry.captureId === undefined || reported.has(entry.captureId)) {
      continue;
    }
    const areaKey = registered.get(entry.captureId);
    if (areaKey === entry.areaKey) {
      continue;
    }
    reported.add(entry.captureId);
    findings.push(
      finding({
        ruleId: "property.address",
        severity: "blocker",
        message:
          areaKey === undefined
            ? "Package files belong to a capture the capture record does not register."
            : "Package files name a different floor or area than the capture record registers.",
        filePath: entry.path,
        ...scopeOf(entry),
        measured: `captureId ${entry.captureId}, areaKey ${entry.areaKey ?? "none"}`,
        expected:
          areaKey === undefined ? "a captureId listed in the capture record" : `areaKey ${areaKey}`,
        nextAction:
          "Re-seal the package on the device so every file belongs to a registered capture.",
      }),
    );
  }
  for (const capture of record.captures) {
    const lookup = ctx.model(capture.captureId);
    if (lookup.state !== "ok") {
      continue;
    }
    const model = lookup.model;
    if (
      model.captureId !== capture.captureId ||
      model.areaKey !== capture.areaKey ||
      model.visitId !== manifest.visitId
    ) {
      findings.push(
        finding({
          ruleId: "property.address",
          severity: "blocker",
          message:
            "Capture model names a different visit, capture or floor than its place in the package.",
          filePath: lookup.entry.path,
          ...scopeOf(capture),
          measured: `model visitId ${model.visitId}, captureId ${model.captureId}, areaKey ${model.areaKey}`,
          expected: `visitId ${manifest.visitId}, captureId ${capture.captureId}, areaKey ${capture.areaKey}`,
          nextAction: "Re-export the capture on the device and re-seal the package.",
        }),
      );
    }
  }
  return { findings };
}

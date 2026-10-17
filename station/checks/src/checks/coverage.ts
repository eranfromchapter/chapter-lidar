// Check 9: coverage. Every room of each capture model has at least one site photo labelled with
// that room (manifest photo.room, compared case-insensitively with collapsed whitespace); omitted
// and inaccessible rooms from the capture record are listed as limitations.

import type { CheckContext } from "../context.js";
import { NO_ACTION, count, finding, scopeOf } from "../finding.js";
import type { CheckOutput, StationFinding } from "../types.js";

function normalizeRoom(text: string): string {
  return text.normalize("NFKC").toLowerCase().replace(/\s+/g, " ").trim();
}

export function checkCoverage(ctx: CheckContext): CheckOutput {
  const findings: StationFinding[] = [];
  const record = ctx.pkg.captureRecord;
  const recordPath = ctx.recordPath();
  let evaluated = 0;

  for (const capture of ctx.captures()) {
    const scope = scopeOf(capture);
    const lookup = ctx.model(capture.captureId);
    if (lookup.state === "ok") {
      evaluated += 1;
      const photos = ctx.entriesFor(capture.captureId, "photo");
      const labels = new Set(
        photos
          .map((entry) => entry.photo?.room)
          .filter((room): room is string => room !== undefined)
          .map(normalizeRoom),
      );
      const rooms = lookup.model.rooms;
      const missing = rooms.filter((room) => !labels.has(normalizeRoom(room.label)));
      for (const room of missing) {
        findings.push(
          finding({
            ruleId: "coverage.rooms",
            severity: "limitation",
            message: `No site photo of ${room.label}.`,
            filePath: lookup.entry.path,
            ...scope,
            measured: `0 photos labelled "${room.label}" (${count(photos.length, "photo")} for ${capture.label})`,
            expected: "at least one labelled photo per captured room",
            nextAction: `Photograph ${room.label} (room, openings, ceiling and details) on the next visit.`,
          }),
        );
      }
      if (missing.length === 0) {
        findings.push(
          finding({
            ruleId: "coverage.rooms",
            severity: "info",
            message: `Every captured room of ${capture.label} has at least one photo.`,
            filePath: lookup.entry.path,
            ...scope,
            measured: `${rooms.length - missing.length} of ${count(rooms.length, "room")} photographed; ${count(photos.length, "photo")}`,
            expected: "at least one photo per captured room",
            nextAction: NO_ACTION,
          }),
        );
      }
    }

    const registered = record?.captures.find((item) => item.captureId === capture.captureId);
    if (registered === undefined) {
      continue;
    }
    evaluated += 1;
    const noted = [
      ...registered.omittedRooms.map((room) => ({ room, kind: "omitted by the operator" })),
      ...registered.inaccessibleRooms.map((room) => ({ room, kind: "inaccessible" })),
    ];
    for (const { room, kind } of noted) {
      findings.push(
        finding({
          ruleId: "coverage.rooms",
          severity: "limitation",
          message: `${room.name} not captured (${kind}${room.reason === undefined ? "" : `: ${room.reason}`}).`,
          filePath: recordPath,
          ...scope,
          measured: `${room.name}: ${kind}`,
          expected: "every room in scope captured",
          nextAction: `Scan or measure ${room.name} on the next visit if it is in scope.`,
        }),
      );
    }
    if (registered.coverageNotes.trim() !== "") {
      findings.push(
        finding({
          ruleId: "coverage.rooms",
          severity: "info",
          message: `Coverage note for ${capture.label} recorded by the operator.`,
          filePath: recordPath,
          ...scope,
          measured: registered.coverageNotes,
          nextAction: NO_ACTION,
        }),
      );
    }
  }
  return evaluated === 0 ? { findings, notApplicable: true } : { findings };
}

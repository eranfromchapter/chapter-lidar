// "What revision N adds" (web-review §6.3.4 and addendum D7). Two sources:
//
// - The phone's next-revision notice (Package.nextRevision): while the operator works on
//   revision N on the phone, before it is sealed. Rows are worded by the phone; the web turns
//   them into tiles, the compact "Contents" line and "answers limitation i".
// - Two station packages (revision B > 1 without a verdict, and A = the package it supersedes):
//   compared by file path and SHA-256 and by capture id.

import { lowerFirst, type Verdict } from "@chapter/capture-contract";
import { captureLabel, formatMm, MODE_LABEL, plural, ROLE_LABEL } from "./format";
import type {
  CaptureRecord,
  FieldControls,
  NextRevisionChange,
  NextRevisionNotice,
  PackageFile,
  StationPackage,
} from "./station-types";

/** One tile of the card. */
export interface ChangeTile {
  readonly title: string;
  readonly sub: string;
}

/** At most this many tiles are shown; the rest are counted in "+{k} more changes". */
export const MAX_TILES = 6;

/** The card's tiles: the first six, and how many more there are. */
export function visibleTiles(tiles: readonly ChangeTile[]): {
  shown: readonly ChangeTile[];
  more: number;
} {
  return { shown: tiles.slice(0, MAX_TILES), more: Math.max(0, tiles.length - MAX_TILES) };
}

// ---------------------------------------------------------------------------------------------
// The phone's notice (D7)

/** The leading integer of a photos title ("3 photos" -> 3); 0 when there is none. */
function leadingCount(title: string): number {
  const match = /^(\d+)/.exec(title.trim());
  return match === null ? 0 : Number(match[1]);
}

/**
 * The compact "Contents" line of a revision on the phone, from its changes in order: "+ primary
 * closet · + 1 control · + 3 photos". Controls and photos are counted into one part each, at the
 * place of their first change.
 */
export function noticeCompactLine(changes: readonly NextRevisionChange[]): string {
  const controls = changes.filter((change) => change.subject === "field_control").length;
  const photos = changes
    .filter((change) => change.subject === "photos")
    .reduce((sum, change) => sum + leadingCount(change.title), 0);
  const parts: string[] = [];
  let controlsDone = false;
  let photosDone = false;
  for (const change of changes) {
    switch (change.subject) {
      case "capture":
        parts.push(`${change.kind === "removed" ? "−" : "+"} ${change.title.toLowerCase()}`);
        break;
      case "field_control":
        if (!controlsDone) {
          parts.push(`+ ${plural(controls, "control")}`);
          controlsDone = true;
        }
        break;
      case "photos":
        if (!photosDone) {
          parts.push(`+ ${plural(photos, "photo")}`);
          photosDone = true;
        }
        break;
      case "room_names":
        if (!parts.includes("+ room names")) {
          parts.push("+ room names");
        }
        break;
      case "retired_file":
        if (!parts.includes("− phone report")) {
          parts.push("− phone report");
        }
        break;
    }
  }
  return parts.join(" · ");
}

/**
 * The 1-based index in the base verdict's limitations of the limitation a change answers: the
 * first limitation finding whose next action is the change's `answersNextAction`, written as
 * the station writes limitations ("{capture label}: {message}" when the finding names a
 * capture). Undefined when the change answers nothing or the limitation is not found.
 */
export function answeredLimitation(
  change: Pick<NextRevisionChange, "answersNextAction">,
  verdict: Verdict | null | undefined,
  record: CaptureRecord | undefined,
): number | undefined {
  const action = change.answersNextAction;
  if (action === undefined || verdict === null || verdict === undefined) {
    return undefined;
  }
  const finding = verdict.findings.find(
    (item) => item.severity === "limitation" && item.nextAction === action,
  );
  if (finding === undefined) {
    return undefined;
  }
  const label =
    finding.captureId === undefined
      ? undefined
      : captureLabel(record, finding.captureId, finding.areaKey);
  const text = label === undefined ? finding.message : `${label}: ${finding.message}`;
  const index = verdict.limitations.indexOf(text);
  return index < 0 ? undefined : index + 1;
}

/** The detail segment that ends in " mm" ("Field control · 2,490 mm · 8' 2"" -> "2,490 mm"). */
function millimetres(detail: string): string | undefined {
  return detail
    .split(" · ")
    .map((part) => part.trim())
    .find((part) => part.endsWith(" mm"));
}

/** Tiles of a revision on the phone, in the order of its changes. */
export function noticeTiles(
  notice: NextRevisionNotice,
  baseVerdict: Verdict | null | undefined,
  baseRecord: CaptureRecord | undefined,
): ChangeTile[] {
  return notice.changes.map((change) => {
    const index = answeredLimitation(change, baseVerdict, baseRecord);
    switch (change.subject) {
      case "capture": {
        const title =
          change.kind === "removed" ? `${change.title} removed` : `${change.title} scanned`;
        return {
          title,
          sub:
            index === undefined
              ? lowerFirst(change.detail)
              : `answers limitation ${index} · coverage`,
        };
      }
      case "field_control": {
        const title =
          change.method === undefined ? change.title : `${change.title}, ${change.method}`;
        const mm = millimetres(change.detail);
        if (index !== undefined) {
          return {
            title,
            sub: `answers limitation ${index}${mm === undefined ? "" : ` · ${mm}`}`,
          };
        }
        return { title, sub: mm ?? lowerFirst(change.detail) };
      }
      case "photos":
        return { title: change.title, sub: lowerFirst(change.detail) };
      case "room_names":
      case "retired_file":
        return { title: change.title, sub: change.detail };
    }
  });
}

/**
 * The verdict card's line about the revision on the phone (D7): "Revision 2 is in progress on the
 * phone with both." The suffix counts the base next actions the changes answer.
 */
export function inProgressLine(notice: NextRevisionNotice, verdict: Verdict): string {
  const total = verdict.nextActions.length;
  const answered = new Set(
    notice.changes
      .map((change) => change.answersNextAction)
      .filter(
        (action): action is string => action !== undefined && verdict.nextActions.includes(action),
      ),
  ).size;
  let suffix: string;
  if (answered === 0) {
    suffix = ".";
  } else if (answered === total && total === 1) {
    suffix = " with this next action.";
  } else if (answered === total && total === 2) {
    suffix = " with both.";
  } else if (answered === total) {
    suffix = ` with all ${total}.`;
  } else {
    suffix = ` with ${answered} of the ${total} next actions.`;
  }
  return `Revision ${notice.revision} is in progress on the phone${suffix}`;
}

// ---------------------------------------------------------------------------------------------
// Two station packages (§6.3.4)

/** The tiles and the compact line of a station revision compared with the one it supersedes. */
export interface StationDiff {
  readonly tiles: ChangeTile[];
  readonly compact: string;
}

type Control =
  | { kind: "distance"; value: FieldControls["distances"][number] }
  | { kind: "ceiling"; value: FieldControls["ceilingHeights"][number] }
  | { kind: "opening"; value: FieldControls["openings"][number] }
  | { kind: "floorToFloor"; value: FieldControls["floorToFloor"][number] }
  | { kind: "landmark"; value: FieldControls["landmarks"][number] };

function controlsOf(controls: FieldControls): Control[] {
  return [
    ...controls.distances.map((value) => ({ kind: "distance" as const, value })),
    ...controls.ceilingHeights.map((value) => ({ kind: "ceiling" as const, value })),
    ...controls.openings.map((value) => ({ kind: "opening" as const, value })),
    ...controls.floorToFloor.map((value) => ({ kind: "floorToFloor" as const, value })),
    ...controls.landmarks.map((value) => ({ kind: "landmark" as const, value })),
  ];
}

/** Everything that defines a control's value (ids and recording times aside). */
function controlValue(control: Control): string {
  const { id: _id, ...rest } = control.value;
  return JSON.stringify(rest, (key, value: unknown) => (key === "recordedAt" ? undefined : value));
}

function controlTile(control: Control): ChangeTile {
  switch (control.kind) {
    case "distance": {
      const { axis, from, to, measurement } = control.value;
      return {
        title: `Distance ${axis}, ${measurement.method}`,
        sub: `${from} to ${to} · ${formatMm(measurement.valueMm)}`,
      };
    }
    case "ceiling": {
      const { room, measurement } = control.value;
      return {
        title: `${room} ceiling height, ${measurement.method}`,
        sub: formatMm(measurement.valueMm),
      };
    }
    case "opening": {
      const { room, label, width } = control.value;
      return { title: `${room} ${label}, ${width.method}`, sub: `${formatMm(width.valueMm)} wide` };
    }
    case "floorToFloor": {
      const { location, measurement } = control.value;
      return {
        title: `Floor to floor, ${measurement.method}`,
        sub: `${location} · ${formatMm(measurement.valueMm)}`,
      };
    }
    case "landmark":
      return {
        title: `Landmark: ${control.value.label}`,
        sub: plural(control.value.captures.length, "capture"),
      };
  }
}

/** Added or changed controls of `after` compared with `before`, by control id. */
export function changedControls(before: FieldControls, after: FieldControls): ChangeTile[] {
  const old = new Map(controlsOf(before).map((control) => [control.value.id, control]));
  return controlsOf(after)
    .filter((control) => {
      const previous = old.get(control.value.id);
      return previous === undefined || controlValue(previous) !== controlValue(control);
    })
    .map(controlTile);
}

interface CaptureInfo {
  captureId: string;
  label: string;
  mode?: "room" | "floor" | "exterior";
}

function capturesOf(pkg: StationPackage): CaptureInfo[] {
  return pkg.captures.map((capture) => ({
    captureId: capture.captureId,
    label:
      capture.label ??
      captureLabel(pkg.captureRecord, capture.captureId, capture.areaKey) ??
      capture.areaKey,
    ...(capture.mode === undefined ? {} : { mode: capture.mode }),
  }));
}

function bySha(files: readonly PackageFile[]): Map<string, string> {
  return new Map(files.map((file) => [file.path, file.sha256]));
}

/** Changes of station package `after` (revision B) against `before` (the revision it supersedes). */
export function stationDiff(before: StationPackage, after: StationPackage): StationDiff {
  const tiles: ChangeTile[] = [];
  const compact: string[] = [];
  const beforeCaptures = new Set(before.captures.map((capture) => capture.captureId));
  const afterCaptures = new Set(after.captures.map((capture) => capture.captureId));
  const beforeFiles = bySha(before.files);

  const added = capturesOf(after).filter((capture) => !beforeCaptures.has(capture.captureId));
  for (const capture of added) {
    const files = after.files.filter((file) => file.captureId === capture.captureId).length;
    tiles.push({
      title: `${capture.label} scanned`,
      sub: `${capture.mode === undefined ? "new capture" : MODE_LABEL[capture.mode]} · ${plural(files, "file")}`,
    });
    compact.push(`+ ${capture.label.toLowerCase()}`);
  }
  const removed = capturesOf(before).filter((capture) => !afterCaptures.has(capture.captureId));
  for (const capture of removed) {
    tiles.push({ title: `${capture.label} removed`, sub: `not in revision ${after.revision}` });
    compact.push(`− ${capture.label.toLowerCase()}`);
  }

  const controlsFile = after.files.find((file) => file.role === "field_controls");
  const controlsChanged =
    controlsFile !== undefined && beforeFiles.get(controlsFile.path) !== controlsFile.sha256;
  if (controlsChanged) {
    if (before.fieldControls !== undefined && after.fieldControls !== undefined) {
      const controls = changedControls(before.fieldControls, after.fieldControls);
      tiles.push(...controls);
      if (controls.length > 0) {
        compact.push(`+ ${plural(controls.length, "control")}`);
      }
    } else if (after.fieldControls === undefined) {
      tiles.push({ title: "Field controls updated", sub: "field-controls.json changed" });
      compact.push("+ controls");
    }
  }

  const newPhotos = after.files.filter(
    (file) => file.role === "photo" && !beforeFiles.has(file.path),
  );
  if (newPhotos.length > 0) {
    const labels: string[] = [];
    for (const photo of newPhotos) {
      const label = (
        captureLabel(after.captureRecord, photo.captureId, photo.areaKey) ??
        capturesOf(after).find((capture) => capture.captureId === photo.captureId)?.label ??
        ""
      ).toLowerCase();
      if (label.length > 0 && !labels.includes(label)) {
        labels.push(label);
      }
    }
    tiles.push({ title: plural(newPhotos.length, "photo"), sub: labels.join(" · ") });
    compact.push(`+ ${plural(newPhotos.length, "photo")}`);
  }

  // Same path, another fingerprint. The field controls are told above; the capture record
  // always changes when a capture is added or removed, so it is not told again then.
  const capturesChanged = added.length > 0 || removed.length > 0;
  const changed = after.files.filter((file) => {
    const previous = beforeFiles.get(file.path);
    if (previous === undefined || previous === file.sha256 || file.role === "field_controls") {
      return false;
    }
    return !(file.role === "capture_record" && capturesChanged);
  });
  if (changed.length > 0) {
    const roles: string[] = [];
    for (const file of changed) {
      const role = ROLE_LABEL[file.role];
      if (!roles.includes(role)) {
        roles.push(role);
      }
    }
    const text = `${plural(changed.length, "file")} changed`;
    tiles.push({ title: text, sub: roles.join(", ") });
    compact.push(text);
  }
  return { tiles, compact: compact.join(" · ") };
}

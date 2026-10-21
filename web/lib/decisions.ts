// Modeling decision log: the form's fields and limits (OpenAPI ModelingDecisionInput), the
// "Source used" options built from the package (web-review §6.4.8) and how logged sources are
// worded in the entries (§6.4.7).
//
// An option's value is a key ("file:{path}", "filectl:{dxf path}|{controlId}", "ctl:{controlId}",
// "photos:{captureId}"). The server action rebuilds the options from the package and resolves
// the posted key again, so a posted path is never forwarded to the station.

import type { FieldControls } from "@chapter/capture-contract";
import { captureLabel, fileDisplayName, pathDisplayName } from "./format";
import type {
  CaptureRecord,
  DecisionSource,
  ModelingDecision,
  ModelingDecisionInput,
  PackageFile,
  StationPackage,
} from "./station-types";

export interface DecisionFormValues {
  readonly element: string;
  /** The option key of the source used. */
  readonly source: string;
  readonly decision: string;
  /** "Remaining uncertainty and next check", sent as the decision's note. */
  readonly note: string;
}

/** Form state; `attempt` counts answers so the form remounts with the echoed values. */
export type DecisionFormState =
  | { readonly status: "idle"; readonly attempt: number }
  | { readonly status: "saved"; readonly attempt: number; readonly message: string }
  | {
      readonly status: "error";
      readonly attempt: number;
      readonly message: string;
      readonly values: DecisionFormValues;
    };

export const EMPTY_VALUES: DecisionFormValues = { element: "", source: "", decision: "", note: "" };

export const LIMITS = {
  element: 300,
  decision: 2000,
  note: 2000,
  path: 1024,
  /** A source key: "filectl:" + path + "|" + control id. */
  sourceKey: 1200,
} as const;

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

export function isPackageId(value: unknown): value is string {
  return typeof value === "string" && UUID_PATTERN.test(value);
}

function text(form: FormData, name: string): string {
  const value = form.get(name);
  return typeof value === "string" ? value.trim() : "";
}

/** The submitted values, echoed back so the form keeps them after an error. */
export function formValues(form: FormData): DecisionFormValues {
  return {
    element: text(form, "element"),
    source: text(form, "source"),
    decision: text(form, "decision"),
    note: text(form, "note"),
  };
}

export type ParsedDecision =
  | {
      readonly ok: true;
      readonly packageId: string;
      readonly sourceKey: string;
      readonly element: string;
      readonly decision: string;
      readonly note?: string;
    }
  | { readonly ok: false; readonly message: string; readonly values: DecisionFormValues };

/** Validates the decision form. The source key is resolved against the package afterwards. */
export function parseDecisionForm(form: FormData): ParsedDecision {
  const values = formValues(form);
  const packageId = text(form, "packageId");
  const problems: string[] = [];
  if (!isPackageId(packageId)) {
    problems.push("the package is unknown");
  }
  if (values.element.length === 0) {
    problems.push("name the element or area");
  } else if (values.element.length > LIMITS.element) {
    problems.push(`keep the element or area under ${LIMITS.element} characters`);
  }
  if (values.source.length === 0) {
    problems.push("choose the source used");
  } else if (values.source.length > LIMITS.sourceKey) {
    problems.push("the source is not one of the package's");
  }
  if (values.decision.length === 0) {
    problems.push("describe the decision");
  } else if (values.decision.length > LIMITS.decision) {
    problems.push(`keep the decision under ${LIMITS.decision} characters`);
  }
  if (values.note.length > LIMITS.note) {
    problems.push(`keep the uncertainty and next check under ${LIMITS.note} characters`);
  }
  if (problems.length > 0) {
    const message = problems.join("; ");
    return { ok: false, message: message.charAt(0).toUpperCase() + message.slice(1) + ".", values };
  }
  return {
    ok: true,
    packageId,
    sourceKey: values.source,
    element: values.element,
    decision: values.decision,
    ...(values.note.length > 0 ? { note: values.note } : {}),
  };
}

// ---------------------------------------------------------------------------------------------
// Source options

export interface SourceOption {
  /** The key posted by the form. */
  readonly value: string;
  readonly label: string;
}

export interface SourceGroup {
  readonly label: string;
  readonly options: readonly SourceOption[];
}

/** What a key stands for: the sources sent to the station and the capture they concern. */
export interface ResolvedSource {
  readonly sources: DecisionSource[];
  readonly captureId?: string;
  readonly areaKey?: string;
}

interface Built {
  readonly groups: SourceGroup[];
  readonly resolve: Map<string, ResolvedSource>;
}

/** Roles offered as "Plans and models" sources, in the order they are listed. */
const MODEL_ROLES: readonly PackageFile["role"][] = [
  "plan_dxf",
  "rooms_csv",
  "plan_pdf",
  "plan_png",
  "plan_svg",
  "mesh_glb",
  "mesh_obj",
  "point_cloud_las",
  "capture_model",
];

type ControlName = { readonly id: string; readonly captureId?: string; readonly areaKey?: string };

/** Every control of a field-controls document with its option text and short name. */
function controlEntries(
  controls: FieldControls,
  labelPrefix: (captureId: string, areaKey: string) => string,
): (ControlName & { option: string; short: string; kind: "distance" | "ceiling" | "other" })[] {
  return [
    ...controls.distances.map((item) => ({
      id: item.id,
      captureId: item.capture.captureId,
      areaKey: item.capture.areaKey,
      kind: "distance" as const,
      short: `Distance ${item.axis} (${item.measurement.method})`,
      option: `${labelPrefix(item.capture.captureId, item.capture.areaKey)}Distance ${item.axis} (${item.measurement.method}) · ${item.from} to ${item.to}`,
    })),
    ...controls.ceilingHeights.map((item) => ({
      id: item.id,
      captureId: item.capture.captureId,
      areaKey: item.capture.areaKey,
      kind: "ceiling" as const,
      short: `${item.room} ceiling height (${item.measurement.method})`,
      option: `${labelPrefix(item.capture.captureId, item.capture.areaKey)}${item.room} ceiling height (${item.measurement.method})`,
    })),
    ...controls.openings.map((item) => ({
      id: item.id,
      captureId: item.capture.captureId,
      areaKey: item.capture.areaKey,
      kind: "other" as const,
      short: `${item.room} ${item.label} (${item.width.method})`,
      option: `${labelPrefix(item.capture.captureId, item.capture.areaKey)}${item.room} ${item.label} (${item.width.method})`,
    })),
    ...controls.floorToFloor.map((item) => ({
      id: item.id,
      kind: "other" as const,
      short: `Floor to floor (${item.measurement.method})`,
      option: `Floor to floor (${item.measurement.method}) · ${item.location}`,
    })),
    ...controls.landmarks.map((item) => ({
      id: item.id,
      kind: "other" as const,
      short: `Landmark ${item.label}`,
      option: `Landmark · ${item.label}`,
    })),
  ];
}

function buildSources(pkg: StationPackage): Built {
  const record = pkg.captureRecord;
  const verified = pkg.files.filter((file) => file.status === "verified");
  const order = new Map(
    (record?.captures ?? pkg.captures).map((capture, index) => [capture.captureId, index]),
  );
  const rank = (file: PackageFile) =>
    file.captureId === undefined ? -1 : (order.get(file.captureId) ?? Number.MAX_SAFE_INTEGER);
  const sorted = [...verified].sort((a, b) => rank(a) - rank(b));
  const multi = (record?.captures.length ?? pkg.captures.length) > 1;
  const label = (captureId: string, areaKey: string) =>
    captureLabel(record, captureId, areaKey) ?? areaKey;
  const resolve = new Map<string, ResolvedSource>();
  const groups: SourceGroup[] = [];
  const capture = (file: PackageFile) =>
    file.captureId === undefined || file.areaKey === undefined
      ? {}
      : { captureId: file.captureId, areaKey: file.areaKey };

  const models: SourceOption[] = [];
  const modelFiles = sorted
    .filter((item) => MODEL_ROLES.includes(item.role))
    .sort((a, b) => rank(a) - rank(b) || MODEL_ROLES.indexOf(a.role) - MODEL_ROLES.indexOf(b.role));
  for (const file of modelFiles) {
    const value = `file:${file.path}`;
    models.push({
      value,
      label: fileDisplayName(file.path, record, file.captureId, file.areaKey),
    });
    resolve.set(value, { sources: [{ path: file.path }], ...capture(file) });
  }
  if (models.length > 0) {
    groups.push({ label: "Plans and models", options: models });
  }

  const controlsFile = verified.find((file) => file.role === "field_controls");
  const controls =
    controlsFile !== undefined && pkg.fieldControls !== undefined
      ? controlEntries(pkg.fieldControls, (captureId, areaKey) =>
          multi ? `${label(captureId, areaKey)} · ` : "",
        )
      : [];

  if (controlsFile !== undefined) {
    const checked: SourceOption[] = [];
    for (const dxf of sorted.filter((file) => file.role === "plan_dxf")) {
      for (const control of controls.filter(
        (item) => item.kind !== "other" && item.captureId === dxf.captureId,
      )) {
        const value = `filectl:${dxf.path}|${control.id}`;
        checked.push({
          value,
          label: `${fileDisplayName(dxf.path, record, dxf.captureId, dxf.areaKey)} + ${control.short}`,
        });
        resolve.set(value, {
          sources: [{ path: dxf.path }, { path: controlsFile.path, controlId: control.id }],
          ...capture(dxf),
        });
      }
    }
    if (checked.length > 0) {
      groups.push({ label: "Plan checked against tape", options: checked });
    }

    const fieldOptions: SourceOption[] = [];
    for (const control of controls) {
      const value = `ctl:${control.id}`;
      fieldOptions.push({ value, label: control.option });
      resolve.set(value, {
        sources: [{ path: controlsFile.path, controlId: control.id }],
        ...(control.captureId === undefined || control.areaKey === undefined
          ? {}
          : { captureId: control.captureId, areaKey: control.areaKey }),
      });
    }
    if (fieldOptions.length > 0) {
      groups.push({ label: "Field controls", options: fieldOptions });
    }
  }

  const photoOptions: SourceOption[] = [];
  const photoCaptures = [
    ...new Set(sorted.filter((file) => file.role === "photo").map((file) => file.captureId)),
  ];
  for (const captureId of photoCaptures) {
    if (captureId === undefined) {
      continue;
    }
    const photos = sorted.filter((file) => file.role === "photo" && file.captureId === captureId);
    const areaKey = photos[0]?.areaKey ?? "";
    const value = `photos:${captureId}`;
    photoOptions.push({
      value,
      label: `${label(captureId, areaKey)} / site photos (${photos.length})`,
    });
    resolve.set(value, {
      sources: photos.map((photo) => ({ path: photo.path })),
      captureId,
      areaKey,
    });
  }
  if (photoOptions.length > 0) {
    groups.push({ label: "Site photos", options: photoOptions });
  }
  return { groups, resolve };
}

/** The "Source used" option groups of a package. */
export function sourceGroups(pkg: StationPackage): SourceGroup[] {
  return buildSources(pkg).groups;
}

/** What a posted key stands for in this package; undefined for an unknown key. */
export function resolveSource(pkg: StationPackage, key: string): ResolvedSource | undefined {
  return buildSources(pkg).resolve.get(key);
}

/** The station input of a parsed form whose key resolved. */
export function decisionInput(
  parsed: Extract<ParsedDecision, { ok: true }>,
  resolved: ResolvedSource,
): ModelingDecisionInput {
  return {
    element: parsed.element,
    decision: parsed.decision,
    ...(resolved.captureId === undefined || resolved.areaKey === undefined
      ? {}
      : { captureId: resolved.captureId, areaKey: resolved.areaKey }),
    sources: resolved.sources,
    ...(parsed.note === undefined ? {} : { note: parsed.note }),
  };
}

// ---------------------------------------------------------------------------------------------
// Entries

/** What is known about a decision's package to word its sources. */
export interface DecisionContext {
  readonly files: readonly PackageFile[];
  readonly captureRecord?: CaptureRecord;
  readonly fieldControls?: FieldControls;
}

const PHOTO_PATH = /^Site Photos\//;

/**
 * The sources of a logged decision as one text: files by display name, field controls by short
 * name ("Distance A (tape)"), photos of one capture as "{label} / site photos ({k})", joined
 * " + ".
 */
export function sourceText(
  decision: Pick<ModelingDecision, "sources">,
  context: DecisionContext | undefined,
): string {
  const files = context?.files ?? [];
  const record = context?.captureRecord;
  const controls =
    context?.fieldControls === undefined
      ? new Map<string, string>()
      : new Map(
          controlEntries(context.fieldControls, () => "").map((item) => [item.id, item.short]),
        );
  const parts: string[] = [];
  const photoGroups = new Map<string, number>();
  for (const source of decision.sources) {
    if (source.controlId !== undefined) {
      parts.push(controls.get(source.controlId) ?? `field-controls.json (${source.controlId})`);
      continue;
    }
    if (PHOTO_PATH.test(source.path)) {
      const name = pathDisplayName(source.path, files, record);
      const label = name.includes(" / ") ? name.slice(0, name.lastIndexOf(" / ")) : "";
      const key = `${label} / site photos`;
      if (!photoGroups.has(key)) {
        parts.push(key);
      }
      photoGroups.set(key, (photoGroups.get(key) ?? 0) + 1);
      continue;
    }
    const name = pathDisplayName(source.path, files, record);
    parts.push(source.elementId === undefined ? name : `${name} (${source.elementId})`);
  }
  return parts
    .map((part) => {
      const count = photoGroups.get(part);
      if (count === undefined) {
        return part;
      }
      return part.startsWith(" / ") ? `site photos (${count})` : `${part} (${count})`;
    })
    .join(" + ");
}

// Shared, memoized view of one package for the checks. Pure: everything comes from the
// LoadedPackage in memory.

import type { CaptureModel, FileEntry, Role } from "@chapter/capture-contract";
import type { ParseResult } from "./parsers/common.js";
import { parseByRole, type ParsedFile } from "./parsers/index.js";
import type { LoadedPackage } from "./types.js";

export interface CaptureInfo {
  captureId: string;
  areaKey: string;
  /** Floor or area label shown to people, for example Floor 1. */
  label: string;
}

/** Model of a capture: absent (no capture_model file), unreadable (check 2 reports it) or read. */
export type ModelLookup =
  | { state: "absent" }
  | { state: "unreadable"; entry: FileEntry }
  | { state: "ok"; entry: FileEntry; model: CaptureModel };

export class CheckContext {
  private readonly parseCache = new Map<string, ParseResult<ParsedFile> | undefined>();
  private readonly memo = new Map<string, unknown>();

  constructor(
    readonly pkg: LoadedPackage,
    readonly hubAddress: string,
  ) {}

  get manifestPath(): string {
    return this.pkg.manifestPath;
  }

  get entries(): readonly FileEntry[] {
    return this.pkg.manifest.files;
  }

  bytes(path: string): Uint8Array | undefined {
    return this.pkg.files.get(path);
  }

  /** True when the manifest lists the path. */
  listed(path: string): boolean {
    return this.entries.some((entry) => entry.path === path);
  }

  /**
   * Parse result of a listed file by its role. Undefined when the file is missing or empty
   * (checks 1 and 2 report those).
   */
  parsed(entry: FileEntry): ParseResult<ParsedFile> | undefined {
    if (this.parseCache.has(entry.path)) {
      return this.parseCache.get(entry.path);
    }
    const bytes = this.bytes(entry.path);
    const result =
      bytes === undefined || bytes.length === 0 ? undefined : parseByRole(entry.role, bytes);
    this.parseCache.set(entry.path, result);
    return result;
  }

  /** Parsed value of a listed file when it read successfully. */
  readable(entry: FileEntry): ParsedFile | undefined {
    const result = this.parsed(entry);
    return result?.ok === true ? result.value : undefined;
  }

  /** Memoizes a derived analysis shared between checks. */
  shared<T>(key: string, compute: () => T): T {
    if (!this.memo.has(key)) {
      this.memo.set(key, compute());
    }
    return this.memo.get(key) as T;
  }

  /** Captures of the visit: from the capture record, else from the manifest entries. */
  captures(): CaptureInfo[] {
    return this.shared("captures", () => {
      const record = this.pkg.captureRecord;
      if (record !== undefined) {
        return record.captures.map((capture) => ({
          captureId: capture.captureId,
          areaKey: capture.areaKey,
          label: capture.label,
        }));
      }
      const seen = new Map<string, CaptureInfo>();
      for (const entry of this.entries) {
        if (entry.captureId !== undefined && !seen.has(entry.captureId)) {
          seen.set(entry.captureId, {
            captureId: entry.captureId,
            areaKey: entry.areaKey ?? "unknown",
            label: entry.areaKey ?? entry.captureId,
          });
        }
      }
      return [...seen.values()];
    });
  }

  label(captureId: string): string {
    return this.captures().find((capture) => capture.captureId === captureId)?.label ?? captureId;
  }

  entriesFor(captureId: string, role: Role): FileEntry[] {
    return this.entries.filter((entry) => entry.captureId === captureId && entry.role === role);
  }

  firstOfRole(role: Role): FileEntry | undefined {
    return this.entries.find((entry) => entry.role === role);
  }

  /** Path of the capture record, or the manifest when there is none. */
  recordPath(): string {
    return this.firstOfRole("capture_record")?.path ?? this.manifestPath;
  }

  /** Path of the field controls, or the manifest when there are none. */
  controlsPath(): string {
    return this.firstOfRole("field_controls")?.path ?? this.manifestPath;
  }

  model(captureId: string): ModelLookup {
    const entry = this.entriesFor(captureId, "capture_model")[0];
    if (entry === undefined) {
      return { state: "absent" };
    }
    const parsed = this.readable(entry);
    if (parsed?.kind !== "capture_model") {
      return { state: "unreadable", entry };
    }
    return { state: "ok", entry, model: parsed.value };
  }

  /** Best file to name for a finding about one capture: its capture model, else the record. */
  capturePath(captureId: string): string {
    return this.entriesFor(captureId, "capture_model")[0]?.path ?? this.recordPath();
  }
}

/**
 * Resolves a relative reference (glTF uri, mtllib, map_Kd) against the folder of the file that
 * holds it. Returns the package path, or undefined when the reference is absolute, a URL or
 * leaves the package root.
 */
export function resolveRelative(fromFile: string, reference: string): string | undefined {
  const cleaned = reference.replace(/\\/g, "/");
  if (cleaned.length === 0 || cleaned.startsWith("/") || /^[a-z][a-z0-9+.-]*:/i.test(cleaned)) {
    return undefined;
  }
  const parts = fromFile.split("/").slice(0, -1);
  for (const segment of cleaned.split("/")) {
    if (segment === "" || segment === ".") {
      continue;
    }
    if (segment === "..") {
      if (parts.length === 0) {
        return undefined;
      }
      parts.pop();
      continue;
    }
    parts.push(segment);
  }
  return parts.length === 0 ? undefined : parts.join("/");
}

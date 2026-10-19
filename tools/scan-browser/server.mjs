#!/usr/bin/env node
// Scan browser: a small local web app for field testing. It lists the visits the Chapter Capture
// field-test build wrote on the iPhone and shows every file of every scan: raw originals, the
// latest "Package ready" exports, photos, field controls, the source register, sealed packages
// and their upload state. "Sync from iPhone" copies the visits off a connected phone.
//
// Testing tool only. Node built-ins only, no build step. It binds 127.0.0.1, answers only requests
// addressed to 127.0.0.1 or localhost, and serves files only from inside the data folder.
//
// Usage: node tools/scan-browser/server.mjs [--data <dir>] [--port <port>]
//   (or: npm run scan-browser -- --data <dir>). See README.md.

import { execFile } from "node:child_process";
import { createHash, randomBytes } from "node:crypto";
import { createReadStream, existsSync } from "node:fs";
import * as fsp from "node:fs/promises";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { parseArgs } from "node:util";

const TOOL_DIR = path.dirname(fileURLToPath(import.meta.url));
const PUBLIC_DIR = path.join(TOOL_DIR, "public");
const REPO_ROOT = path.resolve(TOOL_DIR, "..", "..");

export const BUNDLE_ID = "com.hellochapter.capture";
export const REMOTE_ROOT = "Library/Application Support/FieldTestVisits";
const DEFAULT_PORT = 4321;
const TEXT_PREVIEW_BYTES = 64 * 1024;
const CSV_PREVIEW_BYTES = 2 * 1024 * 1024;
const JSON_TREE_MAX_BYTES = 32 * 1024 * 1024;
const BINARY_SUMMARY_MAX_BYTES = 1024 * 1024 * 1024;
const FT2_PER_M2 = 10.7639104;
const VISIT_PARTS = ["originals", "photos", "controls", "drafts", "packages"];
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const PHOTO_WIDTHS = [320, 480, 1024, 1600, 2400];
const SYNC_CONCURRENCY = 4;
const IGNORED_NAMES = new Set([".DS_Store"]);
const collator = new Intl.Collator("en", { numeric: true, sensitivity: "base" });

/** Real path of the data folder; every served file must be strictly inside it. Set by main(). */
let DATA = "";
/** Folder of converted photos (outside the data folder, so test data is never written to). */
let CACHE = "";
let PORT = DEFAULT_PORT;

// ---------------------------------------------------------------------------------------------
// Configuration

function usage() {
  return [
    "Usage: node tools/scan-browser/server.mjs [--data <dir>] [--port <port>]",
    "",
    "  --data <dir>   Folder of copied visits (default ~/ChapterCaptureScans, or SCAN_BROWSER_DATA).",
    "                 Sync from iPhone copies FieldTestVisits into it as an incremental mirror.",
    `  --port <port>  Port on 127.0.0.1 (default ${DEFAULT_PORT}).`,
  ].join("\n");
}

function expandHome(p) {
  if (p === "~") return os.homedir();
  if (p.startsWith("~/")) return path.join(os.homedir(), p.slice(2));
  return p;
}

export function readConfig(argv, env) {
  const { values } = parseArgs({
    args: argv,
    options: {
      data: { type: "string" },
      port: { type: "string" },
      help: { type: "boolean", short: "h" },
    },
    strict: true,
  });
  const raw =
    values.data ?? env.SCAN_BROWSER_DATA ?? path.join(os.homedir(), "ChapterCaptureScans");
  const port = values.port === undefined ? DEFAULT_PORT : Number(values.port);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error(`--port must be a whole number from 1 to 65535 (got ${values.port}).`);
  }
  return { help: values.help === true, dataDir: path.resolve(expandHome(raw)), port };
}

function cacheRoot() {
  if (process.platform === "darwin") {
    return path.join(os.homedir(), "Library", "Caches", "ChapterScanBrowser");
  }
  return path.join(os.tmpdir(), `chapter-scan-browser-${process.getuid?.() ?? "user"}`);
}

// ---------------------------------------------------------------------------------------------
// HTTP helpers

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}
const fail = (status, message) => new HttpError(status, message);

const SECURITY_HEADERS = {
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "no-referrer",
  "Cross-Origin-Resource-Policy": "same-origin",
  "Cross-Origin-Opener-Policy": "same-origin",
  "Cache-Control": "no-store",
};

/** The page itself. The 3D viewer script is the only thing loaded from elsewhere. */
const PAGE_CSP = [
  "default-src 'self'",
  "script-src 'self' https://cdn.jsdelivr.net",
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data: blob:",
  "connect-src 'self' data: blob:",
  "worker-src 'self' blob:",
  "frame-src 'self'",
  "object-src 'none'",
  "base-uri 'none'",
  "form-action 'none'",
  "frame-ancestors 'none'",
].join("; ");

/** Files from the data folder: never run anything (an SVG opened directly cannot script). */
const FILE_CSP =
  "sandbox; default-src 'none'; img-src data:; style-src 'unsafe-inline'; frame-ancestors 'self'";
/** PDFs: the browser's PDF viewer does not work under a sandbox CSP; only framing is limited. */
const PDF_CSP = "frame-ancestors 'self'";

function send(res, status, body, headers = {}) {
  res.writeHead(status, { ...SECURITY_HEADERS, ...headers });
  res.end(res.req.method === "HEAD" ? undefined : body);
}

function sendJson(res, status, value) {
  send(res, status, JSON.stringify(value), { "Content-Type": "application/json; charset=utf-8" });
}

function contentDisposition(kind, name) {
  const ascii = name.replace(/[^\x20-\x7e]/g, "_").replace(/["\\]/g, "_");
  return `${kind}; filename="${ascii}"; filename*=UTF-8''${encodeURIComponent(name)}`;
}

// ---------------------------------------------------------------------------------------------
// Paths: everything served must resolve (after symlinks) to a path strictly inside DATA.

function isInsideData(p) {
  return p.startsWith(DATA + path.sep);
}

/** Splits a data-relative path ("visit/originals/...") into safe segments, or throws 400. */
export function safeSegments(rel) {
  if (typeof rel !== "string" || rel.length === 0 || rel.length > 4096) {
    throw fail(400, "Missing or invalid path.");
  }
  if (rel.includes("\0") || rel.includes("\\")) throw fail(400, "Invalid character in path.");
  if (rel.startsWith("/") || /^[a-zA-Z]:/.test(rel)) {
    throw fail(400, "Absolute paths are not allowed.");
  }
  const segments = rel.split("/");
  for (const segment of segments) {
    if (segment === "" || segment === "." || segment === "..") {
      throw fail(400, "Invalid path segment.");
    }
  }
  return segments;
}

/** Resolves a data-relative path to an existing file or folder strictly inside DATA. */
async function resolveDataPath(rel, want) {
  const joined = path.resolve(DATA, ...safeSegments(rel));
  if (!isInsideData(joined)) throw fail(403, "Path is outside the data folder.");
  let real;
  try {
    real = await fsp.realpath(joined);
  } catch {
    throw fail(404, "Not found.");
  }
  if (!isInsideData(real)) throw fail(403, "Path is outside the data folder.");
  const stat = await fsp.stat(real);
  if (want === "file" && !stat.isFile()) throw fail(404, "Not a file.");
  if (want === "dir" && !stat.isDirectory()) throw fail(404, "Not a folder.");
  return { abs: real, stat, name: rel.split("/").at(-1) };
}

async function readdirSafe(dir) {
  try {
    return await fsp.readdir(dir, { withFileTypes: true });
  } catch {
    return [];
  }
}

/** Every regular file under root (symlinks are listed, never followed). */
async function walkFiles(root) {
  const files = [];
  const symlinks = [];
  async function visit(dir, parts, depth) {
    if (depth > 16 || files.length > 100000) return;
    const entries = (await readdirSafe(dir)).sort((a, b) => collator.compare(a.name, b.name));
    for (const entry of entries) {
      if (IGNORED_NAMES.has(entry.name) || /^\..+\.partial-[0-9a-f]+$/.test(entry.name)) continue;
      const abs = path.join(dir, entry.name);
      const rel = [...parts, entry.name];
      if (entry.isSymbolicLink()) {
        symlinks.push(rel);
      } else if (entry.isDirectory()) {
        await visit(abs, rel, depth + 1);
      } else if (entry.isFile()) {
        try {
          const st = await fsp.stat(abs);
          files.push({ parts: rel, size: st.size, mtimeMs: st.mtimeMs });
        } catch {
          // Vanished while listing.
        }
      }
    }
  }
  await visit(root, [], 0);
  return { files, symlinks };
}

async function readHead(abs, length) {
  const handle = await fsp.open(abs, "r");
  try {
    const buffer = Buffer.alloc(length);
    const { bytesRead } = await handle.read(buffer, 0, length, 0);
    return buffer.subarray(0, bytesRead);
  } finally {
    await handle.close();
  }
}

async function readJson(abs, maxBytes = 8 * 1024 * 1024) {
  try {
    const st = await fsp.stat(abs);
    if (st.size > maxBytes) return { error: "too large" };
    return { value: JSON.parse(await fsp.readFile(abs, "utf8")) };
  } catch (err) {
    return { error: err.message };
  }
}

// ---------------------------------------------------------------------------------------------
// Visits: discovery, classification by the VisitWorkspace layout, summaries.

export function previewKind(name) {
  const lower = name.toLowerCase();
  if (lower === "depth-samples.bin") return "depth";
  if (lower === "mesh-anchors.bin") return "mesh-anchors";
  if (lower === "camera-poses.json") return "camera-poses";
  if (lower.endsWith(".upload-state.json")) return "upload-state";
  const ext = path.extname(lower);
  if (ext === ".pdf") return "pdf";
  if ([".png", ".jpg", ".jpeg", ".gif", ".webp"].includes(ext)) return "image";
  if (ext === ".svg") return "svg";
  if (ext === ".heic" || ext === ".heif") return "heic";
  if (ext === ".json") return "json";
  if (ext === ".csv") return "csv";
  if (ext === ".glb") return "glb";
  if (ext === ".las") return "las";
  if ([".obj", ".mtl", ".dxf", ".txt", ".log", ".md", ".xml", ".usda"].includes(ext)) return "text";
  return "binary";
}

async function isVisitDir(abs, name) {
  if (UUID_RE.test(name)) return true;
  const children = await readdirSafe(abs);
  return children.some((c) => c.isDirectory() && VISIT_PARTS.includes(c.name));
}

/** Visit folders directly in DATA, or one level down (a dated snapshot or a FieldTestVisits copy). */
async function findVisits() {
  const visits = [];
  const others = [];
  for (const entry of await readdirSafe(DATA)) {
    if (entry.name.startsWith(".") || IGNORED_NAMES.has(entry.name)) continue;
    // A visit's own folders (the data folder is a single visit) are not visit containers.
    if (!entry.isDirectory() || VISIT_PARTS.includes(entry.name)) {
      others.push(entry.name);
      continue;
    }
    const abs = path.join(DATA, entry.name);
    if (await isVisitDir(abs, entry.name)) {
      visits.push(entry.name);
      continue;
    }
    let found = false;
    for (const child of await readdirSafe(abs)) {
      if (child.name.startsWith(".") || !child.isDirectory()) continue;
      if (await isVisitDir(path.join(abs, child.name), child.name)) {
        visits.push(`${entry.name}/${child.name}`);
        found = true;
      }
    }
    if (!found) others.push(entry.name);
  }
  return { visits, others };
}

const iso = (ms) => (Number.isFinite(ms) ? new Date(ms).toISOString() : null);

function fileInfo(visitRel, f, extra = {}) {
  const name = f.parts.at(-1);
  return {
    name,
    path: `${visitRel}/${f.parts.join("/")}`,
    size: f.size,
    mtime: iso(f.mtimeMs),
    mtimeMs: Math.round(f.mtimeMs),
    kind: previewKind(name),
    ...extra,
  };
}

const newest = (files) => files.reduce((m, f) => Math.max(m, f.mtimeMs), 0);

function summarizeUploadState(value) {
  const files = Array.isArray(value?.files) ? value.files : [];
  const phases = {};
  let rejected = 0;
  for (const f of files) {
    const phase = typeof f?.phase === "string" ? f.phase : "unknown";
    phases[phase] = (phases[phase] ?? 0) + 1;
    rejected += Number.isFinite(f?.rejectedUploads) ? f.rejectedUploads : 0;
  }
  const verified = phases.verified ?? 0;
  const sealStatus = typeof value?.sealResult?.status === "string" ? value.sealResult.status : null;
  return {
    packageId: value?.packageId ?? null,
    dealId: value?.dealId ?? null,
    files: files.length,
    phases,
    verified,
    rejected,
    sealStatus,
    confirmed:
      files.length > 0 && verified === files.length && !!sealStatus && sealStatus !== "uploading",
  };
}

function summarizeManifest(value) {
  const files = Array.isArray(value?.files) ? value.files : [];
  const roles = {};
  let bytes = 0;
  for (const f of files) {
    const role = typeof f?.role === "string" ? f.role : "unknown";
    roles[role] = roles[role] ?? { files: 0, bytes: 0 };
    roles[role].files += 1;
    roles[role].bytes += Number.isFinite(f?.bytes) ? f.bytes : 0;
    bytes += Number.isFinite(f?.bytes) ? f.bytes : 0;
  }
  return {
    packageId: value?.packageId ?? null,
    visitId: value?.visitId ?? null,
    revision: value?.revision ?? null,
    sealedAt: value?.sealedAt ?? null,
    files: files.length,
    bytes,
    roles,
  };
}

/** Walks one visit folder and sorts every file into the VisitWorkspace layout. */
async function analyzeVisit(visitRel) {
  const { abs } = await resolveDataPath(visitRel, "dir");
  const { files, symlinks } = await walkFiles(abs);
  const captures = new Map();
  const capture = (areaKey, captureId) => {
    const key = `${areaKey}/${captureId}`;
    if (!captures.has(key)) {
      captures.set(key, { key, areaKey, captureId, raw: [], photoFiles: [], drafts: new Map() });
    }
    return captures.get(key);
  };
  const drafts = new Map();
  const draft = (id) => {
    if (!drafts.has(id)) {
      drafts.set(id, { id, files: [], register: [], other: [], recordFile: null });
    }
    return drafts.get(id);
  };
  const packages = new Map();
  const pkg = (id) => {
    if (!packages.has(id)) {
      packages.set(id, { id, files: [], uploadState: null, recordFile: null, manifestFile: null });
    }
    return packages.get(id);
  };
  const controls = [];
  const other = [];
  let photoRecordsFile = null;

  for (const f of files) {
    const p = f.parts;
    const n = p.length;
    if (p[0] === "originals" && p[1] === "Original Exports" && n === 5) {
      capture(p[2], p[3]).raw.push(f);
    } else if (p[0] === "photos" && n === 2 && p[1] === "photo-records.json") {
      photoRecordsFile = f;
    } else if (p[0] === "photos" && p[1] === "Site Photos" && n === 5) {
      capture(p[2], p[3]).photoFiles.push(f);
    } else if (p[0] === "controls" && p[1] === "Field Measurements" && n === 4) {
      controls.push(f);
    } else if (p[0] === "drafts" && n >= 3) {
      const d = draft(p[1]);
      d.files.push(f);
      if (p[2] === "Original Exports" && n === 6) {
        const c = capture(p[3], p[4]);
        if (!c.drafts.has(d.id)) c.drafts.set(d.id, []);
        c.drafts.get(d.id).push(f);
      } else if (p[2] === "Source Register" && n === 5) {
        d.register.push(f);
        if (p[4] === "capture-record.json") d.recordFile = f;
      } else {
        d.other.push(f);
      }
    } else if (p[0] === "packages" && n === 2 && p[1].endsWith(".upload-state.json")) {
      pkg(p[1].slice(0, -".upload-state.json".length)).uploadState = f;
    } else if (p[0] === "packages" && n >= 3) {
      const k = pkg(p[1]);
      k.files.push(f);
      if (p[2] === "Source Register" && n === 5 && p[4] === "capture-record.json") k.recordFile = f;
      if (p[2] === "Source Register" && n === 5 && p[4] === "manifest.json") k.manifestFile = f;
    } else {
      other.push(f);
    }
  }

  // A sealed package folder copied without its files (read-only on the phone) still counts.
  for (const entry of await readdirSafe(path.join(abs, "packages"))) {
    if (entry.isDirectory()) pkg(entry.name);
  }
  for (const d of drafts.values()) {
    d.builtMs = d.recordFile?.mtimeMs ?? newest(d.files);
  }
  const draftsByTime = [...drafts.values()].sort((a, b) => b.builtMs - a.builtMs);
  const latestDraft = draftsByTime[0] ?? null;

  // The newest capture record (drafts and sealed packages both carry one).
  const recordCandidates = [
    ...draftsByTime.filter((d) => d.recordFile).map((d) => d.recordFile),
    ...[...packages.values()].filter((k) => k.recordFile).map((k) => k.recordFile),
  ].sort((a, b) => b.mtimeMs - a.mtimeMs);
  let record = null;
  let recordPath = null;
  if (recordCandidates.length > 0) {
    const f = recordCandidates[0];
    const parsed = await readJson(path.join(abs, ...f.parts));
    if (parsed.value && typeof parsed.value === "object") {
      record = parsed.value;
      recordPath = `${visitRel}/${f.parts.join("/")}`;
    }
  }

  let photoRecords = [];
  if (photoRecordsFile) {
    const parsed = await readJson(path.join(abs, ...photoRecordsFile.parts));
    if (Array.isArray(parsed.value))
      photoRecords = parsed.value.filter((r) => r && typeof r === "object");
  }

  for (const k of packages.values()) {
    if (k.uploadState) {
      const parsed = await readJson(path.join(abs, ...k.uploadState.parts), 64 * 1024 * 1024);
      k.upload = parsed.value ? summarizeUploadState(parsed.value) : { error: parsed.error };
      k.uploadValue = parsed.value ?? null;
    }
    if (k.manifestFile) {
      const parsed = await readJson(path.join(abs, ...k.manifestFile.parts), 64 * 1024 * 1024);
      k.manifest = parsed.value ? summarizeManifest(parsed.value) : { error: parsed.error };
      k.manifestValue = parsed.value ?? null;
    }
  }

  return {
    visitRel,
    abs,
    files,
    symlinks,
    captures,
    drafts: draftsByTime,
    latestDraft,
    packages: [...packages.values()].sort((a, b) => newest(b.files) - newest(a.files)),
    controls,
    other,
    photoRecordsFile,
    photoRecords,
    record,
    recordPath,
  };
}

function recordCaptures(record) {
  return Array.isArray(record?.captures)
    ? record.captures.filter((c) => c && typeof c === "object")
    : [];
}

function summarizeVisit(a, dirMtimeMs) {
  const record = a.record;
  const captureList = [...a.captures.values()];
  const newestFile = newest(a.files);
  const visitedMs = Date.parse(record?.visitedAt ?? "");
  const dateMs = Number.isFinite(visitedMs) ? visitedMs : newestFile || dirMtimeMs;
  const areas = recordCaptures(record).map((c) => String(c.label ?? c.areaKey ?? ""));
  for (const c of captureList) {
    if (!recordCaptures(record).some((r) => r.captureId === c.captureId)) areas.push(c.areaKey);
  }
  const rawCaptures = captureList.filter((c) => c.raw.length > 0).length;
  const status = [];
  if (a.files.length === 0) status.push({ key: "empty", label: "empty" });
  if (rawCaptures > 0) {
    status.push({
      key: "scanned",
      label: rawCaptures > 1 ? `scanned (${rawCaptures} captures)` : "scanned",
    });
  }
  if (a.drafts.length > 0) {
    status.push({
      key: "built",
      label: a.drafts.length > 1 ? `package built ×${a.drafts.length}` : "package built",
    });
  }
  if (a.packages.length > 0) {
    status.push({
      key: "sealed",
      label: a.packages.length > 1 ? `sealed ×${a.packages.length}` : "sealed",
    });
  }
  for (const k of a.packages) {
    if (!k.upload) continue;
    if (k.upload.error) {
      status.push({ key: "upload-error", label: "upload state unreadable" });
      continue;
    }
    const station = k.upload.sealStatus ? `, station: ${k.upload.sealStatus}` : "";
    status.push({
      key: k.upload.confirmed ? "uploaded" : "upload",
      label: `upload ${k.upload.verified}/${k.upload.files} verified${station}`,
    });
  }
  const bytes = a.files.reduce((s, f) => s + f.size, 0);
  const photos = captureList.reduce((s, c) => s + c.photoFiles.length, 0);
  return {
    id: a.visitRel,
    folder: a.visitRel.split("/").at(-1),
    date: iso(dateMs),
    dateMs,
    dateSource: Number.isFinite(visitedMs)
      ? "visitedAt"
      : a.files.length
        ? "newest file"
        : "folder",
    visitId: record?.visitId ?? null,
    operator: record?.operator?.name ?? null,
    projectName: record?.hub?.projectName ?? null,
    dealId: record?.hub?.dealId ?? null,
    address: record?.address?.formatted ?? null,
    areas: [...new Set(areas.filter(Boolean))],
    counts: {
      files: a.files.length,
      bytes,
      captures: captureList.length,
      photos,
      drafts: a.drafts.length,
      packages: a.packages.length,
    },
    status,
  };
}

async function listVisits() {
  const { visits, others } = await findVisits();
  const out = [];
  for (const rel of visits) {
    try {
      const a = await analyzeVisit(rel);
      const st = await fsp.stat(a.abs);
      out.push(summarizeVisit(a, st.mtimeMs));
    } catch (err) {
      out.push({ id: rel, folder: rel, error: err.message, status: [], counts: {}, areas: [] });
    }
  }
  out.sort((x, y) => (y.dateMs ?? 0) - (x.dateMs ?? 0));
  return { dataDir: DATA, visits: out, others };
}

async function visitDetail(visitRel) {
  const a = await analyzeVisit(visitRel);
  const st = await fsp.stat(a.abs);
  const summary = summarizeVisit(a, st.mtimeMs);
  const info = (f, extra) => fileInfo(visitRel, f, extra);
  const recordCaps = recordCaptures(a.record);
  const order = (c) => {
    const i = recordCaps.findIndex((r) => r.captureId === c.captureId);
    return i < 0 ? recordCaps.length : i;
  };
  const captureList = [...a.captures.values()].sort(
    (x, y) => order(x) - order(y) || collator.compare(x.key, y.key),
  );
  const photoRoot = (f) => f.parts.slice(1).join("/");

  const captures = captureList.map((c) => {
    const rec = recordCaps.find((r) => r.captureId === c.captureId) ?? null;
    const exportsList = a.drafts
      .filter((d) => c.drafts.has(d.id))
      .map((d) => ({
        draftId: d.id,
        builtAt: iso(d.builtMs),
        latest: d === a.latestDraft,
        files: c.drafts.get(d.id).map((f) => info(f)),
      }));
    const exports = exportsList[0] ?? null;
    let sketchPath = exports?.files.find((f) => f.name === "capture-model.json")?.path ?? null;
    if (!sketchPath) {
      for (const k of a.packages) {
        const f = k.files.find(
          (x) =>
            x.parts[2] === "Original Exports" &&
            x.parts[3] === c.areaKey &&
            x.parts[4] === c.captureId &&
            x.parts[5] === "capture-model.json",
        );
        if (f) {
          sketchPath = `${visitRel}/${f.parts.join("/")}`;
          break;
        }
      }
    }
    const photos = c.photoFiles.map((f) => {
      const r = a.photoRecords.find((x) => x.path === photoRoot(f)) ?? null;
      return { file: info(f), record: r, missing: false };
    });
    for (const r of a.photoRecords) {
      if (r.captureId !== c.captureId) continue;
      if (photos.some((p) => p.record === r)) continue;
      photos.push({ file: null, record: r, missing: true });
    }
    photos.sort((x, y) => (x.record?.sequence ?? 1e9) - (y.record?.sequence ?? 1e9));
    return {
      key: c.key,
      areaKey: c.areaKey,
      captureId: c.captureId,
      label: rec?.label ?? null,
      mode: rec?.mode ?? null,
      capturedAt: rec?.capturedAt ?? null,
      finishedAt: rec?.finishedAt ?? null,
      inRecord: !!rec,
      raw: c.raw.map((f) => info(f)),
      exports,
      olderExports: exportsList.slice(1),
      photos,
      sketchPath,
    };
  });

  const packages = a.packages.map((k) => {
    const manifestFiles = Array.isArray(k.manifestValue?.files) ? k.manifestValue.files : [];
    const uploadFiles = Array.isArray(k.uploadValue?.files) ? k.uploadValue.files : [];
    const listed = new Set();
    const files = k.files.map((f) => {
      const inPackage = f.parts.slice(2).join("/");
      const entry = manifestFiles.find((m) => m?.path === inPackage);
      const upload = uploadFiles.find((u) => u?.path === inPackage);
      if (entry) listed.add(inPackage);
      const isManifest = f === k.manifestFile;
      return info(f, {
        inPackage,
        group: f.parts[2],
        role: entry?.role ?? (isManifest ? "(manifest)" : null),
        phase: upload?.phase ?? null,
        sizeMatches: entry ? entry.bytes === f.size : null,
      });
    });
    const missing = manifestFiles
      .filter((m) => typeof m?.path === "string" && !listed.has(m.path))
      .map((m) => m.path);
    return {
      id: k.id,
      files,
      missing,
      uploadState: k.uploadState ? info(k.uploadState) : null,
      upload: k.upload ?? null,
      manifest: k.manifest ?? null,
    };
  });

  const latest = a.latestDraft;
  return {
    summary,
    record: a.record,
    recordPath: a.recordPath,
    captures,
    drafts: a.drafts.map((d) => ({
      id: d.id,
      builtAt: iso(d.builtMs),
      files: d.files.length,
      bytes: d.files.reduce((s, f) => s + f.size, 0),
      latest: d === latest,
    })),
    register: latest ? { draftId: latest.id, files: latest.register.map((f) => info(f)) } : null,
    olderRegisters: a.drafts.slice(1).map((d) => ({
      draftId: d.id,
      builtAt: iso(d.builtMs),
      files: d.register.map((f) => info(f)),
    })),
    draftOther: a.drafts.flatMap((d) => d.other.map((f) => info(f))),
    controls: a.controls.map((f) => info(f)),
    photoRecords: a.photoRecordsFile
      ? info(a.photoRecordsFile, { count: a.photoRecords.length })
      : null,
    packages,
    other: a.other.map((f) => info(f)),
    symlinks: a.symlinks.map((parts) => `${visitRel}/${parts.join("/")}`),
  };
}

// ---------------------------------------------------------------------------------------------
// Previews. Each returns { kind, facts?, problems?, notes?, table?, json?, text?, truncated? }.

const fmtNum = (n, digits = 3) => (Number.isFinite(n) ? String(Number(n.toFixed(digits))) : "—");
const fmtInt = (n) => (Number.isFinite(n) ? n.toLocaleString("en-US") : "—");
const fmtVec = (v, digits = 3) => `(${v.map((x) => fmtNum(x, digits)).join(", ")})`;
function fmtBytes(n) {
  if (!Number.isFinite(n)) return "—";
  const units = ["B", "KB", "MB", "GB"];
  let v = n;
  let i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i += 1;
  }
  return i === 0 ? `${v} B` : `${v.toFixed(v < 10 ? 2 : 1)} ${units[i]}`;
}

function newPreview(kind) {
  return { kind, facts: [], problems: [], notes: [] };
}

function looksBinary(buffer) {
  return buffer.subarray(0, 8192).includes(0);
}

function hexDump(buffer) {
  const lines = [];
  for (let off = 0; off < buffer.length; off += 16) {
    const row = buffer.subarray(off, off + 16);
    const hex = [...row].map((b) => b.toString(16).padStart(2, "0")).join(" ");
    const ascii = [...row].map((b) => (b >= 32 && b < 127 ? String.fromCharCode(b) : ".")).join("");
    lines.push(`${off.toString(16).padStart(8, "0")}  ${hex.padEnd(47)}  ${ascii}`);
  }
  return lines.join("\n");
}

async function textPreview(abs, stat) {
  const head = await readHead(abs, TEXT_PREVIEW_BYTES);
  if (looksBinary(head)) return binaryPreview(abs, stat);
  const out = newPreview("text");
  out.text = new TextDecoder("utf-8", { fatal: false }).decode(head);
  out.truncated = stat.size > head.length;
  if (out.truncated) {
    out.notes.push(
      `Showing the first ${fmtBytes(head.length)} of ${fmtBytes(stat.size)}; Download has the whole file.`,
    );
  }
  return out;
}

async function binaryPreview(abs, stat) {
  const head = await readHead(abs, 256);
  const out = newPreview("text");
  out.facts.push(["Size", `${fmtBytes(stat.size)} (${fmtInt(stat.size)} bytes)`]);
  out.notes.push("Binary file; the first 256 bytes are shown as hex.");
  out.text = hexDump(head);
  return out;
}

export function parseCsv(text) {
  const rows = [];
  let row = [];
  let field = "";
  let quoted = false;
  for (let i = 0; i < text.length; i += 1) {
    const ch = text[i];
    if (quoted) {
      if (ch === '"' && text[i + 1] === '"') {
        field += '"';
        i += 1;
      } else if (ch === '"') {
        quoted = false;
      } else {
        field += ch;
      }
    } else if (ch === '"') {
      quoted = true;
    } else if (ch === ",") {
      row.push(field);
      field = "";
    } else if (ch === "\n" || ch === "\r") {
      if (ch === "\r" && text[i + 1] === "\n") i += 1;
      row.push(field);
      rows.push(row);
      row = [];
      field = "";
    } else {
      field += ch;
    }
  }
  if (field !== "" || row.length > 0) {
    row.push(field);
    rows.push(row);
  }
  return rows;
}

async function csvPreview(abs, stat) {
  const head = await readHead(abs, CSV_PREVIEW_BYTES);
  const out = newPreview("csv");
  const rows = parseCsv(new TextDecoder().decode(head)).filter(
    (r) => !(r.length === 1 && r[0] === ""),
  );
  const comments = rows.filter((r) => r.length === 1 && r[0].startsWith("#")).map((r) => r[0]);
  const data = rows.filter((r) => !(r.length === 1 && r[0].startsWith("#")));
  out.table = { columns: data[0] ?? [], rows: data.slice(1, 5001) };
  out.notes.push(...comments);
  if (data.length > 5001) out.notes.push(`Showing 5,000 of ${fmtInt(data.length - 1)} rows.`);
  if (stat.size > head.length) out.notes.push(`Only the first ${fmtBytes(head.length)} were read.`);
  out.facts.push(
    ["Rows", fmtInt(Math.max(0, data.length - 1))],
    ["Columns", fmtInt(out.table.columns.length)],
  );
  return out;
}

function redactUploadState(value) {
  if (Array.isArray(value)) return value.map(redactUploadState);
  if (value && typeof value === "object") {
    const out = {};
    for (const [key, v] of Object.entries(value)) {
      out[key] = key === "target" && v !== null ? "[hidden: upload target]" : redactUploadState(v);
    }
    return out;
  }
  return value;
}

function genericJsonFacts(value, out) {
  if (Array.isArray(value)) {
    out.facts.push(["Items", fmtInt(value.length)]);
    return;
  }
  if (!value || typeof value !== "object") return;
  for (const key of ["schemaVersion", "formatVersion", "visitId", "packageId"]) {
    if (typeof value[key] === "string" || typeof value[key] === "number")
      out.facts.push([key, String(value[key])]);
  }
  for (const [key, v] of Object.entries(value)) {
    if (Array.isArray(v))
      out.facts.push([key, `${fmtInt(v.length)} item${v.length === 1 ? "" : "s"}`]);
  }
}

function cameraPoseFacts(value, out) {
  const frames = Array.isArray(value?.frames) ? value.frames : [];
  const times = frames.map((f) => f?.timestamp).filter(Number.isFinite);
  const positions = frames
    .map((f) =>
      Array.isArray(f?.transform) && Array.isArray(f.transform[3])
        ? f.transform[3].slice(0, 3)
        : null,
    )
    .filter((p) => p && p.length === 3 && p.every(Number.isFinite));
  out.facts.push(
    ["Format version", String(value?.formatVersion ?? "—")],
    ["Frames", fmtInt(frames.length)],
  );
  if (times.length > 1) {
    const duration = Math.max(...times) - Math.min(...times);
    out.facts.push(["Duration", `${fmtNum(duration, 1)} s`]);
    if (duration > 0)
      out.facts.push(["Mean rate", `${fmtNum((times.length - 1) / duration, 2)} poses/s`]);
  }
  const k = value?.intrinsics;
  if (k && typeof k === "object") {
    out.facts.push([
      "Intrinsics",
      `fx ${fmtNum(k.fx, 1)}, fy ${fmtNum(k.fy, 1)}, cx ${fmtNum(k.cx, 1)}, cy ${fmtNum(k.cy, 1)}, ${k.imageWidth}×${k.imageHeight} px`,
    ]);
  } else {
    out.facts.push(["Intrinsics", "none recorded"]);
  }
  if (positions.length > 0) {
    let length = 0;
    for (let i = 1; i < positions.length; i += 1) {
      length += Math.hypot(...positions[i].map((v, j) => v - positions[i - 1][j]));
    }
    const min = [0, 1, 2].map((j) => Math.min(...positions.map((p) => p[j])));
    const max = [0, 1, 2].map((j) => Math.max(...positions.map((p) => p[j])));
    out.facts.push(
      ["Camera path length", `${fmtNum(length, 2)} m`],
      ["Camera bounds min", `${fmtVec(min, 2)} m`],
      ["Camera bounds max", `${fmtVec(max, 2)} m`],
      ["Camera height (y)", `${fmtNum(min[1], 2)} to ${fmtNum(max[1], 2)} m`],
    );
  }
  out.notes.push("Transforms are camera-to-world, four columns, capture frame (metres, +Y up).");
}

function uploadStateFacts(value, out) {
  const s = summarizeUploadState(value);
  out.facts.push(
    ["Format version", String(value?.formatVersion ?? "—")],
    ["Package", String(s.packageId ?? "—")],
    ["Deal", String(s.dealId ?? "—")],
    ["Files", fmtInt(s.files)],
    ["Verified", `${fmtInt(s.verified)} of ${fmtInt(s.files)}`],
    [
      "Phases",
      Object.entries(s.phases)
        .map(([k, v]) => `${k} ${v}`)
        .join(", ") || "—",
    ],
    ["Rejected uploads", fmtInt(s.rejected)],
    ["Station status", s.sealStatus ?? "not sealed with the station yet"],
    ["Confirmed by station", s.confirmed ? "yes" : "no"],
  );
}

function manifestFacts(value, out) {
  const s = summarizeManifest(value);
  out.facts.push(
    ["Package", String(s.packageId ?? "—")],
    ["Visit", String(s.visitId ?? "—")],
    ["Revision", String(s.revision ?? "—")],
    ["Sealed at", String(s.sealedAt ?? "—")],
    ["Files", fmtInt(s.files)],
    ["Total size", fmtBytes(s.bytes)],
  );
  out.table = {
    columns: ["Role", "Files", "Bytes"],
    rows: Object.entries(s.roles).map(([role, r]) => [role, fmtInt(r.files), fmtBytes(r.bytes)]),
  };
}

function captureModelFacts(value, out) {
  const sketch = sketchFromModel(value);
  out.facts.push(
    ["Schema version", String(value?.schemaVersion ?? "—")],
    ["Label", String(value?.label ?? "—")],
    ["Rooms", fmtInt(sketch.totals.rooms)],
    [
      "Floor area",
      `${fmtNum(sketch.totals.areaM2, 2)} m² (${fmtNum(sketch.totals.areaFt2, 1)} ft²)`,
    ],
    ["Walls", fmtInt(sketch.totals.walls)],
    [
      "Doors / windows / openings",
      `${sketch.totals.doors} / ${sketch.totals.windows} / ${sketch.totals.openings}`,
    ],
    ["Objects", fmtInt(Array.isArray(value?.objects) ? value.objects.length : 0)],
  );
}

async function jsonPreview(abs, stat, name) {
  if (stat.size > JSON_TREE_MAX_BYTES) {
    const out = await textPreview(abs, stat);
    out.notes.unshift(`${fmtBytes(stat.size)} is too large for the tree view.`);
    return out;
  }
  const text = await fsp.readFile(abs, "utf8");
  let value;
  try {
    value = JSON.parse(text);
  } catch (err) {
    const out = newPreview("text");
    out.problems.push(`Not valid JSON: ${err.message}`);
    out.text = text.slice(0, TEXT_PREVIEW_BYTES);
    out.truncated = text.length > TEXT_PREVIEW_BYTES;
    return out;
  }
  const out = newPreview("json");
  if (name === "camera-poses.json") {
    cameraPoseFacts(value, out);
  } else if (name.endsWith(".upload-state.json")) {
    uploadStateFacts(value, out);
    value = redactUploadState(value);
    out.notes.push(
      "Upload targets (SAS URLs) are hidden in this view; Download has the file as it is.",
    );
  } else if (name === "manifest.json") {
    manifestFacts(value, out);
  } else if (name === "capture-model.json") {
    captureModelFacts(value, out);
  } else {
    genericJsonFacts(value, out);
  }
  out.json = value;
  return out;
}

function untilNul(text) {
  const end = text.indexOf("\0");
  return end < 0 ? text : text.slice(0, end);
}

/** LAS 1.x public header block (LAS 1.4 R15 layout). */
async function lasPreview(abs, stat) {
  const b = await readHead(abs, 4096);
  const out = newPreview("facts");
  if (b.length < 227 || b.toString("latin1", 0, 4) !== "LASF") {
    out.problems.push("Not a LAS file: no LASF signature or the header is too short.");
    out.facts.push(["Size", fmtBytes(stat.size)]);
    return out;
  }
  const cstr = (off, len) => untilNul(b.toString("latin1", off, off + len)).trim();
  const major = b.readUInt8(24);
  const minor = b.readUInt8(25);
  const day = b.readUInt16LE(90);
  const year = b.readUInt16LE(92);
  const headerSize = b.readUInt16LE(94);
  const pointOffset = b.readUInt32LE(96);
  const vlrCount = b.readUInt32LE(100);
  const formatByte = b.readUInt8(104);
  const pointFormat = formatByte & 0x3f;
  const recordLength = b.readUInt16LE(105);
  const legacyCount = b.readUInt32LE(107);
  const scale = [131, 139, 147].map((o) => b.readDoubleLE(o));
  const offset = [155, 163, 171].map((o) => b.readDoubleLE(o));
  const max = [179, 195, 211].map((o) => b.readDoubleLE(o));
  const min = [187, 203, 219].map((o) => b.readDoubleLE(o));
  let count = legacyCount;
  if (minor >= 4 && headerSize >= 375 && b.length >= 255) count = Number(b.readBigUInt64LE(247));
  const created =
    year > 0 && day > 0 ? new Date(Date.UTC(year, 0, day)).toISOString().slice(0, 10) : "—";
  out.facts.push(
    ["Version", `${major}.${minor}`],
    ["System identifier", cstr(26, 32) || "—"],
    ["Generating software", cstr(58, 32) || "—"],
    ["Created (header)", created],
    ["Point format", `${pointFormat}${formatByte & 0xc0 ? " (compression bits set)" : ""}`],
    ["Point record length", `${recordLength} bytes`],
    ["Points", fmtInt(count)],
    ["Scale", fmtVec(scale, 6)],
    ["Offset", fmtVec(offset, 3)],
    ["Bounds min (X, Y, Z)", fmtVec(min, 3)],
    ["Bounds max (X, Y, Z)", fmtVec(max, 3)],
    [
      "Extent",
      `${fmtVec(
        max.map((v, i) => v - min[i]),
        3,
      )} m`,
    ],
    ["Header size", `${headerSize} bytes`],
    ["Point data offset", `${pointOffset} bytes`],
    ["VLRs", fmtInt(vlrCount)],
    ["File size", `${fmtBytes(stat.size)} (${fmtInt(stat.size)} bytes)`],
  );
  const expected = pointOffset + count * recordLength;
  if (expected !== stat.size) {
    out.problems.push(
      `Header says ${fmtInt(expected)} bytes (offset + points × record length) but the file has ${fmtInt(stat.size)}.`,
    );
  }
  // VLR headers follow the public header block.
  const vlrs = [];
  let at = headerSize;
  for (let i = 0; i < Math.min(vlrCount, 20) && at + 54 <= b.length; i += 1) {
    const length = b.readUInt16LE(at + 20);
    vlrs.push([
      untilNul(b.toString("latin1", at + 2, at + 18)),
      String(b.readUInt16LE(at + 18)),
      fmtInt(length),
      untilNul(b.toString("latin1", at + 22, at + 54)),
    ]);
    at += 54 + length;
  }
  // First few points.
  const first = Math.min(count, 5);
  if (first > 0 && recordLength >= 12) {
    const pts = await readSlice(abs, pointOffset, first * recordLength);
    const rows = [];
    for (let i = 0; i < first && (i + 1) * recordLength <= pts.length; i += 1) {
      const o = i * recordLength;
      const xyz = [0, 1, 2].map((j) => pts.readInt32LE(o + j * 4) * scale[j] + offset[j]);
      const rgb =
        (pointFormat === 7 || pointFormat === 8) && recordLength >= 36
          ? [30, 32, 34].map((k) => pts.readUInt16LE(o + k) >> 8).join(", ")
          : "—";
      rows.push([String(i + 1), fmtNum(xyz[0]), fmtNum(xyz[1]), fmtNum(xyz[2]), rgb]);
    }
    out.table = { columns: ["Point", "X", "Y", "Z", "RGB (8-bit)"], rows };
  }
  if (vlrs.length)
    out.table2 = { columns: ["VLR user id", "Record id", "Length", "Description"], rows: vlrs };
  out.notes.push(
    "Chapter LAS axes: X = capture x, Y = −capture z (plan up), Z = height (capture +Y).",
  );
  return out;
}

async function readSlice(abs, position, length) {
  const handle = await fsp.open(abs, "r");
  try {
    const buffer = Buffer.alloc(length);
    const { bytesRead } = await handle.read(buffer, 0, length, position);
    return buffer.subarray(0, bytesRead);
  } finally {
    await handle.close();
  }
}

/** depth-samples.bin: "CHDS" v1, 16-byte header, 16-byte records (DepthSamplesCodec). */
async function depthPreview(abs, stat) {
  const out = newPreview("facts");
  out.facts.push(["File size", `${fmtBytes(stat.size)} (${fmtInt(stat.size)} bytes)`]);
  if (stat.size > BINARY_SUMMARY_MAX_BYTES) {
    out.problems.push("Too large to summarise here.");
    return out;
  }
  const b = await fsp.readFile(abs);
  if (b.length < 16 || b.toString("latin1", 0, 4) !== "CHDS") {
    out.problems.push("Does not start with the CHDS magic: not a depth samples file.");
    return out;
  }
  const version = b.readUInt32LE(4);
  const count = b.readUInt32LE(8);
  out.facts.push(["Magic / version", `CHDS / ${version}`], ["Samples (header)", fmtInt(count)]);
  if (version !== 1) out.problems.push(`Unsupported version ${version} (the app writes 1).`);
  const expected = 16 + count * 16;
  if (expected !== b.length) {
    out.problems.push(
      `Header says ${fmtInt(count)} samples = ${fmtInt(expected)} bytes, but the file has ${fmtInt(b.length)} bytes.`,
    );
  }
  const n = Math.min(count, Math.floor((b.length - 16) / 16));
  if (n === 0) {
    if (count === 0) out.notes.push("No depth samples were recorded for this scan (header only).");
    return out;
  }
  const min = [Infinity, Infinity, Infinity];
  const max = [-Infinity, -Infinity, -Infinity];
  const sum = [0, 0, 0];
  const confidence = [0, 0, 0, 0];
  let colored = 0;
  let nonFinite = 0;
  for (let i = 0; i < n; i += 1) {
    const o = 16 + i * 16;
    const v = [b.readFloatLE(o), b.readFloatLE(o + 4), b.readFloatLE(o + 8)];
    if (!v.every(Number.isFinite)) {
      nonFinite += 1;
      continue;
    }
    for (let j = 0; j < 3; j += 1) {
      if (v[j] < min[j]) min[j] = v[j];
      if (v[j] > max[j]) max[j] = v[j];
      sum[j] += v[j];
    }
    if (b[o + 12] || b[o + 13] || b[o + 14]) colored += 1;
    confidence[Math.min(b[o + 15], 3)] += 1;
  }
  const good = n - nonFinite;
  out.facts.push(
    ["Bounds min (x, y, z)", `${fmtVec(min, 3)} m`],
    ["Bounds max (x, y, z)", `${fmtVec(max, 3)} m`],
    [
      "Extent",
      `${fmtVec(
        max.map((v, i) => v - min[i]),
        2,
      )} m`,
    ],
    [
      "Mean point",
      `${fmtVec(
        sum.map((v) => v / Math.max(good, 1)),
        3,
      )} m`,
    ],
    [
      "Confidence low / medium / high",
      `${fmtInt(confidence[0])} / ${fmtInt(confidence[1])} / ${fmtInt(confidence[2])}${confidence[3] ? ` (other ${fmtInt(confidence[3])})` : ""}`,
    ],
    ["With colour", `${fmtInt(colored)} (${fmtNum((100 * colored) / n, 1)} %)`],
  );
  if (nonFinite) out.problems.push(`${fmtInt(nonFinite)} samples are not finite numbers.`);
  out.notes.push("Capture frame: metres, +Y up; the plan uses x and z.");
  return out;
}

/** mesh-anchors.bin: "CHMA" v1 (MeshAnchorsCodec). */
async function meshAnchorsPreview(abs, stat) {
  const out = newPreview("facts");
  out.facts.push(["File size", `${fmtBytes(stat.size)} (${fmtInt(stat.size)} bytes)`]);
  if (stat.size > BINARY_SUMMARY_MAX_BYTES) {
    out.problems.push("Too large to summarise here.");
    return out;
  }
  const b = await fsp.readFile(abs);
  if (b.length < 16 || b.toString("latin1", 0, 4) !== "CHMA") {
    out.problems.push("Does not start with the CHMA magic: not a mesh anchors file.");
    return out;
  }
  const version = b.readUInt32LE(4);
  const count = b.readUInt32LE(8);
  out.facts.push(["Magic / version", `CHMA / ${version}`], ["Anchors (header)", fmtInt(count)]);
  if (version !== 1) out.problems.push(`Unsupported version ${version} (the app writes 1).`);
  let at = 16;
  let vertices = 0;
  let triangles = 0;
  const min = [Infinity, Infinity, Infinity];
  const max = [-Infinity, -Infinity, -Infinity];
  const rows = [];
  let parsed = 0;
  for (let i = 0; i < count; i += 1) {
    if (at + 16 + 64 + 8 > b.length) {
      out.problems.push(`File ends inside anchor ${i + 1} of ${count}.`);
      break;
    }
    const id = b
      .toString("hex", at, at + 16)
      .replace(/^(.{8})(.{4})(.{4})(.{4})(.{12})$/, "$1-$2-$3-$4-$5");
    const t = [];
    for (let k = 0; k < 16; k += 1) t.push(b.readFloatLE(at + 16 + k * 4));
    const vc = b.readUInt32LE(at + 80);
    const tc = b.readUInt32LE(at + 84);
    const dataStart = at + 88;
    const dataEnd = dataStart + (vc * 3 + tc * 3) * 4;
    if (dataEnd > b.length) {
      out.problems.push(
        `Anchor ${i + 1} says ${fmtInt(vc)} vertices and ${fmtInt(tc)} triangles but the file is shorter.`,
      );
      break;
    }
    for (let v = 0; v < vc; v += 1) {
      const o = dataStart + v * 12;
      const x = b.readFloatLE(o);
      const y = b.readFloatLE(o + 4);
      const z = b.readFloatLE(o + 8);
      for (let axis = 0; axis < 3; axis += 1) {
        const w = t[axis] * x + t[4 + axis] * y + t[8 + axis] * z + t[12 + axis];
        if (w < min[axis]) min[axis] = w;
        if (w > max[axis]) max[axis] = w;
      }
    }
    vertices += vc;
    triangles += tc;
    parsed += 1;
    if (rows.length < 200)
      rows.push([String(i + 1), id, fmtInt(vc), fmtInt(tc), fmtVec([t[12], t[13], t[14]], 2)]);
    at = dataEnd;
  }
  out.facts.push(
    ["Anchors read", fmtInt(parsed)],
    ["Vertices", fmtInt(vertices)],
    ["Triangles", fmtInt(triangles)],
  );
  if (vertices > 0) {
    out.facts.push(
      ["World bounds min", `${fmtVec(min, 2)} m`],
      ["World bounds max", `${fmtVec(max, 2)} m`],
    );
  }
  if (parsed === count && at !== b.length) {
    out.problems.push(
      `${fmtInt(b.length - at)} bytes after the last anchor (the reader expects none).`,
    );
  }
  out.table = { columns: ["#", "Anchor", "Vertices", "Triangles", "Position (x, y, z)"], rows };
  if (count > rows.length) out.notes.push(`Table shows the first ${rows.length} anchors.`);
  out.notes.push(
    "Not part of the package: MeshExport turns it into mesh.glb, mesh.obj and mesh.mtl.",
  );
  return out;
}

async function preview(rel) {
  const { abs, stat, name } = await resolveDataPath(rel, "file");
  switch (previewKind(name)) {
    case "las":
      return lasPreview(abs, stat);
    case "depth":
      return depthPreview(abs, stat);
    case "mesh-anchors":
      return meshAnchorsPreview(abs, stat);
    case "csv":
      return csvPreview(abs, stat);
    case "json":
    case "camera-poses":
    case "upload-state":
      return jsonPreview(abs, stat, name);
    case "text":
      return textPreview(abs, stat);
    case "binary":
      return binaryPreview(abs, stat);
    default:
      return textPreview(abs, stat);
  }
}

// ---------------------------------------------------------------------------------------------
// Room sketch from capture-model.json. Plan axes are x and z (plan up is −z, so SVG y = z).

function polygonArea(points) {
  let twice = 0;
  for (let i = 0; i < points.length; i += 1) {
    const [x1, z1] = points[i];
    const [x2, z2] = points[(i + 1) % points.length];
    twice += x1 * z2 - x2 * z1;
  }
  return twice / 2;
}

function pointInPolygon([x, z], points) {
  let inside = false;
  for (let i = 0, j = points.length - 1; i < points.length; j = i, i += 1) {
    const [xi, zi] = points[i];
    const [xj, zj] = points[j];
    if (zi > z !== zj > z && x < ((xj - xi) * (z - zi)) / (zj - zi) + xi) inside = !inside;
  }
  return inside;
}

function distanceToSegment([px, pz], [ax, az], [bx, bz]) {
  const dx = bx - ax;
  const dz = bz - az;
  const len2 = dx * dx + dz * dz;
  const t = len2 > 0 ? Math.max(0, Math.min(1, ((px - ax) * dx + (pz - az) * dz) / len2)) : 0;
  return Math.hypot(px - (ax + t * dx), pz - (az + t * dz));
}

/** A point well inside the polygon for its label (centroid when inside, else a grid search). */
function labelPoint(points) {
  const a = polygonArea(points);
  let cx = 0;
  let cz = 0;
  for (let i = 0; i < points.length; i += 1) {
    const [x1, z1] = points[i];
    const [x2, z2] = points[(i + 1) % points.length];
    const cross = x1 * z2 - x2 * z1;
    cx += (x1 + x2) * cross;
    cz += (z1 + z2) * cross;
  }
  const edgeDistance = (p) =>
    Math.min(...points.map((q, i) => distanceToSegment(p, q, points[(i + 1) % points.length])));
  const centroid = Math.abs(a) > 1e-9 ? [cx / (6 * a), cz / (6 * a)] : points[0];
  let best = pointInPolygon(centroid, points) ? centroid : null;
  let bestDistance = best ? edgeDistance(best) : -1;
  const xs = points.map((p) => p[0]);
  const zs = points.map((p) => p[1]);
  const [minX, maxX, minZ, maxZ] = [
    Math.min(...xs),
    Math.max(...xs),
    Math.min(...zs),
    Math.max(...zs),
  ];
  if (!best || bestDistance < 0.6) {
    const steps = 16;
    for (let i = 1; i < steps; i += 1) {
      for (let j = 1; j < steps; j += 1) {
        const p = [minX + ((maxX - minX) * i) / steps, minZ + ((maxZ - minZ) * j) / steps];
        if (!pointInPolygon(p, points)) continue;
        const d = edgeDistance(p);
        if (d > bestDistance * 1.25) {
          best = p;
          bestDistance = d;
        }
      }
    }
  }
  return best ?? centroid;
}

export function sketchFromModel(model) {
  const flat = (p) =>
    Array.isArray(p) && p.length >= 3 && Number.isFinite(p[0]) && Number.isFinite(p[2])
      ? [p[0], p[2]]
      : null;
  const bounds = { minX: Infinity, maxX: -Infinity, minZ: Infinity, maxZ: -Infinity };
  const grow = ([x, z]) => {
    bounds.minX = Math.min(bounds.minX, x);
    bounds.maxX = Math.max(bounds.maxX, x);
    bounds.minZ = Math.min(bounds.minZ, z);
    bounds.maxZ = Math.max(bounds.maxZ, z);
  };
  const rooms = [];
  for (const r of Array.isArray(model?.rooms) ? model.rooms : []) {
    const polygon = (Array.isArray(r?.polygon) ? r.polygon : []).map(flat).filter(Boolean);
    if (polygon.length < 3) continue;
    polygon.forEach(grow);
    const areaM2 = Math.abs(polygonArea(polygon));
    rooms.push({
      id: String(r.id ?? ""),
      label: String(r.label ?? r.id ?? ""),
      type: typeof r.type === "string" ? r.type : null,
      typeSource: typeof r.typeSource === "string" ? r.typeSource : null,
      heightM: Number.isFinite(r.heightM) ? r.heightM : null,
      areaM2,
      areaFt2: areaM2 * FT2_PER_M2,
      polygon,
      labelAt: labelPoint(polygon),
    });
  }
  const walls = [];
  const wallById = new Map();
  for (const w of Array.isArray(model?.walls) ? model.walls : []) {
    const a = flat(w?.start);
    const b = flat(w?.end);
    if (!a || !b) continue;
    grow(a);
    grow(b);
    const wall = {
      id: String(w.id ?? ""),
      a,
      b,
      lengthM: Math.hypot(b[0] - a[0], b[1] - a[1]),
      thicknessM: Number.isFinite(w.thicknessM) ? w.thicknessM : 0,
      roomIds: Array.isArray(w.roomIds) ? w.roomIds.map(String) : [],
    };
    walls.push(wall);
    wallById.set(wall.id, wall);
  }
  const openings = [];
  const unplaced = [];
  const counts = { door: 0, window: 0, opening: 0 };
  for (const [kind, list] of [
    ["door", model?.doors],
    ["window", model?.windows],
    ["opening", model?.openings],
  ]) {
    for (const o of Array.isArray(list) ? list : []) {
      counts[kind] += 1;
      const wall = wallById.get(String(o?.wallId ?? ""));
      if (
        !wall ||
        !(wall.lengthM > 0) ||
        !Number.isFinite(o.offsetM) ||
        !Number.isFinite(o.widthM)
      ) {
        unplaced.push(String(o?.id ?? "?"));
        continue;
      }
      const ux = (wall.b[0] - wall.a[0]) / wall.lengthM;
      const uz = (wall.b[1] - wall.a[1]) / wall.lengthM;
      const from = o.offsetM - o.widthM / 2;
      const to = o.offsetM + o.widthM / 2;
      openings.push({
        id: String(o.id ?? ""),
        kind,
        wallId: wall.id,
        a: [wall.a[0] + ux * from, wall.a[1] + uz * from],
        b: [wall.a[0] + ux * to, wall.a[1] + uz * to],
        widthM: o.widthM,
        heightM: Number.isFinite(o.heightM) ? o.heightM : null,
        isOpen: typeof o.isOpen === "boolean" ? o.isOpen : null,
      });
    }
  }
  const areaM2 = rooms.reduce((s, r) => s + r.areaM2, 0);
  return {
    label: typeof model?.label === "string" ? model.label : null,
    areaKey: typeof model?.areaKey === "string" ? model.areaKey : null,
    captureId: typeof model?.captureId === "string" ? model.captureId : null,
    schemaVersion: typeof model?.schemaVersion === "string" ? model.schemaVersion : null,
    rooms,
    walls,
    openings,
    unplaced,
    bounds: Number.isFinite(bounds.minX) ? bounds : null,
    totals: {
      rooms: rooms.length,
      areaM2,
      areaFt2: areaM2 * FT2_PER_M2,
      walls: walls.length,
      doors: counts.door,
      windows: counts.window,
      openings: counts.opening,
    },
  };
}

async function sketch(rel) {
  const { abs, name } = await resolveDataPath(rel, "file");
  if (name !== "capture-model.json") throw fail(400, "A sketch needs a capture-model.json.");
  const parsed = await readJson(abs, 64 * 1024 * 1024);
  if (!parsed.value) throw fail(422, `capture-model.json could not be read: ${parsed.error}`);
  return { path: rel, ...sketchFromModel(parsed.value) };
}

// ---------------------------------------------------------------------------------------------
// Photos: HEIC (and other images) to JPEG with macOS sips, cached outside the data folder.

const converting = new Map();
let sipsRunning = 0;
const sipsQueue = [];

/** At most three sips at a time; a finished job hands its slot to the next waiting one. */
async function withSipsSlot(task) {
  if (sipsRunning >= 3) await new Promise((resolve) => sipsQueue.push(resolve));
  else sipsRunning += 1;
  try {
    return await task();
  } finally {
    const waiting = sipsQueue.shift();
    if (waiting) waiting();
    else sipsRunning -= 1;
  }
}

async function photoJpeg(rel, widthParam) {
  const { abs, stat, name } = await resolveDataPath(rel, "file");
  if (!["heic", "image"].includes(previewKind(name))) throw fail(400, "Not a photo.");
  const requested = Number(widthParam) || 480;
  const width = PHOTO_WIDTHS.find((w) => w >= requested) ?? PHOTO_WIDTHS.at(-1);
  const key = createHash("sha256")
    .update(`${abs}\0${stat.size}\0${stat.mtimeMs}\0${width}`)
    .digest("hex");
  const out = path.join(CACHE, `${key}.jpg`);
  if (existsSync(out)) return out;
  if (!converting.has(key)) {
    const job = withSipsSlot(async () => {
      const tmp = path.join(CACHE, `.${key}.${randomBytes(4).toString("hex")}.jpg`);
      const r = await run(
        "sips",
        [
          "-s",
          "format",
          "jpeg",
          "-s",
          "formatOptions",
          "82",
          "-Z",
          String(width),
          abs,
          "--out",
          tmp,
        ],
        { timeoutMs: 60000 },
      );
      if (r.code !== 0) {
        await fsp.rm(tmp, { force: true });
        if (r.error?.code === "ENOENT")
          throw fail(501, "Photo preview needs macOS (sips was not found).");
        throw fail(
          500,
          `sips could not convert ${name}: ${(r.stderr || r.stdout).trim().split("\n").at(-1)}`,
        );
      }
      await fsp.rename(tmp, out);
      return out;
    }).finally(() => converting.delete(key));
    converting.set(key, job);
  }
  return converting.get(key);
}

// ---------------------------------------------------------------------------------------------
// Sync from iPhone (xcrun devicectl; every command is execFile with an argument array).

function run(cmd, args, { env = process.env, timeoutMs = 60000 } = {}) {
  return new Promise((resolve) => {
    execFile(
      cmd,
      args,
      { env, timeout: timeoutMs, maxBuffer: 64 * 1024 * 1024, encoding: "utf8" },
      (error, stdout, stderr) => {
        const code = error ? (typeof error.code === "number" ? error.code : -1) : 0;
        resolve({ code, error, stdout: stdout ?? "", stderr: stderr ?? "" });
      },
    );
  });
}

function devicectlEnv() {
  if (process.env.DEVELOPER_DIR) return process.env;
  for (const app of ["/Applications/Xcode-beta.app", "/Applications/Xcode.app"]) {
    const dir = path.join(app, "Contents", "Developer");
    if (existsSync(dir)) return { ...process.env, DEVELOPER_DIR: dir };
  }
  return process.env;
}

/** The useful part of a devicectl failure (its ERROR line and failure reason). */
export function devicectlError(r) {
  if (r.error?.killed) return "devicectl timed out.";
  const lines = `${r.stderr}\n${r.stdout}`
    .split("\n")
    .map((l) => l.trim())
    .filter(Boolean);
  const error = lines.find((l) => l.startsWith("ERROR:"))?.replace(/^ERROR:\s*/, "");
  const reason = lines
    .find((l) => l.startsWith("NSLocalizedFailureReason"))
    ?.replace(/^NSLocalizedFailureReason\s*=\s*/, "");
  const recovery = lines
    .find((l) => l.startsWith("NSLocalizedRecoverySuggestion"))
    ?.replace(/^NSLocalizedRecoverySuggestion\s*=\s*/, "");
  const text =
    [error, reason, recovery].filter(Boolean).join(" — ") || lines.at(-1) || `exit code ${r.code}`;
  return text.slice(0, 500);
}

/** Picks the iPhone to copy from in `devicectl list devices` JSON. Simulators are ignored. */
export function pickDevice(json) {
  const devices = Array.isArray(json?.result?.devices) ? json.result.devices : [];
  const phones = devices.filter(
    (d) =>
      d?.hardwareProperties?.reality === "physical" &&
      ["iOS", "iPadOS"].includes(d?.hardwareProperties?.platform),
  );
  const name = (d) =>
    d?.deviceProperties?.name ?? d?.hardwareProperties?.marketingName ?? d?.identifier ?? "iPhone";
  const transport = (d) => d?.connectionProperties?.transportType;
  const device =
    phones.find((d) => d?.connectionProperties?.tunnelState === "connected") ??
    phones.find((d) => transport(d) === "wired") ??
    phones.find((d) => transport(d) === "localNetwork") ??
    null;
  if (device) {
    return {
      device: {
        id: String(device.identifier),
        name: name(device),
        model: device.hardwareProperties?.marketingName ?? null,
        transport: transport(device) ?? null,
      },
    };
  }
  if (phones.length === 0) {
    return {
      device: null,
      message:
        "No iPhone is connected. Plug the iPhone in with a cable, unlock it and tap Trust if it asks, then press Sync again.",
    };
  }
  const names = phones.map(name).join(", ");
  return {
    device: null,
    message: `No iPhone is connected. ${names} ${phones.length === 1 ? "is" : "are"} paired with this Mac but not reachable now: plug it in with a cable and unlock it, then press Sync again.`,
  };
}

/** Files and folders from `devicectl device info files` JSON, paths relative to FieldTestVisits. */
export function parseRemoteListing(json) {
  const files = json?.result?.files;
  if (!Array.isArray(files)) throw new Error("devicectl returned no file list.");
  return files
    .map((f) => ({
      rel: typeof f?.relativePath === "string" ? f.relativePath : f?.name,
      isDir: f?.resources?.isDirectory === true,
      isLink: f?.resources?.isSymbolicLink === true,
      size: Number(f?.metadata?.size ?? 0),
      mtimeMs: Date.parse(f?.metadata?.lastModDate ?? ""),
    }))
    .filter((f) => typeof f.rel === "string" && f.rel.length > 0);
}

function idleSync() {
  return { status: "idle", message: "Not synced in this session yet.", failures: [] };
}
let syncState = idleSync();

function syncSnapshot() {
  return {
    ...syncState,
    failures: syncState.failures.slice(0, 200),
    failureCount: syncState.failures.length,
  };
}

/** Local path in DATA for a phone path (validated like a request path). */
function localPathFor(rel) {
  const dest = path.resolve(DATA, ...safeSegments(rel));
  if (!isInsideData(dest)) throw new Error("outside the data folder");
  return dest;
}

/** Creates a folder chain inside DATA; folders copied read-only by hand are made owner-writable. */
async function ensureWritableDir(dir) {
  const parts = path.relative(DATA, dir).split(path.sep).filter(Boolean);
  let current = DATA;
  for (const part of parts) {
    current = path.join(current, part);
    let st;
    try {
      st = await fsp.lstat(current);
    } catch (err) {
      if (err.code !== "ENOENT") throw err;
      try {
        await fsp.mkdir(current);
      } catch (mkdirErr) {
        if (mkdirErr.code !== "EEXIST") throw mkdirErr;
      }
      continue;
    }
    if (st.isSymbolicLink() || !st.isDirectory())
      throw new Error(`${path.relative(DATA, current)} is not a folder`);
    if ((st.mode & 0o700) !== 0o700) await fsp.chmod(current, (st.mode & 0o7777) | 0o700);
  }
}

class SyncStop extends Error {}

async function runSync() {
  const s = syncState;
  const env = devicectlEnv();
  const found = await run("xcrun", ["--find", "devicectl"], { env, timeoutMs: 30000 });
  if (found.error?.code === "ENOENT")
    throw new SyncStop("xcrun was not found. Sync needs a Mac with Xcode installed.");
  if (found.code !== 0) {
    throw new SyncStop(
      `Xcode's devicectl was not found (${devicectlError(found)}). Install Xcode or Xcode-beta, or set DEVELOPER_DIR to its Contents/Developer folder.`,
    );
  }
  const tmp = await fsp.mkdtemp(path.join(os.tmpdir(), "scan-browser-"));
  try {
    const devicesJson = path.join(tmp, "devices.json");
    const listed = await run(
      "xcrun",
      ["devicectl", "list", "devices", "--json-output", devicesJson],
      { env, timeoutMs: 90000 },
    );
    if (listed.code !== 0)
      throw new SyncStop(`devicectl could not list devices: ${devicectlError(listed)}`);
    const picked = pickDevice(JSON.parse(await fsp.readFile(devicesJson, "utf8")));
    if (!picked.device) throw new SyncStop(picked.message);
    const device = picked.device;
    s.device = device;
    s.phase = "listing";
    s.message = `Listing the app's files on ${device.name}…`;

    const filesJson = path.join(tmp, "files.json");
    const domain = ["--domain-type", "appDataContainer", "--domain-identifier", BUNDLE_ID];
    const info = await run(
      "xcrun",
      [
        "devicectl",
        "device",
        "info",
        "files",
        "--device",
        device.id,
        ...domain,
        "--subdirectory",
        REMOTE_ROOT,
        "--json-output",
        filesJson,
      ],
      { env, timeoutMs: 120000 },
    );
    if (info.code !== 0) {
      throw new SyncStop(
        `Could not list the app's files on ${device.name}: ${devicectlError(info)}. Check that the phone is unlocked and that the Chapter Capture field-test build (${BUNDLE_ID}) is installed and has started a visit.`,
      );
    }
    const remote = parseRemoteListing(JSON.parse(await fsp.readFile(filesJson, "utf8")));

    // Plan: folders first (so empty visits show up too), then every file that is new or changed.
    const queue = [];
    const dirs = new Set();
    for (const item of remote) {
      if (item.isLink) continue;
      let local;
      try {
        local = localPathFor(item.rel);
      } catch (err) {
        s.failures.push({ path: item.rel, error: `Skipped: ${err.message}` });
        continue;
      }
      if (item.isDir) {
        dirs.add(local);
        continue;
      }
      dirs.add(path.dirname(local));
      try {
        const st = await fsp.lstat(local);
        if (
          st.isFile() &&
          st.size === item.size &&
          Number.isFinite(item.mtimeMs) &&
          Math.abs(st.mtimeMs - item.mtimeMs) < 2000
        ) {
          s.skipped += 1;
          continue;
        }
      } catch {
        // Not copied yet.
      }
      queue.push({ ...item, local });
    }
    for (const dir of [...dirs].sort()) {
      try {
        await ensureWritableDir(dir);
      } catch (err) {
        s.failures.push({
          path: path.relative(DATA, dir),
          error: `Folder could not be created: ${err.message}`,
        });
      }
    }
    s.total = queue.length;
    s.totalBytes = queue.reduce((sum, q) => sum + q.size, 0);
    s.phase = "copying";

    let next = 0;
    let consecutiveFailures = 0;
    const worker = async () => {
      while (next < queue.length && consecutiveFailures < 6) {
        const item = queue[next];
        next += 1;
        s.message = `Copying ${Math.min(s.done + 1, s.total)} of ${s.total} files from ${device.name}…`;
        const tmpName = path.join(
          path.dirname(item.local),
          `.${path.basename(item.local)}.partial-${randomBytes(4).toString("hex")}`,
        );
        const r = await run(
          "xcrun",
          [
            "devicectl",
            "device",
            "copy",
            "from",
            "--device",
            device.id,
            ...domain,
            "--source",
            `${REMOTE_ROOT}/${item.rel}`,
            "--destination",
            tmpName,
          ],
          { env, timeoutMs: 120000 + Math.ceil(item.size / 50000) },
        );
        let error = null;
        if (r.code !== 0) {
          error = devicectlError(r);
        } else {
          try {
            const st = await fsp.stat(tmpName);
            if (st.size !== item.size)
              error = `copied ${st.size} bytes, the phone lists ${item.size}`;
            else await fsp.rename(tmpName, item.local);
          } catch (err) {
            error = err.message;
          }
        }
        if (error) {
          await fsp.rm(tmpName, { force: true }).catch(() => {});
          s.failures.push({ path: item.rel, error });
          consecutiveFailures += 1;
        } else {
          consecutiveFailures = 0;
          if (Number.isFinite(item.mtimeMs))
            await fsp.utimes(item.local, new Date(), new Date(item.mtimeMs)).catch(() => {});
          s.copied += 1;
          s.copiedBytes += item.size;
        }
        s.done += 1;
        s.doneBytes += item.size;
      }
    };
    await Promise.all(Array.from({ length: Math.min(SYNC_CONCURRENCY, queue.length) }, worker));
    // Folder times as on the phone (deepest first), so an empty visit shows when it was started.
    const remoteDirs = remote.filter((item) => item.isDir && Number.isFinite(item.mtimeMs));
    remoteDirs.sort((a, b) => b.rel.split("/").length - a.rel.split("/").length);
    for (const item of remoteDirs) {
      try {
        await fsp.utimes(localPathFor(item.rel), new Date(), new Date(item.mtimeMs));
      } catch {
        // Not created (already reported) or not settable: the time is only informational.
      }
    }
    if (consecutiveFailures >= 6 && s.done < s.total) {
      s.aborted = `Stopped after ${consecutiveFailures} failures in a row (was the iPhone unplugged or locked?). ${s.total - s.done} files were not tried.`;
    }
  } finally {
    await fsp.rm(tmp, { recursive: true, force: true }).catch(() => {});
  }
}

function startSync() {
  if (syncState.status === "running") throw fail(409, "A sync is already running.");
  syncState = {
    status: "running",
    phase: "device",
    message: "Looking for a connected iPhone…",
    startedAt: new Date().toISOString(),
    finishedAt: null,
    dataDir: DATA,
    device: null,
    total: 0,
    done: 0,
    totalBytes: 0,
    doneBytes: 0,
    copied: 0,
    copiedBytes: 0,
    skipped: 0,
    failures: [],
    aborted: null,
  };
  const s = syncState;
  runSync()
    .then(() => {
      const from = s.device ? ` from ${s.device.name}` : "";
      const parts = [];
      if (s.total === 0)
        parts.push(`Everything is up to date: ${s.skipped} files were already copied${from}.`);
      else
        parts.push(
          `Copied ${s.copied} file${s.copied === 1 ? "" : "s"} (${fmtBytes(s.copiedBytes)})${from}; ${s.skipped} were already up to date.`,
        );
      if (s.failures.length) parts.push(`${s.failures.length} failed (listed below).`);
      if (s.aborted) parts.push(s.aborted);
      s.status = s.failures.length || s.aborted ? "partial" : "done";
      s.message = parts.join(" ");
    })
    .catch((err) => {
      s.status = "error";
      s.message = err instanceof SyncStop ? err.message : `Sync failed: ${err.message}`;
    })
    .finally(() => {
      s.phase = "finished";
      s.finishedAt = new Date().toISOString();
      console.log(`[sync] ${s.status}: ${s.message}`);
    });
  return syncSnapshot();
}

// ---------------------------------------------------------------------------------------------
// HTTP routing

const STATIC_FILES = {
  "/": ["index.html", "text/html; charset=utf-8"],
  "/index.html": ["index.html", "text/html; charset=utf-8"],
  "/app.js": ["app.js", "text/javascript; charset=utf-8"],
  "/styles.css": ["styles.css", "text/css; charset=utf-8"],
};

const FILE_TYPES = {
  ".json": "application/json; charset=utf-8",
  ".csv": "text/csv; charset=utf-8",
  ".txt": "text/plain; charset=utf-8",
  ".dxf": "text/plain; charset=utf-8",
  ".obj": "text/plain; charset=utf-8",
  ".mtl": "text/plain; charset=utf-8",
  ".md": "text/plain; charset=utf-8",
  ".log": "text/plain; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".webp": "image/webp",
  ".heic": "image/heic",
  ".heif": "image/heif",
  ".pdf": "application/pdf",
  ".glb": "model/gltf-binary",
};

async function serveFile(req, res, url) {
  const { abs, stat, name } = await resolveDataPath(url.searchParams.get("path"), "file");
  const download = url.searchParams.get("download") === "1";
  const type = FILE_TYPES[path.extname(name).toLowerCase()] ?? "application/octet-stream";
  const headers = {
    "Content-Type": type,
    "Content-Length": String(stat.size),
    "Content-Security-Policy": type === "application/pdf" && !download ? PDF_CSP : FILE_CSP,
    "Content-Disposition": contentDisposition(download ? "attachment" : "inline", name),
  };
  res.writeHead(200, { ...SECURITY_HEADERS, ...headers });
  if (req.method === "HEAD") {
    res.end();
    return;
  }
  const stream = createReadStream(abs);
  stream.on("error", () => res.destroy());
  stream.pipe(res);
}

async function servePhoto(req, res, url) {
  const jpeg = await photoJpeg(url.searchParams.get("path"), url.searchParams.get("w"));
  const st = await fsp.stat(jpeg);
  res.writeHead(200, {
    ...SECURITY_HEADERS,
    "Content-Type": "image/jpeg",
    "Content-Length": String(st.size),
    "Content-Security-Policy": FILE_CSP,
    "Cache-Control": "private, max-age=3600",
  });
  if (req.method === "HEAD") {
    res.end();
    return;
  }
  const stream = createReadStream(jpeg);
  stream.on("error", () => res.destroy());
  stream.pipe(res);
}

async function serveStatic(res, pathname) {
  const [file, type] = STATIC_FILES[pathname];
  const body = await fsp.readFile(path.join(PUBLIC_DIR, file));
  const headers = { "Content-Type": type };
  if (file === "index.html") headers["Content-Security-Policy"] = PAGE_CSP;
  send(res, 200, body, headers);
}

function allowedHost(host) {
  return host === `127.0.0.1:${PORT}` || host === `localhost:${PORT}`;
}

function checkPost(req) {
  // A cross-site page cannot set this header without a CORS preflight, which is never granted.
  if (req.headers["x-scan-browser"] !== "1") throw fail(403, "Missing X-Scan-Browser header.");
  const origin = req.headers.origin;
  if (origin && origin !== `http://127.0.0.1:${PORT}` && origin !== `http://localhost:${PORT}`) {
    throw fail(403, "Cross-origin request refused.");
  }
}

async function handle(req, res) {
  // Requests for any other host name are refused (protects against DNS rebinding).
  if (!allowedHost(req.headers.host ?? ""))
    throw fail(421, "This server only answers 127.0.0.1 and localhost.");
  if (!req.url || !req.url.startsWith("/") || req.url.startsWith("//"))
    throw fail(400, "Bad request.");
  const url = new URL(req.url, `http://127.0.0.1:${PORT}`);
  const pathname = url.pathname;
  const isRead = req.method === "GET" || req.method === "HEAD";

  if (pathname === "/api/sync") {
    if (req.method === "POST") {
      checkPost(req);
      return sendJson(res, 202, startSync());
    }
    if (isRead) return sendJson(res, 200, syncSnapshot());
    throw fail(405, "Method not allowed.");
  }
  if (!isRead) throw fail(405, "Method not allowed.");
  if (Object.hasOwn(STATIC_FILES, pathname)) return serveStatic(res, pathname);
  if (pathname === "/favicon.ico") return send(res, 204, "");
  if (pathname === "/api/status") {
    return sendJson(res, 200, {
      dataDir: DATA,
      cacheDir: CACHE,
      port: PORT,
      bundleId: BUNDLE_ID,
      remoteRoot: REMOTE_ROOT,
    });
  }
  if (pathname === "/api/visits") return sendJson(res, 200, await listVisits());
  if (pathname === "/api/visit")
    return sendJson(res, 200, await visitDetail(url.searchParams.get("id")));
  if (pathname === "/api/file") return serveFile(req, res, url);
  if (pathname === "/api/preview")
    return sendJson(res, 200, await preview(url.searchParams.get("path")));
  if (pathname === "/api/photo") return servePhoto(req, res, url);
  if (pathname === "/api/sketch")
    return sendJson(res, 200, await sketch(url.searchParams.get("path")));
  throw fail(404, "Not found.");
}

async function main() {
  let config;
  try {
    config = readConfig(process.argv.slice(2), process.env);
  } catch (err) {
    console.error(`${err.message}\n\n${usage()}`);
    process.exit(2);
  }
  if (config.help) {
    console.log(usage());
    return;
  }
  // Scans are photos and plans of real homes: never keep them in the repository. Checked before
  // the folder is created and again after symlinks are resolved.
  const repo = await fsp.realpath(REPO_ROOT).catch(() => REPO_ROOT);
  const insideRepo = (p) =>
    p === repo ||
    p.startsWith(repo + path.sep) ||
    p === REPO_ROOT ||
    p.startsWith(REPO_ROOT + path.sep);
  const refuse = (p) => {
    console.error(
      `The data folder ${p} is inside the repository. Keep scans outside it (default ~/ChapterCaptureScans).`,
    );
    process.exit(2);
  };
  if (insideRepo(config.dataDir)) refuse(config.dataDir);
  await fsp.mkdir(config.dataDir, { recursive: true });
  DATA = await fsp.realpath(config.dataDir);
  if (insideRepo(DATA)) refuse(DATA);
  CACHE = cacheRoot();
  await fsp.mkdir(CACHE, { recursive: true, mode: 0o700 });
  PORT = config.port;

  const server = http.createServer((req, res) => {
    handle(req, res).catch((err) => {
      const status = err instanceof HttpError ? err.status : 500;
      if (status === 500) console.error(err);
      if (res.headersSent) {
        res.destroy();
        return;
      }
      sendJson(res, status, {
        error: status === 500 ? `Server error: ${err.message}` : err.message,
      });
    });
  });
  server.on("error", (err) => {
    if (err.code === "EADDRINUSE") console.error(`Port ${PORT} is in use. Try --port ${PORT + 1}.`);
    else console.error(err.message);
    process.exit(1);
  });
  server.listen(PORT, "127.0.0.1", () => {
    console.log(`Scan browser: http://127.0.0.1:${PORT}/`);
    console.log(`Data folder:  ${DATA}`);
  });
}

const invokedPath = process.argv[1] ? pathToFileURL(path.resolve(process.argv[1])).href : "";
if (invokedPath === import.meta.url) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}

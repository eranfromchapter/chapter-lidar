#!/usr/bin/env node
// Scan browser: a small local web app for field testing. It lists the visits the Chapter Capture
// field-test build wrote on the iPhone and shows every file of every scan: raw originals, the
// latest "Package ready" exports, photos, field controls, the source register, sealed packages
// and their upload state, and each scan's Chapter Floorplan rendered now with the current app code
// (tools/plan-render, a Swift tool it builds on first need). "Sync from iPhone" copies the visits
// off a connected phone.
//
// Testing tool only. Node built-ins only, no build step for the page. It binds 127.0.0.1, answers
// only requests addressed to 127.0.0.1 or localhost, and serves files only from inside the data
// folder, besides the page itself, the Chapter brand files and its own cache entries.
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
/** Chapter logo and Inter fonts, shared with the web app. */
const BRAND_DIR = path.join(REPO_ROOT, "web", "public", "brand");
/** The Floorplan renderer (a SwiftPM package) and the binary `swift build` makes. */
const PLAN_RENDER_DIR = path.join(REPO_ROOT, "tools", "plan-render");
const PLAN_RENDER_BIN = path.join(PLAN_RENDER_DIR, ".build", "release", "plan-render");
/** What plan-render is built from: a file newer than the binary means a rebuild. */
const PLAN_RENDER_SOURCES = [
  "tools/plan-render/Package.swift",
  "tools/plan-render/Sources",
  "ios/Packages/PlanExport/Package.swift",
  "ios/Packages/PlanExport/Sources",
  "ios/Packages/CaptureCore/Package.swift",
  "ios/Packages/CaptureCore/Sources/CaptureModelMapping",
  "contract/swift/Package.swift",
  "contract/swift/Sources",
].map((rel) => path.join(REPO_ROOT, ...rel.split("/")));
const BUILD_TIMEOUT_MS = 20 * 60 * 1000;
const RENDER_TIMEOUT_MS = 2 * 60 * 1000;
const FLOORPLAN_INPUT_MAX_BYTES = 64 * 1024 * 1024;
/** Cached floor plans older than this are removed when a new one is written. */
const FLOORPLAN_CACHE_DAYS = 30;
const FLOORPLAN_FILES = ["floorplan.png", "floorplan.pdf", "floorplan.svg"];

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

/**
 * The 3D viewer, the only script loaded from elsewhere. The CSP allows this one file (not the
 * whole CDN, which serves any npm package), and the page loads it with an SRI hash (app.js).
 */
const MODEL_VIEWER_URL =
  "https://cdn.jsdelivr.net/npm/@google/model-viewer@3.5.0/dist/model-viewer.min.js";

/** The page itself. */
const PAGE_CSP = [
  "default-src 'self'",
  `script-src 'self' ${MODEL_VIEWER_URL}`,
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

/** Every regular file and real folder under root (symlinks are listed, never followed). */
async function walkFiles(root) {
  const files = [];
  const dirs = [];
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
        dirs.push(rel);
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
  return { files, dirs, symlinks };
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

// Counts keyed by values from the files (phase, role) are kept in Maps and turned into objects
// with Object.fromEntries, which defines own properties: a value such as "__proto__" or
// "constructor" is then just another key and never reaches Object.prototype.

function summarizeUploadState(value) {
  const files = Array.isArray(value?.files) ? value.files : [];
  const phases = new Map();
  let rejected = 0;
  for (const f of files) {
    const phase = typeof f?.phase === "string" ? f.phase : "unknown";
    phases.set(phase, (phases.get(phase) ?? 0) + 1);
    rejected += Number.isFinite(f?.rejectedUploads) ? f.rejectedUploads : 0;
  }
  const verified = phases.get("verified") ?? 0;
  const sealStatus = typeof value?.sealResult?.status === "string" ? value.sealResult.status : null;
  return {
    packageId: value?.packageId ?? null,
    dealId: value?.dealId ?? null,
    files: files.length,
    phases: Object.fromEntries(phases),
    verified,
    rejected,
    sealStatus,
    confirmed:
      files.length > 0 && verified === files.length && !!sealStatus && sealStatus !== "uploading",
  };
}

function summarizeManifest(value) {
  const files = Array.isArray(value?.files) ? value.files : [];
  const roles = new Map();
  let bytes = 0;
  for (const f of files) {
    const role = typeof f?.role === "string" ? f.role : "unknown";
    if (!roles.has(role)) roles.set(role, { files: 0, bytes: 0 });
    const r = roles.get(role);
    r.files += 1;
    r.bytes += Number.isFinite(f?.bytes) ? f.bytes : 0;
    bytes += Number.isFinite(f?.bytes) ? f.bytes : 0;
  }
  return {
    packageId: value?.packageId ?? null,
    visitId: value?.visitId ?? null,
    revision: value?.revision ?? null,
    sealedAt: value?.sealedAt ?? null,
    files: files.length,
    bytes,
    roles: Object.fromEntries(roles),
  };
}

/** Walks one visit folder and sorts every file into the VisitWorkspace layout. */
async function analyzeVisit(visitRel) {
  const { abs } = await resolveDataPath(visitRel, "dir");
  const { files, dirs, symlinks } = await walkFiles(abs);
  const captures = new Map();
  const capture = (areaKey, captureId) => {
    const key = `${areaKey}/${captureId}`;
    if (!captures.has(key)) {
      captures.set(key, {
        key,
        areaKey,
        captureId,
        raw: [],
        photoFiles: [],
        drafts: new Map(),
        packages: new Map(),
      });
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

  // A file under {areaKey}/{captureId}/ may sit in a subfolder (layout.json: mesh companions), so
  // the depths below are minimums; such files keep the rest of their path as their label.
  for (const f of files) {
    const p = f.parts;
    const n = p.length;
    if (p[0] === "originals" && p[1] === "Original Exports" && n >= 5) {
      capture(p[2], p[3]).raw.push(f);
    } else if (p[0] === "photos" && n === 2 && p[1] === "photo-records.json") {
      photoRecordsFile = f;
    } else if (p[0] === "photos" && p[1] === "Site Photos" && n >= 5) {
      capture(p[2], p[3]).photoFiles.push(f);
    } else if (p[0] === "controls" && p[1] === "Field Measurements" && n === 4) {
      controls.push(f);
    } else if (p[0] === "drafts" && n >= 3) {
      const d = draft(p[1]);
      d.files.push(f);
      if (p[2] === "Original Exports" && n >= 6) {
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
      if (p[2] === "Original Exports" && n >= 6) {
        const c = capture(p[3], p[4]);
        if (!c.packages.has(k.id)) c.packages.set(k.id, []);
        c.packages.get(k.id).push(f);
      }
    } else {
      other.push(f);
    }
  }

  // A sealed package folder copied without its files (read-only on the phone) still counts. The
  // folders come from the walk, so a symlinked packages folder is never read.
  for (const parts of dirs) {
    if (parts.length === 2 && parts[0] === "packages") pkg(parts[1]);
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

  // A capture named by the capture record or a photo record is shown even when none of its files
  // were copied (a partial copy), so its photo records still appear, as "File missing".
  const isId = (v) => typeof v === "string" && v.length > 0 && v.length <= 512;
  const known = new Set([...captures.values()].map((c) => c.captureId));
  for (const r of [...recordCaptures(record), ...photoRecords]) {
    if (!isId(r.captureId) || known.has(r.captureId)) continue;
    const fromPath = typeof r.path === "string" ? r.path.split("/") : [];
    const areaKey = isId(r.areaKey)
      ? r.areaKey
      : fromPath[0] === "Site Photos" && isId(fromPath[1])
        ? fromPath[1]
        : "unknown";
    capture(areaKey, r.captureId);
    known.add(r.captureId);
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

  // A capture's file is labelled by its path below {areaKey}/{captureId}/: that folder is 4 parts
  // deep in originals and photos, 5 in drafts and packages.
  const captureFile = (depth) => (f) => info(f, { label: f.parts.slice(depth).join("/") });

  // Which app build wrote each draft and package (shown with its exports and Floorplan source).
  await readApps(a);
  const captures = captureList.map((c) => {
    const rec = recordCaps.find((r) => r.captureId === c.captureId) ?? null;
    const exportsList = a.drafts
      .filter((d) => c.drafts.has(d.id))
      .map((d) => ({
        source: "draft",
        draftId: d.id,
        builtAt: iso(d.builtMs),
        latest: d === a.latestDraft,
        app: d.app,
        files: c.drafts.get(d.id).map(captureFile(5)),
      }));
    // No draft has this capture (drafts/ missing from a partial copy, say): the newest sealed
    // package that has it holds the same exports.
    const sealed = a.packages.find((k) => c.packages.has(k.id)) ?? null;
    const sealedAt = sealed?.manifest?.sealedAt;
    const fromPackage = sealed
      ? {
          source: "package",
          packageId: sealed.id,
          sealedAt: typeof sealedAt === "string" ? sealedAt : null,
          app: sealed.app,
          files: c.packages.get(sealed.id).map(captureFile(5)),
        }
      : null;
    const exports = exportsList[0] ?? fromPackage;
    const model = captureModelSource(a, c);
    const sketchPath = model ? `${visitRel}/${model.file.parts.join("/")}` : null;
    const photos = c.photoFiles.map((f) => {
      const r = a.photoRecords.find((x) => x.path === photoRoot(f)) ?? null;
      return { file: captureFile(4)(f), record: r, missing: false };
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
      raw: c.raw.map(captureFile(4)),
      exports,
      olderExports: exportsList.slice(1),
      photos,
      sketchPath,
      floorplan: { sources: floorplanSources(a, c), options: floorplanOptions(a, c) },
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
    // fromEntries: a "__proto__" key from the file stays an own key (see summarizeUploadState).
    return Object.fromEntries(
      Object.entries(value).map(([key, v]) => [
        key,
        key === "target" && v !== null ? "[hidden: upload target]" : redactUploadState(v),
      ]),
    );
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

/** Runs at most `limit` tasks at a time; a finished task hands its slot to the next waiting one. */
function slotLimiter(limit) {
  let running = 0;
  const queue = [];
  return async (task) => {
    if (running >= limit) await new Promise((resolve) => queue.push(resolve));
    else running += 1;
    try {
      return await task();
    } finally {
      const waiting = queue.shift();
      if (waiting) waiting();
      else running -= 1;
    }
  };
}

/** At most three sips at a time. */
const withSipsSlot = slotLimiter(3);

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
// Floorplan: the one-page Chapter Floorplan of a capture (PlanExport's FloorplanWriter, the page
// the phone shows), rendered now with the current app code by tools/plan-render. The renderer is
// built with `swift build` on first need, and again when its Swift sources are newer than the
// binary: one build at a time, never while a render runs. Pages are cached in
// <cache>/floorplans/<key>/ (owner-only folders), keyed by the SHA-256 of the input bytes, the
// options and the renderer version (the binary's mtime and size), so a new build draws afresh.

/** Folder of cached floor plans. Set by main(). */
let FLOORPLANS = "";
const FLOORPLAN_KEY_RE = /^[0-9a-f]{64}$/;
const FLOORPLAN_TMP_RE = /^\.[0-9a-f]{64}\.[0-9a-f]{8}$/;

/** The renderer: idle (not looked at yet), building, ready (with its version) or error. */
const planRenderer = { status: "idle", message: "", version: null, builtFrom: 0 };
/** Renders running, by cache key. */
const floorplanJobs = new Map();
/** Renders that failed, by cache key: the reason, until a page asks afresh. */
const floorplanErrors = new Map();
/** Cache entries this server wrote or checked (key to download name): the only ones it serves. */
const knownFloorplans = new Map();
const withRenderSlot = slotLimiter(2);

const atDepth = (name, depth) => (f) => f.parts.length === depth && f.parts[depth - 1] === name;
const shortId = (id) => String(id).slice(0, 8);

/**
 * Sets `app` on each draft and sealed package of an analysed visit: the app version and build
 * from its capture record (the app build that wrote it), or null.
 */
async function readApps(a) {
  const text = (v) => (typeof v === "string" || typeof v === "number" ? String(v) : null);
  for (const x of [...a.drafts, ...a.packages]) {
    x.app = null;
    if (!x.recordFile) continue;
    const app = (await readJson(path.join(a.abs, ...x.recordFile.parts))).value?.app;
    if (app && typeof app === "object")
      x.app = { version: text(app.version), build: text(app.build) };
  }
}

const appText = (app) => `app ${app.version ?? "?"}, build ${app.build ?? "?"}`;

/**
 * The capture-model.json of a capture, as the room sketch draws it: from the latest draft that
 * has the capture, else from the newest sealed package that has one.
 */
function captureModelSource(a, c) {
  const isModel = atDepth("capture-model.json", 6);
  const draft = a.drafts.find((d) => c.drafts.has(d.id));
  const fromDraft = draft ? c.drafts.get(draft.id).find(isModel) : null;
  if (fromDraft) return { file: fromDraft, draftId: draft.id, app: draft.app };
  for (const k of a.packages) {
    const f = c.packages.get(k.id)?.find(isModel);
    if (f) return { file: f, packageId: k.id, app: k.app };
  }
  return null;
}

/** The raw RoomPlan capture: from the originals, else from the newest sealed package. */
function roomplanSource(a, c) {
  const raw = c.raw.find(atDepth("roomplan.json", 5));
  if (raw) return { file: raw };
  for (const k of a.packages) {
    const f = c.packages.get(k.id)?.find(atDepth("roomplan.json", 6));
    if (f) return { file: f, packageId: k.id };
  }
  return null;
}

/**
 * What a capture's Floorplan can be drawn from, preferred first: the capture model of the latest
 * draft (it has the operator's room labels), then the raw scan, mapped with the current code as
 * the phone's scan viewer maps it. Needs readApps(a) first.
 */
function floorplanSources(a, c) {
  const rel = (f) => `${a.visitRel}/${f.parts.join("/")}`;
  const out = [];
  const model = captureModelSource(a, c);
  if (model) {
    const app = model.app;
    const where = model.draftId
      ? `draft ${shortId(model.draftId)}`
      : `sealed package ${shortId(model.packageId)}`;
    out.push({
      id: "model",
      label: "Capture model (package)",
      path: rel(model.file),
      detail: `capture-model.json of ${where}${app ? `, mapped on the phone by ${appText(app)}` : ""}`,
    });
  }
  const raw = roomplanSource(a, c);
  if (raw) {
    const where = raw.packageId ? `sealed package ${shortId(raw.packageId)}` : "the originals";
    out.push({
      id: "roomplan",
      label: "Raw scan (as on the phone)",
      path: rel(raw.file),
      detail: `roomplan.json of ${where}, mapped now with the current code (as the phone's scan viewer does)`,
    });
  }
  return out;
}

/** Address and units as the capture record gives them (imperial when it does not say). */
function floorplanOptions(a, c) {
  const rec = recordCaptures(a.record).find((r) => r.captureId === c.captureId);
  const formatted = a.record?.address?.formatted;
  const address = typeof formatted === "string" ? formatted.trim().slice(0, 300) : "";
  return {
    title: "Floorplan",
    address: address || null,
    units: rec?.units?.display === "metric" ? "metric" : "imperial",
  };
}

/** Newest modification time of a file, or of a folder and everything in it. */
async function newestMtime(p, depth = 0) {
  let st;
  try {
    st = await fsp.lstat(p);
  } catch {
    return 0;
  }
  if (!st.isDirectory() || depth > 12) return st.mtimeMs;
  // The folder's own time counts too: a deleted file shows only there.
  let newestMs = st.mtimeMs;
  for (const entry of await readdirSafe(p)) {
    if (entry.name.startsWith(".")) continue;
    newestMs = Math.max(newestMs, await newestMtime(path.join(p, entry.name), depth + 1));
  }
  return newestMs;
}

async function newestRendererSource() {
  return Math.max(0, ...(await Promise.all(PLAN_RENDER_SOURCES.map((p) => newestMtime(p)))));
}

/** The renderer version in cache keys: the binary's modified time and size. */
const rendererVersion = (bin) => `${Math.round(bin.mtimeMs)}-${bin.size}`;

/**
 * The useful lines of a failed `swift build`: the compiler's errors (file:line:column), else any
 * error line, else its last lines. The compiler colours its output even into a pipe.
 */
function buildError(r) {
  const lines = `${r.stderr}\n${r.stdout}`
    // eslint-disable-next-line no-control-regex
    .replace(/\x1b\[[0-9;]*m/g, "")
    .split("\n")
    .map((l) => l.trim())
    .filter(Boolean);
  const diagnostics = lines.filter((l) => /:\d+:\d+: error:/.test(l));
  const errors = diagnostics.length ? diagnostics : lines.filter((l) => /\berror:/.test(l));
  return (errors.length ? errors.slice(0, 6) : lines.slice(-6))
    .map((l) => l.replaceAll(REPO_ROOT + path.sep, ""))
    .join("\n")
    .slice(0, 2000);
}

function startRendererBuild() {
  const r = planRenderer;
  if (r.status === "building") return;
  r.status = "building";
  r.message =
    "Building the floor plan renderer (swift build of tools/plan-render); the first build takes a minute or two.";
  r.version = null;
  const started = Date.now();
  console.log("[floorplan] building tools/plan-render…");
  (async () => {
    const sourcesMs = await newestRendererSource();
    // Never replace the binary under a running render.
    await Promise.allSettled([...floorplanJobs.values()]);
    const b = await run("swift", ["build", "-c", "release", "--package-path", PLAN_RENDER_DIR], {
      env: xcodeEnv(["Xcode.app", "Xcode-beta.app"]),
      timeoutMs: BUILD_TIMEOUT_MS,
    });
    if (b.error?.code === "ENOENT") {
      throw new Error(
        "Swift was not found. The Floorplan is drawn by a small Swift tool: install Xcode (or set DEVELOPER_DIR to its Contents/Developer folder) and reload.",
      );
    }
    if (b.error?.killed) {
      throw new Error(`swift build did not finish within ${BUILD_TIMEOUT_MS / 60000} minutes.`);
    }
    if (b.code !== 0) throw new Error(`swift build of tools/plan-render failed:\n${buildError(b)}`);
    r.version = rendererVersion(await fsp.stat(PLAN_RENDER_BIN));
    r.builtFrom = sourcesMs;
  })()
    .then(() => {
      r.status = "ready";
      r.message = "";
      console.log(
        `[floorplan] plan-render built in ${Math.round((Date.now() - started) / 1000)} s`,
      );
    })
    .catch((err) => {
      r.status = "error";
      r.message = err.message;
      r.version = null;
      console.error(`[floorplan] ${err.message}`);
    });
}

/**
 * The renderer's state. `check` (a page asking afresh) builds it when the binary is missing or
 * older than its sources, and retries a failed build; polls just read the state.
 */
async function rendererState(check) {
  const r = planRenderer;
  if (r.status === "building" || (r.status !== "idle" && !check)) return r;
  // The binary's version when it is there and newer than every source, else null.
  let version = null;
  try {
    const bin = await fsp.stat(PLAN_RENDER_BIN);
    if ((await newestRendererSource()) <= Math.max(bin.mtimeMs, r.builtFrom)) {
      version = rendererVersion(bin);
    }
  } catch {
    // No binary yet.
  }
  if (r.status === "building") return r; // Started by another request meanwhile.
  if (version === null) {
    startRendererBuild();
  } else {
    r.version = version;
    r.status = "ready";
    r.message = "";
  }
  return r;
}

function floorplanKey(bytes, source, options, version) {
  return createHash("sha256")
    .update(
      `scan-browser floorplan 1\0${path.basename(source.path)}\0${JSON.stringify(options)}\0${version}\0`,
    )
    .update(bytes)
    .digest("hex");
}

/** A complete cache entry (result.json and the three files, no symlinks), or null. */
async function cachedFloorplan(key) {
  if (!FLOORPLAN_KEY_RE.test(key)) return null;
  const dir = path.join(FLOORPLANS, key);
  try {
    if (!(await fsp.lstat(dir)).isDirectory()) return null;
    for (const name of FLOORPLAN_FILES) {
      if (!(await fsp.lstat(path.join(dir, name))).isFile()) return null;
    }
    const result = JSON.parse(await fsp.readFile(path.join(dir, "result.json"), "utf8"));
    const name =
      typeof result?.downloadName === "string" && /^[\w.-]{1,100}$/.test(result.downloadName)
        ? result.downloadName
        : "floorplan";
    knownFloorplans.set(key, name);
    return result;
  } catch {
    return null;
  }
}

/** The useful line of a failed plan-render (it writes one line to stderr). */
function renderError(r) {
  if (r.error?.killed) return `plan-render did not finish within ${RENDER_TIMEOUT_MS / 1000} s.`;
  const line = `${r.stderr}\n${r.stdout}`
    .split("\n")
    .map((l) => l.trim())
    .filter(Boolean)
    .at(-1);
  return (line ?? `plan-render failed (exit code ${r.code}).`).replace(/^plan-render: /, "");
}

async function renderFloorplan({ key, bytes, source, options, version, downloadName }) {
  const tmp = path.join(FLOORPLANS, `.${key}.${randomBytes(4).toString("hex")}`);
  await fsp.mkdir(tmp, { mode: 0o700 });
  try {
    // The exact bytes the key was made from (a sync may be rewriting the original), removed
    // again once drawn.
    const inputDir = path.join(tmp, "input");
    const input = path.join(inputDir, path.basename(source.path));
    await fsp.mkdir(inputDir, { mode: 0o700 });
    await fsp.writeFile(input, bytes, { mode: 0o600 });
    const args = [input, tmp, "--units", options.units, "--title", options.title];
    if (options.address) args.push("--address", options.address);
    const r = await withRenderSlot(() =>
      run(PLAN_RENDER_BIN, args, { timeoutMs: RENDER_TIMEOUT_MS }),
    );
    await fsp.rm(inputDir, { recursive: true, force: true });
    if (r.code !== 0) throw new Error(renderError(r));
    let summary = null;
    try {
      summary = JSON.parse(r.stdout.trim().split("\n").at(-1));
    } catch {
      // Drawn, without a summary: the page is still shown.
    }
    const result = {
      summary,
      source,
      options,
      rendererVersion: version,
      renderedAt: new Date().toISOString(),
      downloadName,
    };
    await fsp.writeFile(path.join(tmp, "result.json"), JSON.stringify(result), { mode: 0o600 });
    try {
      await fsp.rename(tmp, path.join(FLOORPLANS, key));
    } catch (err) {
      // Another render of the same input finished first.
      if (!(await cachedFloorplan(key))) throw err;
    }
  } finally {
    await fsp.rm(tmp, { recursive: true, force: true }).catch(() => {});
  }
}

/** Removes cache entries older than FLOORPLAN_CACHE_DAYS and leftovers of interrupted renders. */
async function pruneFloorplans() {
  const now = Date.now();
  for (const entry of await readdirSafe(FLOORPLANS)) {
    const isTmp = FLOORPLAN_TMP_RE.test(entry.name);
    if (!isTmp && !FLOORPLAN_KEY_RE.test(entry.name)) continue; // Not written by this server.
    try {
      const age = now - (await fsp.lstat(path.join(FLOORPLANS, entry.name))).mtimeMs;
      if (age > (isTmp ? 3600 * 1000 : FLOORPLAN_CACHE_DAYS * 86400 * 1000)) {
        await fsp.rm(path.join(FLOORPLANS, entry.name), { recursive: true, force: true });
        knownFloorplans.delete(entry.name);
      }
    } catch {
      // Gone already.
    }
  }
}

/**
 * GET /api/floorplan?visit=<visit>&capture=<areaKey/captureId>[&source=model|roomplan][&start=1]:
 * the state of that capture's Floorplan (building, rendering, ready or error). The page asks
 * with start=1 when it opens and then polls; the input file and the options come from the
 * server's own reading of the visit, never from the request.
 */
async function floorplanStatus(url) {
  const wanted = url.searchParams.get("source");
  if (wanted !== null && wanted !== "model" && wanted !== "roomplan") {
    throw fail(400, "Unknown floor plan source.");
  }
  const start = url.searchParams.get("start") === "1";
  const a = await analyzeVisit(url.searchParams.get("visit"));
  const c = a.captures.get(url.searchParams.get("capture") ?? "");
  if (!c) throw fail(404, "This capture is not in the visit.");
  await readApps(a);
  const sources = floorplanSources(a, c);
  const source = wanted === null ? sources[0] : sources.find((x) => x.id === wanted);
  if (!source) {
    throw fail(404, "This capture has no roomplan.json or capture-model.json to draw from.");
  }
  const options = floorplanOptions(a, c);
  const reply = (status, extra) => ({ status, source, options, ...extra });

  const r = await rendererState(start);
  if (r.status === "building") return reply("building", { message: r.message });
  if (r.status === "error") return reply("error", { message: r.message });
  const { abs, stat } = await resolveDataPath(source.path, "file");
  if (stat.size > FLOORPLAN_INPUT_MAX_BYTES) {
    return reply("error", {
      message: `${path.basename(abs)} is too large (${fmtBytes(stat.size)}).`,
    });
  }
  const bytes = await fsp.readFile(abs);
  const key = floorplanKey(bytes, source, options, r.version);
  const cached = await cachedFloorplan(key);
  if (cached) {
    // Used again: kept from pruning for another FLOORPLAN_CACHE_DAYS.
    const now = new Date();
    await fsp.utimes(path.join(FLOORPLANS, key), now, now).catch(() => {});
    return reply("ready", {
      key,
      summary: cached.summary ?? null,
      renderedAt: cached.renderedAt ?? null,
    });
  }
  if (floorplanErrors.has(key) && !start) {
    return reply("error", { message: floorplanErrors.get(key) });
  }
  if (!floorplanJobs.has(key)) {
    floorplanErrors.delete(key);
    const downloadName = `floorplan-${c.areaKey}-${shortId(c.captureId)}`
      .replace(/[^\w.-]+/g, "_")
      .slice(0, 100);
    const job = renderFloorplan({ key, bytes, source, options, version: r.version, downloadName })
      .then(() => pruneFloorplans())
      .catch((err) => {
        floorplanErrors.set(key, err.message);
        console.error(`[floorplan] ${source.path}: ${err.message}`);
      })
      .finally(() => floorplanJobs.delete(key));
    floorplanJobs.set(key, job);
  }
  return reply("rendering", { message: "Rendering floor plan…" });
}

/** GET /api/floorplan-file?key=<sha256>&name=floorplan.png|pdf|svg[&download=1]. */
async function serveFloorplanFile(req, res, url) {
  const key = url.searchParams.get("key") ?? "";
  const name = url.searchParams.get("name") ?? "";
  if (!FLOORPLAN_KEY_RE.test(key) || !FLOORPLAN_FILES.includes(name)) {
    throw fail(400, "Invalid floor plan file.");
  }
  // Only entries this server wrote or checked: never any other path in the cache.
  if (!knownFloorplans.has(key)) throw fail(404, "No such floor plan (reload the visit).");
  const dir = path.join(FLOORPLANS, key);
  const abs = path.join(dir, name);
  let stat;
  try {
    if (!(await fsp.lstat(dir)).isDirectory()) throw new Error("not a folder");
    stat = await fsp.lstat(abs);
  } catch {
    throw fail(404, "No such floor plan (reload the visit).");
  }
  if (!stat.isFile()) throw fail(404, "No such floor plan.");
  const download = url.searchParams.get("download") === "1";
  const type = FILE_TYPES[path.extname(name)];
  res.writeHead(200, {
    ...SECURITY_HEADERS,
    "Content-Type": type,
    "Content-Length": String(stat.size),
    "Content-Security-Policy": type === "application/pdf" && !download ? PDF_CSP : FILE_CSP,
    "Content-Disposition": contentDisposition(
      download ? "attachment" : "inline",
      `${knownFloorplans.get(key)}${path.extname(name)}`,
    ),
    // A key names one page for good.
    "Cache-Control": "private, max-age=86400",
  });
  if (req.method === "HEAD") {
    res.end();
    return;
  }
  const stream = createReadStream(abs);
  stream.on("error", () => res.destroy());
  stream.pipe(res);
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

/** DEVELOPER_DIR when set, else the first of these Xcodes in /Applications that is installed. */
function xcodeEnv(apps) {
  if (process.env.DEVELOPER_DIR) return process.env;
  for (const app of apps) {
    const dir = path.join("/Applications", app, "Contents", "Developer");
    if (existsSync(dir)) return { ...process.env, DEVELOPER_DIR: dir };
  }
  return process.env;
}

const devicectlEnv = () => xcodeEnv(["Xcode-beta.app", "Xcode.app"]);

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

/**
 * Creates a folder chain inside DATA. New folders are owner-only (0700): they hold photos and
 * plans of real homes. Folders copied read-only by hand are made owner-writable. A symlink or a
 * file in the way fails; the error's `dir` is the folder that failed.
 */
async function ensureWritableDir(dir) {
  let current = DATA;
  try {
    for (const part of path.relative(DATA, dir).split(path.sep).filter(Boolean)) {
      current = path.join(current, part);
      try {
        await fsp.mkdir(current, { mode: 0o700 });
        continue; // Made just now: a real folder.
      } catch (err) {
        if (err.code !== "EEXIST") throw err;
      }
      const st = await fsp.lstat(current);
      if (st.isSymbolicLink() || !st.isDirectory())
        throw new Error(`${path.relative(DATA, current)} is not a folder`);
      if ((st.mode & 0o700) !== 0o700) await fsp.chmod(current, (st.mode & 0o7777) | 0o700);
    }
  } catch (err) {
    err.dir = current;
    throw err;
  }
}

/**
 * True when every component from DATA down to dir is a real folder (no symlink, nothing missing).
 * Checked right before sync writes into a folder or sets its time, so a symlink inside the data
 * folder can never send a write outside it: sync refuses symlinks just as the read side does.
 */
async function isRealDirInsideData(dir) {
  if (dir !== DATA && !isInsideData(dir)) return false;
  let current = DATA;
  for (const part of path.relative(DATA, dir).split(path.sep).filter(Boolean)) {
    current = path.join(current, part);
    try {
      const st = await fsp.lstat(current);
      if (st.isSymbolicLink() || !st.isDirectory()) return false;
    } catch {
      return false;
    }
  }
  return true;
}

const isUnder = (p, dir) => p === dir || p.startsWith(dir + path.sep);

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
    const files = [];
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
      } else {
        dirs.add(path.dirname(local));
        files.push({ ...item, local });
      }
    }
    // A folder that cannot be made (a symlink or a file is in the way) takes every file under it
    // out of the copy, so nothing is written through a symlink.
    const badDirs = [];
    for (const dir of [...dirs].sort()) {
      if (badDirs.some((bad) => isUnder(dir, bad))) continue; // Reported with its parent.
      try {
        await ensureWritableDir(dir);
      } catch (err) {
        const bad = err.dir ?? dir;
        badDirs.push(bad);
        s.failures.push({
          path: path.relative(DATA, bad),
          error: `Folder could not be created: ${err.message}`,
        });
      }
    }
    const queue = [];
    for (const item of files) {
      const bad = badDirs.find((dir) => isUnder(item.local, dir));
      if (bad) {
        s.failures.push({
          path: item.rel,
          error: `Not copied: its folder ${path.relative(DATA, bad)} could not be created.`,
        });
        continue;
      }
      try {
        const st = await fsp.lstat(item.local);
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
      queue.push(item);
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
        if (!(await isRealDirInsideData(path.dirname(item.local)))) {
          // A symlink appeared in the folder chain after it was made: never write through it.
          s.failures.push({
            path: item.rel,
            error: "Not copied: its folder in the data folder is a symbolic link or is missing.",
          });
          s.done += 1;
          s.doneBytes += item.size;
          continue;
        }
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
            await fsp.lutimes(item.local, new Date(), new Date(item.mtimeMs)).catch(() => {});
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
    // Only real folders: a symlink anywhere in the chain is skipped, as it is for files.
    for (const item of remoteDirs) {
      try {
        const local = localPathFor(item.rel);
        if (!(await isRealDirInsideData(local))) continue; // Not created (already reported).
        await fsp.lutimes(local, new Date(), new Date(item.mtimeMs));
      } catch {
        // Not settable: the time is only informational.
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

// The page, and the Chapter logo and Inter fonts read in place from the web app's brand folder
// (web/public/brand, generated by tools/brand): the only files served from outside the data folder
// besides the cache's own floor plans and photos.
const STATIC_FILES = {
  "/": [path.join(PUBLIC_DIR, "index.html"), "text/html; charset=utf-8"],
  "/index.html": [path.join(PUBLIC_DIR, "index.html"), "text/html; charset=utf-8"],
  "/app.js": [path.join(PUBLIC_DIR, "app.js"), "text/javascript; charset=utf-8"],
  "/styles.css": [path.join(PUBLIC_DIR, "styles.css"), "text/css; charset=utf-8"],
  "/brand/chapter-logo.svg": [path.join(BRAND_DIR, "chapter-logo.svg"), "image/svg+xml"],
  "/brand/inter-400.woff2": [path.join(BRAND_DIR, "inter-400.woff2"), "font/woff2"],
  "/brand/inter-600.woff2": [path.join(BRAND_DIR, "inter-600.woff2"), "font/woff2"],
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
  let body;
  try {
    body = await fsp.readFile(file);
  } catch (err) {
    if (err.code === "ENOENT") throw fail(404, `${pathname} is missing from this checkout.`);
    throw err;
  }
  const headers = { "Content-Type": type };
  if (path.basename(file) === "index.html") headers["Content-Security-Policy"] = PAGE_CSP;
  // The logo is shown with <img>; opened on its own it still cannot run anything.
  if (type === "image/svg+xml") headers["Content-Security-Policy"] = FILE_CSP;
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
  if (pathname === "/api/floorplan") return sendJson(res, 200, await floorplanStatus(url));
  if (pathname === "/api/floorplan-file") return serveFloorplanFile(req, res, url);
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
  // Owner-only (0700), like every folder sync makes: on macOS every standard account is in the
  // staff group, so a 0755 folder would let other accounts on the Mac read the photos and plans.
  // A folder that already exists is left as it is, with a note when others can open it.
  const created = await fsp.mkdir(config.dataDir, { recursive: true, mode: 0o700 });
  DATA = await fsp.realpath(config.dataDir);
  if (insideRepo(DATA)) refuse(DATA);
  if (created !== undefined) await fsp.chmod(DATA, 0o700);
  const dataMode = (await fsp.stat(DATA)).mode & 0o777;
  CACHE = cacheRoot();
  await fsp.mkdir(CACHE, { recursive: true, mode: 0o700 });
  // Floor plans of real homes: an owner-only folder, made so again if it was opened up.
  FLOORPLANS = path.join(CACHE, "floorplans");
  await fsp.mkdir(FLOORPLANS, { recursive: true, mode: 0o700 });
  const floorplansStat = await fsp.lstat(FLOORPLANS);
  if (floorplansStat.isSymbolicLink() || !floorplansStat.isDirectory()) {
    console.error(`${FLOORPLANS} is not a folder; remove it and start again.`);
    process.exit(2);
  }
  if (floorplansStat.mode & 0o077) await fsp.chmod(FLOORPLANS, 0o700);
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
    if (dataMode & 0o077) {
      console.warn(
        `Note: other accounts on this Mac can open the data folder (mode ${dataMode.toString(8)}). To keep the scans private: chmod 700 "${DATA}"`,
      );
    }
  });
}

const invokedPath = process.argv[1] ? pathToFileURL(path.resolve(process.argv[1])).href : "";
if (invokedPath === import.meta.url) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}

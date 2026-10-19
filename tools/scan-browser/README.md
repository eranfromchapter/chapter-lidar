# Scan browser

A small local web app for field testing. It shows every file the Chapter Capture field-test build
wrote for each scan, and copies them off a connected iPhone.

Testing tool only: it is not part of the app, the station or the package contract.

## Run

```sh
npm run scan-browser                          # data folder ~/ChapterCaptureScans, port 4321
npm run scan-browser -- --data ~/some/folder  # another data folder
npm run scan-browser -- --port 4322
SCAN_BROWSER_DATA=~/some/folder npm run scan-browser
```

Then open <http://127.0.0.1:4321/>. Node 22, no dependencies, no build step.

The data folder must be outside this repository (the server refuses to start otherwise): it holds
photos and floor plans of real homes.

## What it shows

**Visits** (newest first): date (`visitedAt` from the capture record, else the newest file),
operator, project, deal and address, areas, file counts and a status: _scanned_ (raw originals),
_package built_ (a `drafts/` build), _sealed_ (`packages/`) and the upload state of each sealed
package (files verified, station status).

**Visit page**, per capture (area label, area key and capture id):

- **Room sketch**: a top-down SVG of `capture-model.json` from the latest draft (rooms with labels
  and areas in m² and ft², walls, doors, windows and openings). Plan axes are x and z; plan up is
  −z. Hover an element for its id and size. Nothing is drawn before the first export.
- **Raw scan (originals)**: `roomplan.json`, `depth-samples.bin`, `camera-poses.json`,
  `mesh-anchors.bin`.
- **Exports** from the latest draft that has this capture (the draft id and build time are shown;
  older drafts are listed below it).
- **Photos** with room, direction and subject from `photo-records.json`. HEIC is converted to JPEG
  on the fly with macOS `sips`, cached in `~/Library/Caches/ChapterScanBrowser`.

Visit-wide: field controls, source register (capture record), photo records, sealed packages (each
file with its manifest role and upload phase, plus the manifest and upload state), all drafts, and
any file outside the expected layout.

Every file has its size, modified time, Open, Download and a Preview:

| File                       | Preview                                                           |
| -------------------------- | ----------------------------------------------------------------- |
| PDF                        | the browser's PDF viewer                                          |
| PNG, SVG                   | an image (`<img>`, so an SVG cannot run scripts)                  |
| HEIC                       | JPEG converted by `sips`                                          |
| JSON                       | collapsible tree with a summary (top-level arrays, capture model) |
| `camera-poses.json`        | frames, duration, intrinsics, camera path and bounds              |
| `*.upload-state.json`      | phases and station status; upload targets (SAS URLs) are hidden   |
| `manifest.json`            | files per role, sizes, sealed time                                |
| CSV                        | a table                                                           |
| GLB                        | `@google/model-viewer` 3.5.0, loaded from jsDelivr only on demand |
| OBJ, MTL, DXF              | the first 64 KB as text                                           |
| LAS                        | header: version, point format, point count, scale, offset, bounds |
| `depth-samples.bin` (CHDS) | sample count, size check, bounds, confidence and colour counts    |
| `mesh-anchors.bin` (CHMA)  | anchors, vertices, triangles, world bounds, size check            |

## Sync from iPhone

The button finds a connected iPhone with `xcrun devicectl list devices` (simulators are ignored),
lists `Library/Application Support/FieldTestVisits` in the app container of
`com.hellochapter.capture`, and copies every file that is new or changed (size or modified time)
into the data folder, file by file, four at a time. The data folder is an incremental mirror of
`FieldTestVisits`: nothing is ever deleted, and files keep the phone's modified times.

Copying file by file is what makes sealed packages work: they are read-only on the phone, so a
single `devicectl device copy from` of the whole folder creates read-only folders that cannot take
their files ("Permission denied"). Folders copied that way by hand are made owner-writable and
filled in on the next sync. Failed files are listed with devicectl's reason; the rest still copy.

It uses `DEVELOPER_DIR` when set, else `/Applications/Xcode-beta.app`, else `/Applications/Xcode.app`.
With no phone connected, no Xcode, or the app not installed, it says so instead of failing.

## Safety

- Binds `127.0.0.1` and refuses requests whose `Host` is not `127.0.0.1:<port>` or
  `localhost:<port>` (DNS rebinding). Starting a sync needs a custom header and a same-origin
  `Origin`, so another web page cannot trigger it.
- Files are served only from inside the data folder: every path is split into segments (no `..`,
  empty or absolute segments, backslashes or NUL), resolved, and checked again after `realpath`, so
  symlinks cannot escape it. Symlinks inside visits are listed, never followed.
- The page never uses `innerHTML`: every file name, label and JSON value is set as text. A strict
  Content Security Policy allows scripts only from the server and jsDelivr (for the 3D viewer).
  Raw files are served with `X-Content-Type-Options: nosniff` and a sandbox policy (PDFs excepted,
  which the browser's viewer needs), and never as HTML.
- `devicectl` and `sips` run through `execFile` with argument arrays; no shell.
- No network calls except to the phone (devicectl) and, when a GLB is previewed, jsDelivr.

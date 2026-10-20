# Scan browser

A small local web app for field testing. It shows every file the Chapter Capture field-test build
wrote for each scan, draws each scan's Chapter Floorplan with the current app code, and copies the
files off a connected iPhone.

Testing tool only: it is not part of the app, the station or the package contract.

## What's new

- **Chapter look**: Chapter colours (ground, surface, ink, line, muted), Times for headings, Inter
  for everything else, and the Chapter logo in the header. The logo and the two Inter files are
  read in place from `web/public/brand` (served at `/brand/`); nothing is loaded from the internet.
  Status chips use the verdict tones with a word and a shape: ● ready (upload confirmed by the
  station), ▲ limited (upload not confirmed yet), ■ blocked (upload state unreadable).
- **Floorplan** per capture: the same one-page Floorplan the phone shows (PlanExport's
  `FloorplanWriter`), rendered now by `tools/plan-render` with the current code in this checkout,
  so scans whose exports were written by an older app build, or that only have originals, still
  show today's plan. See [Floorplan](#floorplan).
- **Room sketch** in the Floorplan's palette: rooms filled by room type, warm charcoal walls, bronze
  doors, grey double-line windows, labels in ink and areas in muted.
- Phone widths: file and visit tables become stacked rows.

## Run

```sh
npm run scan-browser                          # data folder ~/ChapterCaptureScans, port 4321
npm run scan-browser -- --data ~/some/folder  # another data folder
npm run scan-browser -- --port 4322
SCAN_BROWSER_DATA=~/some/folder npm run scan-browser
```

Then open <http://127.0.0.1:4321/>. Node 22, no dependencies, no build step for the page.

The Floorplan also needs Swift 6 on the Mac (Xcode 16 or later): the first visit page that shows a
Floorplan builds `tools/plan-render` with `swift build -c release` (about half a minute the first
time). It uses `DEVELOPER_DIR` when set, else `/Applications/Xcode.app`, else
`/Applications/Xcode-beta.app`. Without Swift, the rest of the page works and the Floorplan section
says what is missing.

The data folder must be outside this repository (the server refuses to start otherwise): it holds
photos and floor plans of real homes. The server creates it owner-only (`0700`), and sync creates
its folders the same way, so other accounts on the Mac cannot read them. A data folder that already
exists keeps its permissions; the server prints a note with the `chmod 700` command when other
accounts can open it.

## What it shows

**Visits** (newest first): date (`visitedAt` from the capture record, else the newest file),
operator, project, deal and address, areas, file counts and a status: _scanned_ (raw originals),
_package built_ (a `drafts/` build), _sealed_ (`packages/`) and the upload state of each sealed
package (files verified, station status).

**Visit page**, per capture (area label, area key and capture id). A capture is shown when any of
its files are present, or when the capture record or a photo record names it, so a partial copy
still lists its captures and their missing photos:

- **Floorplan (rendered now with the current app code)**: the Floorplan page as a PNG (click it
  for the PDF), with its total, room count, print scale and page, and links to open or download
  the PDF, the SVG and the PNG. See [Floorplan](#floorplan).
- **Room sketch**: a top-down SVG of `capture-model.json` from the latest draft (rooms with labels
  and areas in m² and ft², walls, doors, windows and openings), in the Floorplan's palette: rooms
  filled by type (from the label for models written before rooms had a type). Plan axes are x and
  z; plan up is −z. Hover an element for its id and size. Nothing is drawn before the first export.
- **Raw scan (originals)**: `roomplan.json`, `depth-samples.bin`, `camera-poses.json`,
  `mesh-anchors.bin`.
- **Exports** from the latest draft that has this capture (the draft id and build time are shown;
  older drafts are listed below it). When no draft has the capture (a copy without `drafts/`), the
  exports come from the newest sealed package that has them. Files in subfolders of a capture
  folder (mesh companions) are listed with their subfolder. These files were written on the phone
  by the app build that made the package (its version and build are shown when the capture record
  has them), so they show that build's plan code, not the current one.
- **Photos** with room, direction and subject from `photo-records.json`; a record whose file is
  not in the copy shows as "File missing". HEIC is converted to JPEG on the fly with macOS `sips`,
  cached in `~/Library/Caches/ChapterScanBrowser`.

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
| GLB                        | `@google/model-viewer` 3.5.0, jsDelivr, on demand, hash-pinned    |
| OBJ, MTL, DXF              | the first 64 KB as text                                           |
| LAS                        | header: version, point format, point count, scale, offset, bounds |
| `depth-samples.bin` (CHDS) | sample count, size check, bounds, confidence and colour counts    |
| `mesh-anchors.bin` (CHMA)  | anchors, vertices, triangles, world bounds, size check            |

## Floorplan

Each capture's Floorplan is drawn by `tools/plan-render`, a small Swift command-line tool built
from this checkout's `contract/swift`, `ios/Packages/CaptureCore` (`CaptureModelMapping`) and
`ios/Packages/PlanExport`. It calls `FloorplanWriter.write`, the code that writes the phone's
Floorplan; nothing is redrawn in the browser.

```sh
plan-render <roomplan.json | capture-model.json> <out-dir> \
  [--address <text>] [--units imperial|metric] [--title <text>]
```

It writes `floorplan.pdf`, `floorplan.svg` and `floorplan.png` (page 1 of the PDF at 200 dpi on
white) and prints a one-line JSON summary. A `roomplan.json` is mapped with `CaptureModelMapper`
first, as the phone's scan viewer does.

- **Source**: the `capture-model.json` of the latest draft that has the capture (it carries the
  operator's room labels; else the newest sealed package's), else the raw `roomplan.json` from the
  originals (else from a sealed package). When both exist, "Draw from" switches between them:
  a capture model written by an older app build can differ from the raw scan mapped with today's
  code, which is what the phone's scan viewer shows.
- **Options**: the address and the display units come from the capture record (imperial when it
  has none); the title is "Floorplan".
- **Build**: on the first Floorplan request, and again whenever a Swift source of the tool or of
  those packages is newer than the binary, the server runs
  `swift build -c release --package-path tools/plan-render` (output in `tools/plan-render/.build`,
  ignored by git). When a source changed without changing what it compiles to (a checkout, a
  comment, a `touch`), `swift build` leaves the binary as it was; the server then sets the binary's
  modified time just after the newest source, so the next start does not build again (the cached
  pages then draw afresh once). One build at a time, never while a render runs; the section shows
  "Rendering floor plan…" meanwhile. A failed build shows the compiler's errors in the section;
  reload or Try again builds again.
- **Cache**: pages are kept in `~/Library/Caches/ChapterScanBrowser/floorplans/<key>/`, owner-only
  (`0700`) folders, where the key is the SHA-256 of the input file's bytes, the options and the
  renderer version (the binary's modified time and size), so a new build draws every page afresh.
  Entries unused for 30 days are removed when a new page is written. The folder can be deleted at
  any time.

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

Sync never writes through a symbolic link. A folder that cannot be made because a symlink or a
file is in the way is reported, and every file under it is skipped (and listed as failed). Right
before each file is copied, and before a folder's time is set, every folder from the data folder
down to it is checked again with `lstat`.

It uses `DEVELOPER_DIR` when set, else `/Applications/Xcode-beta.app`, else `/Applications/Xcode.app`.
With no phone connected, no Xcode, or the app not installed, it says so instead of failing.

## Safety

- Binds `127.0.0.1` and refuses requests whose `Host` is not `127.0.0.1:<port>` or
  `localhost:<port>` (DNS rebinding). Starting a sync needs a custom header and a same-origin
  `Origin`, so another web page cannot trigger it.
- Files are served only from inside the data folder: every path is split into segments (no `..`,
  empty or absolute segments, backslashes or NUL), resolved, and checked again after `realpath`, so
  symlinks cannot escape it. Symlinks inside visits are listed, never followed, and folders are
  listed from the same walk (a symlinked `packages` folder is never read). Sync writes only into
  real folders (see above).
- The page never uses `innerHTML`: every file name, label and JSON value is set as text. A strict
  Content Security Policy allows scripts only from the server and the one pinned
  `model-viewer.min.js` URL on jsDelivr (not the whole CDN), and the page loads that file with an
  SRI hash, so a changed file is refused. Raw files are served with
  `X-Content-Type-Options: nosniff` and a sandbox policy (PDFs excepted, which the browser's viewer
  needs), and never as HTML.
- Counts keyed by values from the files (manifest roles, upload phases) are kept in `Map`s, and the
  redacted upload state is rebuilt with `Object.fromEntries`, so a key such as `__proto__` stays
  plain data and cannot change `Object.prototype`.
- Besides the data folder, the server reads only its own page, the three brand files (a fixed
  list, from `web/public/brand`) and its own cache. Floor plan files are requested by cache key
  and file name: the key must be 64 hex digits, the name one of `floorplan.png`, `floorplan.pdf`
  and `floorplan.svg`, and the entry one this server wrote or checked (complete, real folder and
  files, no symlinks); nothing else in the cache can be named. Which file a Floorplan is drawn from
  is worked out by the server from the visit, never taken from the request.
- `devicectl`, `sips`, `swift build` and `plan-render` run through `execFile` with argument arrays;
  no shell. A render gets a copy of the exact bytes it was keyed by, and has two minutes.
- No network calls except to the phone (devicectl) and, when a GLB is previewed, jsDelivr. The
  renderer's packages are all local paths, so `swift build` fetches nothing.

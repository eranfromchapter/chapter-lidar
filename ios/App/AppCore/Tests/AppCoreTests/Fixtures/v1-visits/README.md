# v1 visit folders (test fixture)

Visit workspaces as the v1 app (commit 05f16e8, the build the owner field-tested before design
v2) wrote them, made by running that code on the box-room and two-floor-house fixture scans
(design-v2 review of T10, Oct 21, 2026). `V1VisitFixtureTests` copies them to a temporary folder
and reads them with today's code, so a change that stops the owner's visits from showing up
after the update fails a test.

| Workspace | What the v1 app left |
|---|---|
| `f6b847e1-…` | A sealed package (manifest and capture record 1.0.0, a `spatial_report_pdf` entry), its upload state (`formatVersion` 1, every file verified), the "Package ready" draft, photos, field controls. |
| `6da18f1c-…` | The same visit sealed, never uploaded (no upload state). |
| `93d1fdf7-…` | Two floors that reached "Package ready" (a draft) and were never sealed, with `room-names.json` (Living Room renamed Shower). |
| `5bf80999-…` | Two scans and photos, no capture record (the v1 app kept it in memory until "Package ready"). |

Only the JSON files and the photos are kept; the plans, meshes, point clouds, depth samples and
PDFs (about 3 MB) are left out. Nothing reads them here: a sealed package opens from its
manifest, and its files' fingerprints are what the manifest says. No `visit.json` exists in any
of them: the v1 app never wrote one.

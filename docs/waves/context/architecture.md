# Chapter Capture — architecture and context (planning reference)

Read-only context for every phase. Specs own the "what"; this file explains the shape.

## Goal

Replace Polycam for Chapter field capture. An iPhone/iPad Pro app produces the full intake
package defined in `intake-guide-R01.md`. A station service on Azure checks it automatically
and publishes the result to the HUB.

## v1 success bar (approved by Eran, 2026-10-17)

The same property is scanned with Polycam and with Chapter Capture:
- every file the guide requests is produced;
- long room dimensions are within 1% or 1 inch (25.4 mm) of tape-measured controls, whichever is larger;
- the station returns a verdict (ready / limited / blocked);
- the DXF and GLB open in Revit 2027 and the LAS indexes in ReCap (checked by a person on Windows).

CI proves geometry fidelity on fixtures with known dimensions. Sensor accuracy and the
Revit/ReCap opening are proven only by the live test property (human acceptance step).

## Stack (approved)

- iOS: Swift 6, SwiftUI, Apple RoomPlan, ARKit (sceneDepth, sceneReconstruction). iPhone/iPad Pro with LiDAR only.
- All export writers (DXF, CSV, PDF, PNG, SVG, GLB, OBJ, LAS) are **pure Swift + Foundation** so they
  run and test on Linux. Only `CaptureCore`, `FieldKit` UI and the App target import Apple-only frameworks.
- Station: TypeScript (Node 22, npm workspaces) on Azure Container Apps, "Chapter Main" tenant.
  Azure Blob Storage (originals, immutable), Postgres (registry), Key Vault (secrets). Entra ID login.
- Web review screen: Next.js on Vercel (Chapter Vercel team).
- HUB: upload route `POST /api/projects/{dealId}/document-media/upload` (multipart field `files`, 50 MB cap).
  The HUB stores files in the project's SharePoint-backed Files tab. Large files stay in Blob and are linked.
- Repo: HelloChapter GitHub org. CI: GitHub Actions; macOS runner for iOS build and Apple-only tests.

## Repository layout (greenfield)

```
contract/        F1  schemas, examples, OpenAPI, TS package, Swift package CaptureContract
scripts/         F1  gate runners (swift-test.sh, verify-exports.sh)
fixtures/        F11 synthetic + recorded capture fixtures, past Polycam packages (sanitized)
ios/Packages/CaptureCore/   F2  RoomPlan + ARKit capture, adapter to CaptureModel
ios/Packages/PlanExport/    F3  DXF, CSV, plan PDF, Spatial Report PDF, PNG, SVG
ios/Packages/MeshExport/    F4  GLB, OBJ+MTL, LAS 1.4
ios/Packages/FieldKit/      F5  photos, field controls, leave-property checklist
ios/Packages/PackageKit/    F6  package assembly, fingerprints, offline upload queue
ios/App/, ios/project.yml   F6  app shell (XcodeGen)
station/api/, station/db/   F7  station API, migrations
station/checks/             F8  acceptance checks + worker
station/hub/                F9  HUB publish
web/                        F10 review screen
.github/, infra/, ios/fastlane/  F12 CI/CD, Azure IaC, TestFlight
```

## Data flow

1. Operator picks the HUB project (dealId) and confirms the address. App creates a CaptureRecord.
2. RoomPlan + ARKit capture per floor/area → CaptureCore normalizes to `CaptureModel` (contract) and
   saves raw RoomPlan JSON + depth samples as originals.
3. PlanExport and MeshExport write derived files from `CaptureModel` on the phone (works offline).
4. FieldKit collects labeled photos and independent field controls; checklist must pass.
5. PackageKit assembles the guide's folder layout, writes `manifest.json` with SHA-256 per file,
   and uploads when online (resumable, to Blob via SAS from the station).
6. Station registers the package, runs acceptance checks, stores the verdict.
7. HUB publish puts verdict report + manifest + plan files into the HUB project folder; links large files.
8. BIM operator reviews in the web screen and logs the source for each modeling decision.

## Human steps that remain (not implementation)

- Apple Developer account owner signs, and approves TestFlight/App Store submission.
- One recorded scan on an iPhone Pro with the debug build to add a real fixture to `fixtures/recorded/`.
- Live test property: Polycam vs Chapter Capture, tape controls, open DXF/GLB in Revit, LAS in ReCap.
- Azure, Vercel and HUB credentials are created by an admin and stored in Key Vault / GitHub secrets.
  No secret ever appears in code, prompts, chat or Slack.

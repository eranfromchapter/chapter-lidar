# PackageKit

Packages one site visit into the intake package and gets it to the station without losing anything
(spec F6, steps F6.1 and F6.2).

| Target             | Imports                               | Purpose                                                                                                         |
| ------------------ | ------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| `PackageCore`      | Foundation, CaptureContract           | Layout paths, `PackageDraft`, `PackageAssembler` (copy + SHA-256 + manifest + seal), revisions, `PackageUploader` |
| `PackageTransport` | Foundation(Networking), PackageCore   | `HTTPBlobTransport` (foreground, portable) and `BackgroundBlobTransport` (background URLSession, Apple only)     |

Everything builds and tests on Linux (`scripts/swift-test.sh`). There is no `.apple-only` marker; the
background transport is wrapped in `#if canImport(Darwin)`. PackageKit depends only on the contract
(not on StationClient, CaptureCore, FieldKit, PlanExport or MeshExport): inputs are file URLs plus
role and capture metadata.

```sh
swift test --package-path ios/Packages/PackageKit --filter PackageAssemblyTests
swift test --package-path ios/Packages/PackageKit --filter OriginalPreservationTests
swift test --package-path ios/Packages/PackageKit --filter UploadResumeTests
station/api/scripts/local-up.sh && STATION_URL=http://localhost:8080 \
  swift test --package-path ios/Packages/PackageKit --filter E2EUploadTests
```

`E2EUploadTests` skips unless `STATION_URL` is set; it signs in at the local test sign-in service
(`http://localhost:8090`, override with `STATION_DEV_IDP_URL`).

## Rules worth knowing

- One package is one visit (`visitId`); each floor or area scan is a capture (`captureId`, `areaKey`).
  `capture_record` and `field_controls` carry no capture. Paths come from `CaptureContract`
  (`PackageFolder`, `PackageLayout`); the downstream folders (Working Conversions, Issued Outputs)
  are never written.
- Originals are copied byte for byte (cloned on APFS), never renamed in content, re-encoded or
  written to; each copy is hashed again and must match its source. A symlinked source is copied as
  the file it points to.
- The manifest (`Source Register/{visitId}/manifest.json`, sorted keys) is written last, as
  `schemaVersion` 1.1.0. The package is built in a hidden staging folder and moved into place
  complete, then made read-only (files 0444, folders 0555). A change is
  `PackageDraft.nextRevision(of:)`: new `packageId`, `revision + 1`, `supersedesPackageId`,
  written to a new folder. A full rebuild of a later revision (re-seal after a failed upload)
  starts from `PackageDraft(visitId:packageId:revision:supersedesPackageId:)`.
- Retired roles (`FileRole.isRetired`: the phone's `spatial_report_pdf`, design v2) are refused by
  `add` and `replace` (`PackageError.retiredRole`); `nextRevision(of:)` leaves them out of a
  1.0.0 base. Packages sealed before v2 (manifest 1.0.0, with the phone report) still open and
  upload unchanged.
- Upload: `PackageUploadService` is the station protocol (StationClient conforms to it in the app).
  Files up to 8 MiB use one Put Blob with the target's headers; larger files use 8 MiB Put Block
  with deterministic base64 ids, then Put Block List. A file is verified only when `completeFile`
  answers `verified` with the manifest's SHA-256 and size. Mismatches, expired or refused targets
  reopen the session (same body) for fresh targets. The seal body is the manifest bytes exactly as
  written.
- Revision N+1 (station 1.1.0): files the session answers as verified with `carriedOverFrom`
  (the superseded revision holds them verified) are recorded in `UploadState.carriedOver` and
  confirmed through `completeFile`; they are never uploaded. `UploadState.registeredAt` is the
  station's `createdAt` of the first session answer (the phone's time with an older station);
  `supersededBy` marks a package re-sealed as a later revision, never resumed. State format 2
  reads format 1.
- Resume: the state (per file: target, staged blocks, phase, last check) is saved as
  `<package folder>.upload-state.json` next to the package after every confirmed step and before
  each Put Blob or Put Block List. A restarted uploader asks the station what landed before sending
  again. The state file holds SAS URLs: it is owner-only (0600) and, on iOS, protected until first
  unlock. Descriptions of `UploadTarget` redact the URL.
- PackageKit has no delete API. It never deletes the package, the state file or a failed staging
  folder (`UploadState.isConfirmedByStation` tells the app when the station has everything).
- App shell (F6.4): create one `BackgroundBlobTransport` per session identifier for the app's
  lifetime and pass the `handleEventsForBackgroundURLSession` completion handler to
  `setBackgroundEventsCompletionHandler(_:)`.

# StationClient

The phone's client for the station API (spec F6, step F6.3). Foundation and CaptureContract
only; builds and tests on Linux (`scripts/swift-test.sh`). No third-party packages, no
`.apple-only` marker.

| Type                         | Purpose                                                                                              |
| ---------------------------- | ---------------------------------------------------------------------------------------------------- |
| `StationClient`              | One method per phone operation of `contract/openapi/station.yaml` (13 of 1.1.0), typed `StationError` |
| `StationOperation`           | operationId, method, path template, security and success statuses, checked by `OpenAPIParityTests`   |
| `AccessTokenProvider`        | Token seam. The app shell implements it with MSAL; 401 gets one `forceRefresh: true` retry            |
| `SecureTokenStore`           | Secret storage seam; `KeychainTokenStore` (Apple only, `#if canImport(Security)`) is the only store   |
| `HTTPTransport`              | Injected transport; `URLSessionTransport` is ephemeral (no cache, no cookies) and never redirects     |
| `ProjectStore`               | HUB project list: live when online and saved as JSON; last saved list marked stale when offline       |

```sh
swift test --package-path ios/Packages/StationClient --filter OpenAPIParityTests
swift test --package-path ios/Packages/StationClient --filter StationClientTests
swift test --package-path ios/Packages/StationClient --filter ProjectStoreTests
```

## Rules worth knowing

- The client is written by hand, not generated: swift-openapi-generator would add several
  third-party packages (runtime, transport and build-plugin dependencies). `OpenAPIParityTests` reads the document and fails on any operation, method, path, security or
  success-status difference, and on any request the client sends that the document does not list.
- `stationURL` is the station host; the client appends `/v1`. HTTPS only, except
  `http://localhost` and `http://127.0.0.1` for a local station.
- `sealPackage(packageId:manifestJSON:)` sends the manifest bytes exactly as given.
- Station 1.1.0 fields are all optional, so an older station's answers still decode:
  `Package`/`PackageSummary` `checks`, `publication`, `links`; `Package.nextRevision`;
  `UploadSession.createdAt` ("Registered" on the phone); `UploadSessionFile.carriedOverFrom` and
  `PackageFile.carriedOverFrom` (revision N+1 reuses verified files of revision N).
- `putNextRevisionNotice(packageId:_:)` tells the station what the next revision changes while
  the operator works on it (the web shows it); callers treat it as best effort. The review
  screen's operations (`getSpatialReportLink`, archive, review lists, all decisions) are not in
  the phone client (`OpenAPIParityTests.notInClient`).
- Nothing is logged. Tokens and Authorization headers never appear in errors; SAS URLs in
  `UploadTarget` and `DownloadLink` are redacted from `description` and `dump`.
- `ProjectStore` falls back to the saved list only on `StationError.offline`. 401, 403, 5xx,
  invalid responses and token-provider errors are thrown, never answered from the cache. With no
  saved list, offline throws `.offline`. Call `clearCache()` at sign-out.
- The app shell must provide the MSAL-backed `AccessTokenProvider` and bridge `UploadSession`,
  `FileCheckResult` and `Package` to PackageKit's station protocol.

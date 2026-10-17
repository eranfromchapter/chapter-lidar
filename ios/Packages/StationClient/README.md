# StationClient

The phone's client for the station API (spec F6, step F6.3). Foundation and CaptureContract
only; builds and tests on Linux (`scripts/swift-test.sh`). No third-party packages, no
`.apple-only` marker.

| Type                         | Purpose                                                                                              |
| ---------------------------- | ---------------------------------------------------------------------------------------------------- |
| `StationClient`              | One method per operation of `contract/openapi/station.yaml` (12 operations), typed `StationError`     |
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
- Nothing is logged. Tokens and Authorization headers never appear in errors; SAS URLs in
  `UploadTarget` and `DownloadLink` are redacted from `description` and `dump`.
- `ProjectStore` falls back to the saved list only on `StationError.offline`. 401, 403, 5xx,
  invalid responses and token-provider errors are thrown, never answered from the cache. With no
  saved list, offline throws `.offline`. Call `clearCache()` at sign-out.
- The app shell must provide the MSAL-backed `AccessTokenProvider` and bridge `UploadSession`,
  `FileCheckResult` and `Package` to PackageKit's station protocol.

// UI-test stubs: an in-process station (HTTPTransport for the real StationClient) and a token
// provider. DEBUG ONLY: this whole file is compiled only with the DEBUG condition, so a Release
// build of AppCore (and of the app) contains no stub station and no stub token. The app selects
// them only in `LaunchMode.uiTestReplay` and `.fieldTest`, which `LaunchModeResolver` never
// returns for a Release build.
#if DEBUG
  import CaptureContract
  import Foundation
  import StationClient

  #if canImport(FoundationNetworking)
    import FoundationNetworking
  #endif

  /// Blobs "stored" by the UI-test blob transport, by blob location (URL without query).
  public final class UITestBlobStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var blobs: [String: Data] = [:]
    private var blocks: [String: [String: Data]] = [:]

    public init() {}

    public func putBlob(_ data: Data, at location: String) {
      lock.lock()
      blobs[location] = data
      blocks[location] = nil
      lock.unlock()
    }

    public func putBlock(_ data: Data, id: String, at location: String) {
      lock.lock()
      blocks[location, default: [:]][id] = data
      lock.unlock()
    }

    /// Commits staged blocks in order. False when a block is missing.
    public func commit(_ ids: [String], at location: String) -> Bool {
      lock.lock()
      defer { lock.unlock() }
      let staged = blocks[location] ?? [:]
      var data = Data()
      for id in ids {
        guard let block = staged[id] else { return false }
        data.append(block)
      }
      blobs[location] = data
      blocks[location] = nil
      return true
    }

    public func blob(at location: String) -> Data? {
      lock.lock()
      defer { lock.unlock() }
      return blobs[location]
    }
  }

  /// A fixed token. Never a real credential.
  public struct UITestTokenProvider: AccessTokenProvider {
    /// The signed-in name of the UI-test mode (operator, "Signed in as" on New capture).
    public static let operatorName = "UI Test Operator"

    public init() {}
    public func accessToken(forceRefresh: Bool) async throws -> String { "uitest-local-token" }
  }

  /// The station of the UI tests, answering StationClient's requests in process: one HUB
  /// project, upload sessions with targets on `https://uitest-blob.invalid`, server-side SHA-256
  /// checks against the UI-test blob storage, sealing (status `checks_queued`), and the package
  /// status. Nothing leaves the process.
  public final class UITestStationTransport: HTTPTransport, @unchecked Sendable {
    public static let stationURL = URL(string: "https://uitest-station.invalid")!
    public static let blobHost = "https://uitest-blob.invalid"
    public static let project = HubProject(
      dealId: "UITEST-0001", projectName: "UI test visit",
      address: HubProject.Address(formatted: "618 Valley Street, Test Town"))

    private let storage: UITestBlobStorage
    private let lock = NSLock()
    /// Guarded by `lock`.
    private var packages: [String: StoredPackage] = [:]
    private let now: @Sendable () -> Date

    private struct StoredPackage {
      var request: UploadSessionRequest
      var status: PackageStatus
      var createdAt: UTCTimestamp
      var sealedAt: UTCTimestamp?
      var manifest: PackageManifest?
    }

    public init(storage: UITestBlobStorage, now: @escaping @Sendable () -> Date = { Date() }) {
      self.storage = storage
      self.now = now
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
      guard let url = request.url else { throw URLError(.badURL) }
      let path = url.path
      let method = request.httpMethod ?? "GET"
      let segments = path.split(separator: "/").map(String.init)
      guard segments.first == "v1" else { return problem(404, "not_found", url) }
      let route = Array(segments.dropFirst())
      let body = request.httpBody ?? Data()

      switch (method, route.count, route.first) {
      case ("GET", 1, "projects"):
        return try json(200, ProjectListResponse(projects: [Self.project]), url)
      case ("POST", 1, "packages"):
        return try openSession(body, url)
      case ("POST", 4, "packages") where route[2] == "files" && route[3] == "complete":
        return try complete(packageId: route[1], body: body, url)
      case ("POST", 3, "packages") where route[2] == "seal":
        return try seal(packageId: route[1], body: body, url)
      case ("GET", 2, "packages"):
        return try package(route[1], url)
      case ("GET", 3, "packages") where route[2] == "verdict":
        return problem(404, "verdict_not_ready", url)
      default:
        return problem(404, "not_found", url)
      }
    }

    // MARK: Routes

    private func openSession(_ body: Data, _ url: URL) throws -> (Data, HTTPURLResponse) {
      let request = try CaptureContractJSON.makeDecoder().decode(
        UploadSessionRequest.self, from: body)
      lock.lock()
      let key = request.packageId.rawValue
      let created = packages[key] == nil
      if created {
        packages[key] = StoredPackage(
          request: request, status: .uploading, createdAt: UTCTimestamp(now()))
      }
      let stored = packages[key]!
      lock.unlock()
      let expires = UTCTimestamp(now().addingTimeInterval(3600))
      let files = request.files.enumerated().map { index, file -> UploadSessionFile in
        if verified(file, packageId: key) {
          return UploadSessionFile(path: file.path, status: .verified)
        }
        return UploadSessionFile(
          path: file.path, status: .pending,
          upload: UploadTarget(
            url: blobURL(packageId: key, index: index), headers: ["x-ms-blob-type": "BlockBlob"],
            expiresAt: expires))
      }
      let session = UploadSession(
        packageId: request.packageId, visitId: request.visitId, dealId: request.dealId,
        revision: request.revision, status: stored.status, files: files)
      return try json(created ? 201 : 200, session, url)
    }

    private func complete(packageId: String, body: Data, _ url: URL) throws -> (
      Data, HTTPURLResponse
    ) {
      let path = try CaptureContractJSON.makeDecoder().decode(CompleteFileRequest.self, from: body)
        .path
      guard let stored = stored(packageId),
        let index = stored.request.files.firstIndex(where: { $0.path == path })
      else { return problem(404, "file_not_declared", url) }
      let file = stored.request.files[index]
      let data = storage.blob(at: blobLocation(packageId: packageId, index: index))
      let status: FileStatus
      if let data {
        let digest = UITestDigest.sha256Hex(data)
        status =
          Int64(data.count) != file.bytes
          ? .bytesMismatch : (digest == file.sha256 ? .verified : .sha256Mismatch)
      } else {
        status = .notUploaded
      }
      return try json(
        200,
        FileCheckResult(
          path: path, status: status, expectedSha256: file.sha256,
          actualSha256: data.map(UITestDigest.sha256Hex), expectedBytes: file.bytes,
          actualBytes: data.map { Int64($0.count) }, checkedAt: UTCTimestamp(now())),
        url)
    }

    private func seal(packageId: String, body: Data, _ url: URL) throws -> (Data, HTTPURLResponse) {
      guard var stored = stored(packageId) else { return problem(404, "package_not_found", url) }
      let manifest = try CaptureContractJSON.makeDecoder().decode(PackageManifest.self, from: body)
      guard stored.request.files.allSatisfy({ verified($0, packageId: packageId) }) else {
        return problem(409, "files_not_verified", url)
      }
      stored.status = .checksQueued
      stored.sealedAt = manifest.sealedAt
      stored.manifest = manifest
      lock.lock()
      packages[packageId] = stored
      lock.unlock()
      return try json(200, packageBody(stored), url)
    }

    private func package(_ packageId: String, _ url: URL) throws -> (Data, HTTPURLResponse) {
      guard let stored = stored(packageId) else { return problem(404, "package_not_found", url) }
      return try json(200, packageBody(stored), url)
    }

    // MARK: Helpers

    private func stored(_ packageId: String) -> StoredPackage? {
      lock.lock()
      defer { lock.unlock() }
      return packages[packageId]
    }

    private func verified(_ file: UploadFileDeclaration, packageId: String) -> Bool {
      guard let stored = stored(packageId),
        let index = stored.request.files.firstIndex(where: { $0.path == file.path }),
        let data = storage.blob(at: blobLocation(packageId: packageId, index: index))
      else { return false }
      return Int64(data.count) == file.bytes && UITestDigest.sha256Hex(data) == file.sha256
    }

    private func packageBody(_ stored: StoredPackage) -> Package {
      let request = stored.request
      return Package(
        packageId: request.packageId, visitId: request.visitId, dealId: request.dealId,
        revision: request.revision, supersedesPackageId: request.supersedesPackageId,
        status: stored.status, createdAt: stored.createdAt, sealedAt: stored.sealedAt,
        files: request.files.map { file in
          PackageFile(
            path: file.path, role: file.role, captureId: file.captureId, areaKey: file.areaKey,
            sha256: file.sha256, bytes: file.bytes,
            status: verified(file, packageId: request.packageId.rawValue) ? .verified : .pending,
            checkedAt: UTCTimestamp(now()))
        },
        manifest: stored.manifest)
    }

    private func blobLocation(packageId: String, index: Int) -> String {
      "\(Self.blobHost)/packages/\(packageId)/file-\(index)"
    }

    private func blobURL(packageId: String, index: Int) -> URL {
      URL(string: blobLocation(packageId: packageId, index: index) + "?uitest=1")!
    }

    private func json<T: Encodable>(_ status: Int, _ value: T, _ url: URL) throws -> (
      Data, HTTPURLResponse
    ) {
      let data = try CaptureContractJSON.makeEncoder().encode(value)
      return (data, response(status, url, "application/json"))
    }

    private func problem(_ status: Int, _ code: String, _ url: URL) -> (Data, HTTPURLResponse) {
      let body = Data(
        #"{"type":"about:blank","title":"\#(code)","status":\#(status),"code":"\#(code)"}"#.utf8)
      return (body, response(status, url, "application/problem+json"))
    }

    private func response(_ status: Int, _ url: URL, _ type: String) -> HTTPURLResponse {
      HTTPURLResponse(
        url: url, statusCode: status, httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": type])!
    }
  }
#endif

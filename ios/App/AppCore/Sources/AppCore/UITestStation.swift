// UI-test stubs: an in-process station (HTTPTransport for the real StationClient) and a token
// provider. DEBUG ONLY: this whole file is compiled only with the DEBUG condition, so a Release
// build of AppCore (and of the app) contains no stub station and no stub token. The app selects
// them only in `LaunchMode.uiTestReplay` and `.fieldTest`, which `LaunchModeResolver` never
// returns for a Release build.
#if DEBUG
  import CaptureContract
  import Foundation
  import StationClient

  import FieldRules
  import PhotoStore

  #if canImport(FoundationNetworking)
    import FoundationNetworking
  #endif

  /// How the UI-test station behaves (phone-package §9.1), from the app's launch arguments:
  ///
  /// - `-ChapterUITestVerdict ready|limited|blocked`: after sealing, the checks run and the
  ///   verdict is ready about 2 s later, published to the HUB 2 s after that. Without it the
  ///   package stays at checks_queued and `getVerdict` answers 404, as before v2.
  /// - `-ChapterUITestOffline [seconds]`: blob uploads fail with "not connected to the internet"
  ///   for that long (default 20 s) from the first upload on, then go through.
  /// - `-ChapterUITestRefuse`: the first upload session is refused with 409 `package_conflict`
  ///   (a fatal error: Upload stopped); later ones are accepted.
  public struct UITestStationOptions: Equatable, Sendable {
    public static let verdictArgument = "-ChapterUITestVerdict"
    public static let offlineArgument = "-ChapterUITestOffline"
    public static let refuseArgument = "-ChapterUITestRefuse"
    public static let defaultOfflineSeconds: TimeInterval = 20

    public var verdict: VerdictOutcome?
    /// Nil: never offline.
    public var offlineSeconds: TimeInterval?
    public var refuseFirstSession: Bool

    public init(
      verdict: VerdictOutcome? = nil, offlineSeconds: TimeInterval? = nil,
      refuseFirstSession: Bool = false
    ) {
      self.verdict = verdict
      self.offlineSeconds = offlineSeconds
      self.refuseFirstSession = refuseFirstSession
    }

    public init(arguments: [String]) {
      func value(after flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
          return nil
        }
        return arguments[index + 1]
      }
      var offline: TimeInterval?
      if arguments.contains(Self.offlineArgument) {
        offline = value(after: Self.offlineArgument).flatMap(TimeInterval.init)
          ?? Self.defaultOfflineSeconds
      }
      self.init(
        verdict: value(after: Self.verdictArgument).flatMap(VerdictOutcome.init(rawValue:)),
        offlineSeconds: offline, refuseFirstSession: arguments.contains(Self.refuseArgument))
    }
  }

  /// Blobs "stored" by the UI-test blob transport, by blob location (URL without query), and
  /// the offline window of `-ChapterUITestOffline`.
  public final class UITestBlobStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var blobs: [String: Data] = [:]
    private var blocks: [String: [String: Data]] = [:]
    private var offlineSeconds: TimeInterval?
    private var offlineUntil: Date?

    public init(offlineSeconds: TimeInterval? = nil) {
      self.offlineSeconds = offlineSeconds
    }

    /// Throws "not connected to the internet" while the offline window lasts; the window starts
    /// at the first call.
    public func checkConnection(now: Date = Date()) throws {
      let offline = lock.withLock { () -> Bool in
        guard let seconds = offlineSeconds else { return false }
        let until = offlineUntil ?? now.addingTimeInterval(seconds)
        offlineUntil = until
        return now < until
      }
      if offline { throw URLError(.notConnectedToInternet) }
    }

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

    /// Every blob location stored.
    public var locations: [String] {
      lock.withLock { blobs.keys.sorted() }
    }

    /// Removes the blobs and staged blocks at `locations` ("Delete all photos"); returns how
    /// many blobs and staged blocks were removed.
    @discardableResult
    public func remove(at locations: Set<String>) -> Int {
      lock.withLock {
        var removed = 0
        for location in locations {
          if blobs.removeValue(forKey: location) != nil { removed += 1 }
          removed += blocks.removeValue(forKey: location)?.count ?? 0
        }
        return removed
      }
    }

    /// Removes every blob and staged block whose bytes are a photograph (JPEG or HEIC by its
    /// first bytes), wherever it is stored; returns how many were removed.
    @discardableResult
    public func removePhotos() -> Int {
      lock.withLock {
        var removed = 0
        for (location, data) in blobs where PhotoFormat.detect(data) != nil {
          blobs[location] = nil
          removed += 1
        }
        for (location, staged) in blocks {
          let kept = staged.filter { PhotoFormat.detect($0.value) == nil }
          removed += staged.count - kept.count
          blocks[location] = kept.isEmpty ? nil : kept
        }
        return removed
      }
    }
  }

  /// How the in-process station answers `POST /v1/sketch-interpretations` (spec F16): the
  /// bundled fixture interpretation (UI tests; a field-test build without an API key), or the
  /// field-test build's direct Claude call (`FieldTestSketchReader`).
  public enum UITestSketchReader: Sendable {
    /// The fixture's bytes (a `SketchInterpretation`), answered after `delay` seconds with the
    /// photo's pixel size and the time of the answer.
    case fixture(Data, delay: TimeInterval)
    case claude(FieldTestSketchReader)
  }

  /// A fixed token. Never a real credential.
  public struct UITestTokenProvider: AccessTokenProvider {
    /// The signed-in name of the UI-test mode (operator, "Signed in as" on New capture).
    public static let operatorName = "UI Test Operator"

    public init() {}
    public func accessToken(forceRefresh: Bool) async throws -> String { "uitest-local-token" }
  }

  /// The station of the UI tests, answering StationClient's requests in process: one HUB
  /// project, upload sessions with targets on `https://uitest-blob.invalid` (and carry-over of
  /// the superseded revision's verified files), server-side SHA-256 checks against the UI-test
  /// blob storage, sealing, the package with its checks, publication and links, the verdict and
  /// the next-revision notice (`UITestStationOptions`). Nothing leaves the process.
  public final class UITestStationTransport: HTTPTransport, @unchecked Sendable {
    public static let stationURL = URL(string: "https://uitest-station.invalid")!
    public static let blobHost = "https://uitest-blob.invalid"
    public static let reviewHost = "https://uitest-review.invalid"
    /// The HUB's deal pages, as a station with `HUB_WEB_DEAL_URL_TEMPLATE` sends them.
    public static let hubHost = "https://uitest-hub.invalid"
    public static let project = HubProject(
      dealId: "UITEST-0001", projectName: "UI test visit",
      address: HubProject.Address(formatted: "618 Valley Street, Test Town"))
    /// Seconds from sealing to the verdict, and from the verdict to the HUB publication.
    static let checksSeconds: TimeInterval = 2
    static let publishSeconds: TimeInterval = 2

    private let storage: UITestBlobStorage
    private let options: UITestStationOptions
    private let lock = NSLock()
    /// Guarded by `lock`.
    private var packages: [String: StoredPackage] = [:]
    private var notices: [String: NextRevisionNotice] = [:]
    private var refusedFirstSession = false
    private let now: @Sendable () -> Date
    private let sketchReader: UITestSketchReader?

    private struct StoredPackage {
      var request: UploadSessionRequest
      var status: PackageStatus
      var createdAt: UTCTimestamp
      var sealedAt: UTCTimestamp?
      /// When the station accepted the seal (its clock).
      var sealedTime: Date?
      var manifest: PackageManifest?
      /// Files verified by carry-over: path → (superseded package, its file index).
      var carried: [String: (packageId: String, index: Int)] = [:]
      var verdictId = LowercaseUUID()
    }

    /// `sketchReader`: how sketch photos are read; nil answers 503 (no reader), as a station
    /// without an API key does.
    public init(
      storage: UITestBlobStorage, options: UITestStationOptions = UITestStationOptions(),
      sketchReader: UITestSketchReader? = nil, now: @escaping @Sendable () -> Date = { Date() }
    ) {
      self.storage = storage
      self.options = options
      self.sketchReader = sketchReader
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
        return try verdict(route[1], url)
      case ("PUT", 3, "packages") where route[2] == "next-revision":
        return try nextRevision(route[1], body: body, url)
      case ("POST", 1, "sketch-interpretations"):
        return try await interpretSketch(body, url)
      default:
        return problem(404, "not_found", url)
      }
    }

    // MARK: Routes

    private func openSession(_ body: Data, _ url: URL) throws -> (Data, HTTPURLResponse) {
      let request = try CaptureContractJSON.makeDecoder().decode(
        UploadSessionRequest.self, from: body)
      lock.lock()
      if options.refuseFirstSession && !refusedFirstSession {
        refusedFirstSession = true
        lock.unlock()
        return problem(409, "package_conflict", url)
      }
      let key = request.packageId.rawValue
      let created = packages[key] == nil
      if created {
        var stored = StoredPackage(
          request: request, status: .uploading, createdAt: UTCTimestamp(now()))
        // Carry-over: files equal to a verified file of the sealed superseded revision.
        if let previousId = request.supersedesPackageId?.rawValue,
          let previous = packages[previousId], previous.status != .uploading
        {
          for file in request.files {
            guard let index = previous.request.files.firstIndex(of: file),
              let data = blobLocked(previous, packageId: previousId, index: index),
              Int64(data.count) == file.bytes, UITestDigest.sha256Hex(data) == file.sha256
            else { continue }
            stored.carried[file.path] = (previousId, index)
          }
        }
        packages[key] = stored
        notices[request.supersedesPackageId?.rawValue ?? ""] = nil
      }
      let stored = packages[key]!
      lock.unlock()
      let expires = UTCTimestamp(now().addingTimeInterval(3600))
      let files = request.files.enumerated().map { index, file -> UploadSessionFile in
        if let carried = stored.carried[file.path] {
          return UploadSessionFile(
            path: file.path, status: .verified,
            carriedOverFrom: LowercaseUUID(rawValue: carried.packageId))
        }
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
        revision: request.revision, status: stored.status, createdAt: stored.createdAt,
        files: files)
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
      let data = blob(of: file, in: stored, packageId: packageId)
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
      if stored.status == .uploading {
        stored.status = .checksQueued
        stored.sealedAt = manifest.sealedAt
        stored.sealedTime = now()
        stored.manifest = manifest
        lock.lock()
        packages[packageId] = stored
        lock.unlock()
      }
      return try json(200, packageBody(stored), url)
    }

    private func package(_ packageId: String, _ url: URL) throws -> (Data, HTTPURLResponse) {
      guard let stored = stored(packageId) else { return problem(404, "package_not_found", url) }
      return try json(200, packageBody(stored), url)
    }

    private func verdict(_ packageId: String, _ url: URL) throws -> (Data, HTTPURLResponse) {
      guard let stored = stored(packageId) else { return problem(404, "package_not_found", url) }
      guard let verdict = verdictBody(stored) else {
        return problem(404, "verdict_not_ready", url)
      }
      return try json(200, verdict, url)
    }

    private func nextRevision(_ packageId: String, body: Data, _ url: URL) throws -> (
      Data, HTTPURLResponse
    ) {
      guard let stored = stored(packageId) else { return problem(404, "package_not_found", url) }
      guard stored.status != .uploading else { return problem(409, "package_not_sealed", url) }
      let input = try CaptureContractJSON.makeDecoder().decode(
        NextRevisionNoticeInput.self, from: body)
      guard input.revision == stored.request.revision + 1 else {
        return problem(422, "revision_mismatch", url)
      }
      let notice = NextRevisionNotice(
        revision: input.revision, updatedAt: input.updatedAt,
        updatedBy: UITestTokenProvider.operatorName, changes: input.changes)
      lock.withLock { notices[packageId] = notice }
      return try json(200, notice, url)
    }

    /// `POST /v1/sketch-interpretations` as the station answers it: 200 with the reading, 422
    /// `sketch_not_a_plan` (with the interpretation) when the reading is not a floor plan, 502
    /// when Claude failed, 503 without a reader.
    private func interpretSketch(_ body: Data, _ url: URL) async throws -> (Data, HTTPURLResponse) {
      struct Request: Decodable {
        var mediaType: String
        var data: String
      }
      guard let request = try? JSONDecoder().decode(Request.self, from: body),
        let image = Data(base64Encoded: request.data)
      else { return problem(400, "sketch_image_invalid", url) }
      let interpretation: SketchInterpretation
      switch sketchReader {
      case nil:
        return problem(503, "sketch_unavailable", url)
      case .fixture(let fixture, let delay):
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        var read = try CaptureContractJSON.makeDecoder().decode(
          SketchInterpretation.self, from: fixture)
        read.interpretedAt = UTCTimestamp(now())
        if let size = ImageHeader.size(of: image) { read.image = size }
        interpretation = read
      case .claude(let reader):
        do {
          interpretation = try await reader.read(imageData: image, mediaType: request.mediaType)
        } catch let error as FieldTestSketchReaderError {
          // The station's codes (F16.2): 422 refused; 502 truncated, unreadable or rejected.
          let (status, code): (Int, String)
          switch error {
          case .refused: (status, code) = (422, "sketch_refused")
          case .truncated: (status, code) = (502, "sketch_truncated")
          case .unreadableAnswer: (status, code) = (502, "sketch_unreadable_response")
          case .api, .missingResource, .streamError: (status, code) = (502, "sketch_request_rejected")
          }
          return problem(status, code, url, title: error.description)
        }
      }
      guard interpretation.reading.isFloorPlan else {
        var object: [String: Any] = [
          "type": "about:blank", "title": "Not a floor plan", "status": 422,
          "code": "sketch_not_a_plan",
        ]
        object["interpretation"] = try JSONSerialization.jsonObject(
          with: try CaptureContractJSON.makeEncoder().encode(interpretation))
        return (
          try JSONSerialization.data(withJSONObject: object),
          response(422, url, "application/problem+json")
        )
      }
      return try json(200, interpretation, url)
    }

    /// "Delete all photos": the photo blobs of every package this station holds (and their
    /// staged blocks), then any other stored blob that is a photograph. The packages stay
    /// registered; their photo files are no longer verified. Returns how many blobs and blocks
    /// were removed.
    @discardableResult
    public func erasePhotoBlobs() -> Int {
      let locations = lock.withLock { () -> Set<String> in
        var locations: Set<String> = []
        for (key, stored) in packages {
          for (index, file) in stored.request.files.enumerated() where file.role == .photo {
            locations.insert(blobLocation(packageId: key, index: index))
          }
        }
        return locations
      }
      return storage.remove(at: locations) + storage.removePhotos()
    }

    // MARK: Helpers

    private func stored(_ packageId: String) -> StoredPackage? {
      lock.lock()
      defer { lock.unlock() }
      return packages[packageId]
    }

    /// The stored bytes of a declared file: its own blob, or the superseded revision's.
    private func blob(of file: UploadFileDeclaration, in stored: StoredPackage, packageId: String)
      -> Data?
    {
      if let carried = stored.carried[file.path] {
        return storage.blob(at: blobLocation(packageId: carried.packageId, index: carried.index))
      }
      guard let index = stored.request.files.firstIndex(where: { $0.path == file.path }) else {
        return nil
      }
      return storage.blob(at: blobLocation(packageId: packageId, index: index))
    }

    /// `blob(of:…)` for a package read under the lock.
    private func blobLocked(_ stored: StoredPackage, packageId: String, index: Int) -> Data? {
      let file = stored.request.files[index]
      if let carried = stored.carried[file.path] {
        return storage.blob(at: blobLocation(packageId: carried.packageId, index: carried.index))
      }
      return storage.blob(at: blobLocation(packageId: packageId, index: index))
    }

    private func verified(_ file: UploadFileDeclaration, packageId: String) -> Bool {
      guard let stored = stored(packageId), let data = blob(of: file, in: stored, packageId: packageId)
      else { return false }
      return Int64(data.count) == file.bytes && UITestDigest.sha256Hex(data) == file.sha256
    }

    /// Where a sealed package is now: queued, checking, verdict ready (with a verdict option),
    /// then published.
    private func progress(_ stored: StoredPackage) -> (
      status: PackageStatus, checks: CheckRunSummary?, publication: PublicationSummary?,
      verdict: VerdictSummary?
    ) {
      guard stored.status != .uploading, let sealed = stored.sealedTime else {
        return (stored.status, nil, nil, nil)
      }
      let folder = "Capture/\(stored.request.visitId.rawValue)/r\(stored.request.revision)"
      guard let outcome = options.verdict else {
        return (.checksQueued, CheckRunSummary(status: .queued), nil, nil)
      }
      let elapsed = now().timeIntervalSince(sealed)
      let started = UTCTimestamp(sealed.addingTimeInterval(Self.checksSeconds / 2))
      guard elapsed >= Self.checksSeconds / 2 else {
        return (.checksQueued, CheckRunSummary(status: .queued), nil, nil)
      }
      guard elapsed >= Self.checksSeconds else {
        return (.checking, CheckRunSummary(status: .running, startedAt: started), nil, nil)
      }
      let evaluated = UTCTimestamp(sealed.addingTimeInterval(Self.checksSeconds))
      let checks = CheckRunSummary(
        status: .completed, startedAt: started, finishedAt: evaluated, rules: 13)
      let verdict = VerdictSummary(
        verdictId: stored.verdictId, outcome: outcome, evaluatedAt: evaluated)
      let published = elapsed >= Self.checksSeconds + Self.publishSeconds
      let publication = PublicationSummary(
        status: published ? .published : .publishing,
        publishedAt: published
          ? UTCTimestamp(sealed.addingTimeInterval(Self.checksSeconds + Self.publishSeconds)) : nil,
        hubFolder: folder)
      return (.verdictReady, checks, publication, verdict)
    }

    private func packageBody(_ stored: StoredPackage) -> Package {
      let request = stored.request
      let state = progress(stored)
      let key = request.packageId.rawValue
      return Package(
        packageId: request.packageId, visitId: request.visitId, dealId: request.dealId,
        revision: request.revision, supersedesPackageId: request.supersedesPackageId,
        status: state.status, createdAt: stored.createdAt, sealedAt: stored.sealedAt,
        files: request.files.map { file in
          PackageFile(
            path: file.path, role: file.role, captureId: file.captureId, areaKey: file.areaKey,
            sha256: file.sha256, bytes: file.bytes,
            status: verified(file, packageId: key) ? .verified : .pending,
            checkedAt: UTCTimestamp(now()),
            carriedOverFrom: stored.carried[file.path].flatMap {
              LowercaseUUID(rawValue: $0.packageId)
            })
        },
        manifest: stored.manifest, verdict: state.verdict, checks: state.checks,
        publication: state.publication,
        links: PackageLinks(
          review: URL(string: "\(Self.reviewHost)/packages/\(key)")!,
          hub: URL(string: "\(Self.hubHost)/deals/")?.appendingPathComponent(request.dealId)),
        nextRevision: lock.withLock { notices[key] })
    }

    /// The verdict of a package whose checks finished (`-ChapterUITestVerdict`).
    private func verdictBody(_ stored: StoredPackage) -> Verdict? {
      let state = progress(stored)
      guard let summary = state.verdict else { return nil }
      let task = "Preliminary existing-condition plans"
      var findings: [Verdict.Finding] = []
      var limitations: [String] = []
      var nextActions: [String] = []
      switch summary.outcome {
      case .ready:
        break
      case .limited:
        limitations = [
          "Floor 1: Closet ceiling height is approximate", "Floor 1: orientation is not verified",
        ]
        nextActions = [
          "Tape-measure the Closet ceiling height on the next visit.",
          "Read the compass at the start of each floor's scan.",
        ]
        findings = [
          Verdict.Finding(
            ruleId: "controls.ceiling", severity: .limitation,
            message: "Closet ceiling height is approximate",
            measured: "Ceiling partly captured \u{00B7} height is approx.",
            nextAction: nextActions[0]),
          Verdict.Finding(
            ruleId: "orientation.compass", severity: .limitation,
            message: CompassText.limitation, nextAction: nextActions[1]),
        ]
      case .blocked:
        nextActions = ["Scan the floor again: the scan has no rooms."]
        findings = [
          Verdict.Finding(
            ruleId: "model.rooms", severity: .blocker, message: "The scan has no rooms",
            nextAction: nextActions[0])
        ]
      }
      return Verdict(
        verdictId: summary.verdictId, packageId: stored.request.packageId,
        visitId: stored.request.visitId, revision: stored.request.revision,
        outcome: summary.outcome, task: task,
        summary: summary.outcome == .ready
          ? "Ready for preliminary existing-condition plans."
          : "Usable with named limitations.",
        evaluatedAt: summary.evaluatedAt,
        evaluator: Verdict.Evaluator(name: "station-checks", version: "1.1.0"),
        checks: [], findings: findings, limitations: limitations, nextActions: nextActions)
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

    private func problem(_ status: Int, _ code: String, _ url: URL, title: String? = nil) -> (
      Data, HTTPURLResponse
    ) {
      let object: [String: Any] = [
        "type": "about:blank", "title": title ?? code, "status": status, "code": code,
      ]
      let body = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
      return (body, response(status, url, "application/problem+json"))
    }

    private func response(_ status: Int, _ url: URL, _ type: String) -> HTTPURLResponse {
      HTTPURLResponse(
        url: url, statusCode: status, httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": type])!
    }
  }
#endif

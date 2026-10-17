// Background URLSession blob transport for the app. Apple platforms only: the file is empty on
// Linux, so the package builds and tests there.
#if canImport(Darwin)
  import Foundation
  import PackageCore

  /// Blob transport over a background URLSession: uploads keep running while the app is suspended
  /// and finish after it is killed.
  ///
  /// - Put Blob uploads straight from the package file (read only).
  /// - Put Block and Put Block List upload from a scratch file in `scratchDirectory`, because
  ///   background sessions only upload from files. There is one scratch file per blob; it holds a
  ///   copy of one block (never the original) and is replaced atomically for the next block.
  ///   PackageKit never deletes files; scratch files live in a caches folder the system may purge.
  /// - A request that finishes after the app was killed has no waiting caller; its result is
  ///   dropped. `PackageUploader` saved the file as `sending` before the request, so it asks the
  ///   station what landed before sending again.
  ///
  /// Wire `handleEventsForBackgroundURLSession` to `setBackgroundEventsCompletionHandler(_:)` and
  /// create one instance per identifier for the app's lifetime.
  public final class BackgroundBlobTransport: NSObject, BlobTransport, URLSessionDataDelegate,
    @unchecked Sendable
  {
    public let identifier: String
    private let scratchDirectory: URL
    private let lock = NSLock()
    /// Guarded by `lock`.
    private var waiting: [Int: CheckedContinuation<URLResponse?, Error>] = [:]
    /// Guarded by `lock`.
    private var backgroundEventsCompletion: (@Sendable () -> Void)?
    /// Set once in init, then only read.
    private var session: URLSession?

    public init(identifier: String, scratchDirectory: URL) {
      self.identifier = identifier
      self.scratchDirectory = scratchDirectory
      super.init()
      let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
      configuration.isDiscretionary = false
      #if os(iOS)
        configuration.sessionSendsLaunchEvents = true
      #endif
      session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    /// Call from the app delegate's handleEventsForBackgroundURLSession with its handler.
    public func setBackgroundEventsCompletionHandler(_ handler: @escaping @Sendable () -> Void) {
      lock.lock()
      backgroundEventsCompletion = handler
      lock.unlock()
    }

    public func putBlob(_ upload: BlobUpload) async throws {
      try await send(BlobRequests.putBlob(upload), fromFile: upload.file)
    }

    public func putBlock(
      _ upload: BlobUpload, blockId: String, offset: Int64, length: Int
    ) async throws {
      let data = try BlobRequests.readSlice(of: upload.file, offset: offset, length: length)
      let scratch = try writeScratch(data, for: upload.target, suffix: "block")
      try await send(BlobRequests.putBlock(upload, blockId: blockId), fromFile: scratch)
    }

    public func putBlockList(_ upload: BlobUpload, blockIds: [String]) async throws {
      let scratch = try writeScratch(
        BlobRequests.blockListBody(blockIds), for: upload.target, suffix: "blocklist")
      try await send(BlobRequests.putBlockList(upload), fromFile: scratch)
    }

    private func writeScratch(_ data: Data, for target: UploadTarget, suffix: String) throws -> URL {
      let name = String(SHA256.hexDigest(of: Data(target.blobLocation.utf8)).prefix(32))
      let url = scratchDirectory.appendingPathComponent("\(name).\(suffix)")
      do {
        try FileManager.default.createDirectory(
          at: scratchDirectory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
      } catch {
        throw BlobTransportError.unreadable("cannot write the upload scratch file")
      }
      return url
    }

    private func send(_ request: URLRequest, fromFile file: URL) async throws {
      guard let session else { throw BlobTransportError.network("no session") }
      let task = session.uploadTask(with: request, fromFile: file)
      let response: URLResponse? = try await withCheckedThrowingContinuation { continuation in
        lock.lock()
        waiting[task.taskIdentifier] = continuation
        lock.unlock()
        task.resume()
      }
      try BlobRequests.check(response)
    }

    // MARK: URLSessionDataDelegate

    public func urlSession(
      _ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?
    ) {
      lock.lock()
      let continuation = waiting.removeValue(forKey: task.taskIdentifier)
      lock.unlock()
      guard let continuation else { return }
      if let error = error as? URLError {
        // URLError descriptions can quote the URL: keep only the code.
        continuation.resume(throwing: BlobTransportError.network("URLError \(error.code.rawValue)"))
      } else if error != nil {
        continuation.resume(throwing: BlobTransportError.network("upload task failed"))
      } else {
        continuation.resume(returning: task.response)
      }
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
      lock.lock()
      let completion = backgroundEventsCompletion
      backgroundEventsCompletion = nil
      lock.unlock()
      if let completion {
        DispatchQueue.main.async { completion() }
      }
    }
  }
#endif

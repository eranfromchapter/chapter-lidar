import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Sends one HTTP request and returns the raw response. Injected into `StationClient` so tests can
/// stub the station; production uses `URLSessionTransport`.
public protocol HTTPTransport: Sendable {
  /// Sends `request`. Throws the URLSession error (for example URLError) when no HTTP response
  /// arrives; an HTTP error status is a normal return.
  func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// `HTTPTransport` on an ephemeral URLSession:
/// - no response cache, no cookies, nothing written to disk;
/// - redirects are never followed (so the bearer token is never forwarded to another URL); a 3xx
///   is returned as is and the client reports it as `StationError.unexpectedStatus`.
public final class URLSessionTransport: HTTPTransport, @unchecked Sendable {
  // @unchecked: `session` is immutable after init and URLSession is thread-safe.
  private let session: URLSession

  public init(timeout: TimeInterval = 30) {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.timeoutIntervalForRequest = timeout
    session = URLSession(
      configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
  }

  deinit {
    session.finishTasksAndInvalidate()
  }

  public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let box = TaskBox()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>) in
        let task = session.dataTask(with: request) { data, response, error in
          if let error {
            continuation.resume(throwing: error)
            return
          }
          guard let http = response as? HTTPURLResponse else {
            continuation.resume(throwing: URLError(.badServerResponse))
            return
          }
          continuation.resume(returning: (data ?? Data(), http))
        }
        box.set(task)
        task.resume()
      }
    } onCancel: {
      box.cancel()
    }
  }
}

/// Holds the running task so cancellation of the Swift task cancels the URLSession task.
private final class TaskBox: @unchecked Sendable {
  private let lock = NSLock()
  private var task: URLSessionTask?
  private var cancelled = false

  func set(_ task: URLSessionTask) {
    lock.lock()
    self.task = task
    let cancelNow = cancelled
    lock.unlock()
    if cancelNow {
      task.cancel()
    }
  }

  func cancel() {
    lock.lock()
    cancelled = true
    let running = task
    lock.unlock()
    running?.cancel()
  }
}

/// Refuses every redirect: the completion handler gets nil, so the 3xx response is delivered.
private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  #if canImport(FoundationNetworking)
    func urlSession(
      _ session: URLSession, task: URLSessionTask,
      willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
      completionHandler: @escaping (URLRequest?) -> Void
    ) {
      completionHandler(nil)
    }
  #else
    func urlSession(
      _ session: URLSession, task: URLSessionTask,
      willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
      completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
      completionHandler(nil)
    }
  #endif
}

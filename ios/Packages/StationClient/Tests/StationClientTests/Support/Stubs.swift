import Foundation
import StationClient
import XCTest

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Repository files the tests read in place (nothing is copied into the package).
enum RepoFiles {
  /// Repository root (this file is ios/Packages/StationClient/Tests/StationClientTests/Support/Stubs.swift).
  static let root: URL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // Stubs.swift
    .deletingLastPathComponent()  // Support
    .deletingLastPathComponent()  // StationClientTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // StationClient
    .deletingLastPathComponent()  // Packages
    .deletingLastPathComponent()  // ios

  static func url(_ relativePath: String) -> URL {
    root.appendingPathComponent(relativePath)
  }

  static func data(_ relativePath: String) throws -> Data {
    try Data(contentsOf: url(relativePath))
  }
}

/// One canned HTTP answer.
struct StubResponse: Sendable {
  var status: Int
  var body: Data
  var contentType: String

  static func json(_ status: Int, _ body: String) -> StubResponse {
    StubResponse(status: status, body: Data(body.utf8), contentType: "application/json")
  }

  static func problem(_ status: Int, code: String, detail: String? = nil) -> StubResponse {
    var object: [String: Any] = [
      "type": "about:blank", "title": "Error", "status": status, "code": code,
    ]
    if let detail { object["detail"] = detail }
    let body = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return StubResponse(status: status, body: body, contentType: "application/problem+json")
  }
}

/// What a stub transport does with one request.
enum StubAction: Sendable {
  case respond(StubResponse)
  case fail(URLError.Code)
}

/// `HTTPTransport` that records every request and answers from a handler.
final class StubTransport: HTTPTransport, @unchecked Sendable {
  private let lock = NSLock()
  private var recorded: [URLRequest] = []
  private let handler: @Sendable (URLRequest, Int) -> StubAction

  /// `handler` gets the request and its zero-based index.
  init(handler: @escaping @Sendable (URLRequest, Int) -> StubAction) {
    self.handler = handler
  }

  /// Answers the requests in order with `actions`; extra requests fail the test with 599.
  convenience init(_ actions: [StubAction]) {
    self.init { _, index in
      index < actions.count ? actions[index] : .respond(.json(599, "{}"))
    }
  }

  var requests: [URLRequest] {
    lock.withLock { recorded }
  }

  func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let index = lock.withLock {
      recorded.append(request)
      return recorded.count - 1
    }
    switch handler(request, index) {
    case .fail(let code):
      throw URLError(code)
    case .respond(let response):
      let http = HTTPURLResponse(
        url: request.url!, statusCode: response.status, httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": response.contentType])!
      return (response.body, http)
    }
  }
}

/// `AccessTokenProvider` that hands out `tokens` in order and records each `forceRefresh`.
final class StubTokenProvider: AccessTokenProvider, @unchecked Sendable {
  struct Failure: Error, Equatable {}

  private let lock = NSLock()
  private var calls: [Bool] = []
  private let tokens: [String]
  private let fails: Bool

  init(tokens: [String] = ["token-1", "token-2", "token-3"], fails: Bool = false) {
    self.tokens = tokens
    self.fails = fails
  }

  var forceRefreshCalls: [Bool] {
    lock.withLock { calls }
  }

  func accessToken(forceRefresh: Bool) async throws -> String {
    let index = lock.withLock {
      calls.append(forceRefresh)
      return calls.count - 1
    }
    if fails { throw Failure() }
    return tokens[min(index, tokens.count - 1)]
  }
}

func makeClient(
  transport: StubTransport, tokens: StubTokenProvider = StubTokenProvider(),
  stationURL: String = "https://station.test"
) throws -> StationClient {
  StationClient(
    configuration: try StationClientConfiguration(stationURL: URL(string: stationURL)!),
    tokenProvider: tokens, transport: transport)
}

/// Runs `body` and returns the error it throws, failing the test when it does not throw.
func captureError(
  file: StaticString = #filePath, line: UInt = #line, _ body: () async throws -> Void
) async -> Error? {
  do {
    try await body()
    XCTFail("expected an error", file: file, line: line)
    return nil
  } catch {
    return error
  }
}

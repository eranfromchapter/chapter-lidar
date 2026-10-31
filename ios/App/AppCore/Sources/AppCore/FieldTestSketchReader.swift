// The field-test build's direct sketch reader (spec F16 3: "Debug field test only, the app").
// DEBUG ONLY: this whole file is compiled only with the DEBUG condition, so a Release build of
// AppCore (and of the app) can never call the Anthropic API or hold a key. In production the
// station holds the key and the phone calls `POST /v1/sketch-interpretations`
// (`StationSketchInterpreter`); a field-test build answers that route in process
// (`UITestStationTransport`) and, when the developer put an API key in the untracked
// `Local.xcconfig`, reads the photo here with the same prompt and reading schema the station
// uses. Raw HTTP: there is no Anthropic SDK for Swift.
#if DEBUG
  import CaptureContract
  import Foundation
  import StationClient

  #if canImport(FoundationNetworking)
    import FoundationNetworking
  #endif

  public enum FieldTestSketchReaderError: Error, Equatable, LocalizedError, CustomStringConvertible {
    /// The prompt or the schema could not be read from the bundle.
    case missingResource(String)
    /// The Anthropic API answered an error (its type and message).
    case api(status: Int, message: String)
    /// Claude declined to read the photo (`stop_reason: refusal`).
    case refused
    /// The answer was cut off (`stop_reason: max_tokens`).
    case truncated
    /// The answer is not a reading (no text block, or JSON that does not decode).
    case unreadableAnswer(String)
    /// The API sent an `error` event in the middle of the stream (its type and message).
    case streamError(String)

    public var description: String {
      switch self {
      case .missingResource(let name): return "The field-test build has no \(name)."
      case .api(let status, let message): return "The Claude API answered \(status): \(message)"
      case .refused: return "Claude declined to read this photo."
      case .truncated: return "Claude's reading was cut off."
      case .unreadableAnswer(let why): return "Claude's reading could not be used: \(why)"
      case .streamError(let message): return "The Claude API stopped the reading: \(message)"
      }
    }

    public var errorDescription: String? { description }
  }

  /// Sends one request and hands back the response's body line by line as it arrives (the
  /// server-sent events of a streamed Messages call; for an error status, the error body).
  public protocol FieldTestLineTransport: Sendable {
    func lines(for request: URLRequest) async throws -> (
      HTTPURLResponse, AsyncThrowingStream<String, Error>
    )
  }

  /// Any `HTTPTransport` as a line transport: the whole body is received, then split into
  /// lines. The tests' transport, and the reader's on Linux.
  public struct BufferedLineTransport: FieldTestLineTransport {
    private let transport: any HTTPTransport

    public init(_ transport: any HTTPTransport) {
      self.transport = transport
    }

    public func lines(for request: URLRequest) async throws -> (
      HTTPURLResponse, AsyncThrowingStream<String, Error>
    ) {
      let (data, response) = try await transport.send(request)
      let text = String(decoding: data, as: UTF8.self)
      let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        .map(String.init)
      return (
        response,
        AsyncThrowingStream { continuation in
          for line in lines { continuation.yield(line) }
          continuation.finish()
        }
      )
    }
  }

  #if !canImport(FoundationNetworking)
    /// The field-test reader's line transport on the phone: `URLSession.bytes(for:)` on an
    /// ephemeral session (no cache, no cookies), its lines as they arrive. Cancelling the
    /// reading's Swift task cancels the request.
    public final class URLSessionLineTransport: FieldTestLineTransport, @unchecked Sendable {
      // @unchecked: `session` is immutable after init and URLSession is thread-safe.
      private let session: URLSession

      public init(timeout: TimeInterval) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        session = URLSession(configuration: configuration)
      }

      deinit {
        session.finishTasksAndInvalidate()
      }

      public func lines(for request: URLRequest) async throws -> (
        HTTPURLResponse, AsyncThrowingStream<String, Error>
      ) {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        let stream = AsyncThrowingStream<String, Error> { continuation in
          let task = Task {
            do {
              for try await line in bytes.lines { continuation.yield(line) }
              continuation.finish()
            } catch {
              continuation.finish(throwing: error)
            }
          }
          continuation.onTermination = { _ in task.cancel() }
        }
        return (http, stream)
      }
    }
  #endif

  /// Calls `POST https://api.anthropic.com/v1/messages` with the photo (an image block) or the
  /// PDF (a document block, every page), the contract prompt as the system prompt and the
  /// reading schema (`$defs/reading` of `sketch-interpretation.schema.json`, its `$ref`s
  /// resolved) as the structured-output format, streamed (a multi-page PDF takes minutes, and a
  /// long non-streamed request risks an HTTP timeout), and wraps the reading as a
  /// `SketchInterpretation`.
  public struct FieldTestSketchReader: Sendable {
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    public static let model = "claude-opus-5-5"
    public static let apiVersion = "2023-06-01"
    /// A 20-page plan report needs about 14k output tokens (thinking included); 16k cut it off.
    public static let maxTokens = 48000
    public static let effort = "medium"
    public static let instruction = "Read this floor-plan sketch."
    public static let documentInstruction = "Read this floor plan."
    public static let pdfMediaType = "application/pdf"
    /// Seconds to wait for Claude (a 20-page PDF takes about 3 minutes).
    public static let timeout: TimeInterval = 600

    private let apiKey: String
    private let systemPrompt: String
    /// The resolved reading schema, as JSON.
    private let readingSchema: Data
    private let transport: any FieldTestLineTransport
    private let now: @Sendable () -> Date

    /// `interpretationSchema`: the bytes of `contract/schema/sketch-interpretation.schema.json`.
    public init(
      apiKey: String, systemPrompt: String, interpretationSchema: Data,
      lineTransport: any FieldTestLineTransport = FieldTestSketchReader.defaultTransport(),
      now: @escaping @Sendable () -> Date = { Date() }
    ) throws {
      self.apiKey = apiKey
      self.systemPrompt = systemPrompt
      self.readingSchema = try Self.readingSchema(from: interpretationSchema)
      self.transport = lineTransport
      self.now = now
    }

    /// The same reader on an `HTTPTransport` (the whole streamed body, then its lines).
    public init(
      apiKey: String, systemPrompt: String, interpretationSchema: Data,
      transport: any HTTPTransport, now: @escaping @Sendable () -> Date = { Date() }
    ) throws {
      try self.init(
        apiKey: apiKey, systemPrompt: systemPrompt, interpretationSchema: interpretationSchema,
        lineTransport: BufferedLineTransport(transport), now: now)
    }

    /// `URLSessionLineTransport` on Apple platforms; a buffered `URLSessionTransport` on Linux.
    public static func defaultTransport() -> any FieldTestLineTransport {
      #if canImport(FoundationNetworking)
        return BufferedLineTransport(URLSessionTransport(timeout: timeout))
      #else
        return URLSessionLineTransport(timeout: timeout)
      #endif
    }

    /// `$defs/reading` of the interpretation schema with every `#/$defs/…` reference replaced by
    /// the definition it names (structured outputs take one self-contained schema).
    public static func readingSchema(from interpretationSchema: Data) throws -> Data {
      guard let root = try JSONSerialization.jsonObject(with: interpretationSchema) as? [String: Any],
        let defs = root["$defs"] as? [String: Any], let reading = defs["reading"]
      else { throw FieldTestSketchReaderError.missingResource("reading schema") }
      func resolve(_ value: Any, depth: Int) throws -> Any {
        guard depth < 32 else { throw FieldTestSketchReaderError.missingResource("finite schema") }
        if let object = value as? [String: Any] {
          if let ref = object["$ref"] as? String {
            let name = ref.replacingOccurrences(of: "#/$defs/", with: "")
            guard let target = defs[name] else {
              throw FieldTestSketchReaderError.missingResource("schema definition \(ref)")
            }
            return try resolve(target, depth: depth + 1)
          }
          var resolved: [String: Any] = [:]
          for (key, item) in object { resolved[key] = try resolve(item, depth: depth + 1) }
          return resolved
        }
        if let array = value as? [Any] {
          return try array.map { try resolve($0, depth: depth + 1) }
        }
        return value
      }
      return try JSONSerialization.data(
        withJSONObject: try resolve(reading, depth: 0), options: [.sortedKeys])
    }

    /// The request as sent: headers `x-api-key`, `anthropic-version`, `content-type`; the body
    /// of `requestBody`.
    public func request(imageData: Data, mediaType: String) throws -> URLRequest {
      var request = URLRequest(url: Self.endpoint)
      request.httpMethod = "POST"
      request.timeoutInterval = Self.timeout
      request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
      request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
      request.setValue("application/json", forHTTPHeaderField: "content-type")
      request.httpBody = try requestBody(imageData: imageData, mediaType: mediaType)
      return request
    }

    /// `{model, max_tokens, stream: true, system, output_config: {effort, format: {type:
    /// json_schema, schema}}, messages: [{role: user, content: [image or document (base64),
    /// text]}]}`. A PDF goes as a `document` block with "Read this floor plan."; a photo as an
    /// `image` block with "Read this floor-plan sketch.". Claude Opus 5.5 always thinks
    /// (adaptive), so no `thinking` is sent; `effort` sets how hard.
    public func requestBody(imageData: Data, mediaType: String) throws -> Data {
      let schema = try JSONSerialization.jsonObject(with: readingSchema)
      let isPDF = mediaType == Self.pdfMediaType
      let source: [String: Any] = [
        "type": "base64", "media_type": mediaType, "data": imageData.base64EncodedString(),
      ]
      let attachment: [String: Any] = ["type": isPDF ? "document" : "image", "source": source]
      let text: [String: Any] = [
        "type": "text", "text": isPDF ? Self.documentInstruction : Self.instruction,
      ]
      let body: [String: Any] = [
        "model": Self.model,
        "max_tokens": Self.maxTokens,
        "stream": true,
        "system": systemPrompt,
        "output_config": [
          "effort": Self.effort,
          "format": ["type": "json_schema", "schema": schema],
        ],
        "messages": [["role": "user", "content": [attachment, text]]],
      ]
      return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    /// Reads the photo or PDF. The interpretation's `image` is the photo's pixel size, or the
    /// PDF's first page in points (`ImageHeader`).
    public func read(imageData: Data, mediaType: String) async throws -> SketchInterpretation {
      let (response, lines) = try await transport.lines(
        for: try request(imageData: imageData, mediaType: mediaType))
      guard response.statusCode == 200 else {
        var body: [String] = []
        for try await line in lines { body.append(line) }
        let text = body.joined(separator: "\n")
        throw FieldTestSketchReaderError.api(
          status: response.statusCode, message: Self.errorMessage(Data(text.utf8)))
      }
      let message = try await Self.collect(lines)
      switch message.stopReason {
      case "refusal": throw FieldTestSketchReaderError.refused
      case "max_tokens": throw FieldTestSketchReaderError.truncated
      case nil: throw FieldTestSketchReaderError.unreadableAnswer("the answer ended early")
      default: break
      }
      guard !message.text.isEmpty else {
        throw FieldTestSketchReaderError.unreadableAnswer("no text block")
      }
      let reading: SketchInterpretation.Reading
      do {
        reading = try CaptureContractJSON.makeDecoder().decode(
          SketchInterpretation.Reading.self, from: Data(message.text.utf8))
      } catch {
        throw FieldTestSketchReaderError.unreadableAnswer("the reading does not match the schema")
      }
      return SketchInterpretation(
        model: message.model ?? Self.model, interpretedAt: UTCTimestamp(now()),
        image: ImageHeader.size(of: imageData) ?? .init(width: 1000, height: 1000),
        reading: reading)
    }

    /// What a streamed answer said: the model (`message_start`), the text of its text blocks
    /// (`content_block_delta` with `text_delta`, in order) and the stop reason
    /// (`message_delta`). Only `data:` lines are read; each is one event's JSON with its
    /// `type`. An `error` event throws `streamError`.
    struct Streamed: Equatable {
      var model: String?
      var text = ""
      var stopReason: String?
    }

    static func collect(_ lines: AsyncThrowingStream<String, Error>) async throws -> Streamed {
      var message = Streamed()
      for try await line in lines {
        guard line.hasPrefix("data:") else { continue }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty else { continue }
        let event: Event
        do {
          event = try JSONDecoder().decode(Event.self, from: Data(payload.utf8))
        } catch {
          throw FieldTestSketchReaderError.unreadableAnswer("an event does not decode")
        }
        switch event.type {
        case "message_start":
          message.model = event.message?.model ?? message.model
        case "content_block_delta":
          if event.delta?.type == "text_delta", let text = event.delta?.text {
            message.text += text
          }
        case "message_delta":
          if let reason = event.delta?.stopReason { message.stopReason = reason }
        case "error":
          let detail = [event.error?.type, event.error?.message].compactMap { $0 }
            .joined(separator: ": ")
          throw FieldTestSketchReaderError.streamError(detail.isEmpty ? "unknown error" : detail)
        default:
          break
        }
      }
      return message
    }

    /// The `error.message` of an API error body, else its first 200 characters.
    static func errorMessage(_ data: Data) -> String {
      struct Body: Decodable {
        struct Detail: Decodable {
          var type: String?
          var message: String?
        }
        var error: Detail?
      }
      if let body = try? JSONDecoder().decode(Body.self, from: data), let error = body.error {
        return [error.type, error.message].compactMap { $0 }.joined(separator: ": ")
      }
      return String(decoding: data.prefix(200), as: UTF8.self)
    }

    /// The parts of a streamed Messages API event this reader uses.
    struct Event: Decodable {
      struct Started: Decodable {
        var model: String?
      }
      struct Delta: Decodable {
        var type: String?
        var text: String?
        var stopReason: String?

        enum CodingKeys: String, CodingKey {
          case type, text
          case stopReason = "stop_reason"
        }
      }
      struct Failure: Decodable {
        var type: String?
        var message: String?
      }
      var type: String
      var message: Started?
      var delta: Delta?
      var error: Failure?
    }
  }
#endif

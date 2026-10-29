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

    public var description: String {
      switch self {
      case .missingResource(let name): return "The field-test build has no \(name)."
      case .api(let status, let message): return "The Claude API answered \(status): \(message)"
      case .refused: return "Claude declined to read this photo."
      case .truncated: return "Claude's reading was cut off."
      case .unreadableAnswer(let why): return "Claude's reading could not be used: \(why)"
      }
    }

    public var errorDescription: String? { description }
  }

  /// Calls `POST https://api.anthropic.com/v1/messages` with the photo, the contract prompt as
  /// the system prompt and the reading schema (`$defs/reading` of
  /// `sketch-interpretation.schema.json`, its `$ref`s resolved) as the structured-output
  /// format, and wraps the reading as a `SketchInterpretation`.
  public struct FieldTestSketchReader: Sendable {
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    public static let model = "claude-opus-5-5"
    public static let apiVersion = "2023-06-01"
    public static let maxTokens = 16000
    public static let effort = "high"
    public static let instruction = "Read this floor-plan sketch."
    /// Seconds to wait for Claude (the station waits 120 s per attempt).
    public static let timeout: TimeInterval = 150

    private let apiKey: String
    private let systemPrompt: String
    /// The resolved reading schema, as JSON.
    private let readingSchema: Data
    private let transport: any HTTPTransport
    private let now: @Sendable () -> Date

    /// `interpretationSchema`: the bytes of `contract/schema/sketch-interpretation.schema.json`.
    public init(
      apiKey: String, systemPrompt: String, interpretationSchema: Data,
      transport: any HTTPTransport = URLSessionTransport(timeout: FieldTestSketchReader.timeout),
      now: @escaping @Sendable () -> Date = { Date() }
    ) throws {
      self.apiKey = apiKey
      self.systemPrompt = systemPrompt
      self.readingSchema = try Self.readingSchema(from: interpretationSchema)
      self.transport = transport
      self.now = now
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

    /// `{model, max_tokens, system, output_config: {effort, format: {type: json_schema, schema}},
    /// messages: [{role: user, content: [image (base64), text]}]}`. Claude Opus 5.5 always
    /// thinks (adaptive), so no `thinking` is sent; `effort` sets how hard.
    public func requestBody(imageData: Data, mediaType: String) throws -> Data {
      let schema = try JSONSerialization.jsonObject(with: readingSchema)
      let body: [String: Any] = [
        "model": Self.model,
        "max_tokens": Self.maxTokens,
        "system": systemPrompt,
        "output_config": [
          "effort": Self.effort,
          "format": ["type": "json_schema", "schema": schema],
        ],
        "messages": [
          [
            "role": "user",
            "content": [
              [
                "type": "image",
                "source": [
                  "type": "base64", "media_type": mediaType,
                  "data": imageData.base64EncodedString(),
                ],
              ],
              ["type": "text", "text": Self.instruction],
            ],
          ]
        ],
      ]
      return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    /// Reads the photo. The interpretation's `image` is the photo's pixel size from its header.
    public func read(imageData: Data, mediaType: String) async throws -> SketchInterpretation {
      let (data, response) = try await transport.send(
        try request(imageData: imageData, mediaType: mediaType))
      guard response.statusCode == 200 else {
        throw FieldTestSketchReaderError.api(
          status: response.statusCode, message: Self.errorMessage(data))
      }
      let message: Message
      do {
        message = try JSONDecoder().decode(Message.self, from: data)
      } catch {
        throw FieldTestSketchReaderError.unreadableAnswer("the message does not decode")
      }
      switch message.stopReason {
      case "refusal": throw FieldTestSketchReaderError.refused
      case "max_tokens": throw FieldTestSketchReaderError.truncated
      default: break
      }
      guard let text = message.content.first(where: { $0.type == "text" })?.text else {
        throw FieldTestSketchReaderError.unreadableAnswer("no text block")
      }
      let reading: SketchInterpretation.Reading
      do {
        reading = try CaptureContractJSON.makeDecoder().decode(
          SketchInterpretation.Reading.self, from: Data(text.utf8))
      } catch {
        throw FieldTestSketchReaderError.unreadableAnswer("the reading does not match the schema")
      }
      return SketchInterpretation(
        model: message.model ?? Self.model, interpretedAt: UTCTimestamp(now()),
        image: ImageHeader.size(of: imageData) ?? .init(width: 1000, height: 1000),
        reading: reading)
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

    /// The parts of a Messages API response this reader uses.
    struct Message: Decodable {
      struct Block: Decodable {
        var type: String
        var text: String?
      }
      var model: String?
      var content: [Block]
      var stopReason: String?

      enum CodingKeys: String, CodingKey {
        case model, content
        case stopReason = "stop_reason"
      }
    }
  }
#endif

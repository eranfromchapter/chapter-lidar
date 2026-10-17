import Foundation

// Wire formats shared by every schema in contract/schema.
// Optional fields are omitted when nil (synthesized Codable uses encodeIfPresent), never null.

/// A UTC timestamp with whole seconds, written as RFC 3339 with `Z`, for example
/// `2026-10-17T14:02:11Z` (the schemas' `dateTime`). Creating one from a `Date` drops the
/// fraction of a second, so what is encoded is exactly what was stored.
public struct UTCTimestamp: Hashable, Comparable, Sendable, Codable, RawRepresentable,
  CustomStringConvertible
{
  /// Whole seconds since 1970-01-01T00:00:00Z.
  public let secondsSince1970: Int64

  public init(secondsSince1970: Int64) {
    self.secondsSince1970 = secondsSince1970
  }

  /// Truncates `date` to the whole second at or before it.
  public init(_ date: Date) {
    secondsSince1970 = Int64(date.timeIntervalSince1970.rounded(.down))
  }

  /// The current time, truncated to whole seconds.
  public static func now() -> UTCTimestamp {
    UTCTimestamp(Date())
  }

  public var date: Date {
    Date(timeIntervalSince1970: TimeInterval(secondsSince1970))
  }

  /// Parses `YYYY-MM-DDTHH:MM:SSZ` only. Fractional seconds, offsets and other layouts fail.
  public init?(rawValue: String) {
    let characters = Array(rawValue.utf8)
    guard characters.count == 20 else { return nil }
    let layout = Array("dddd-dd-ddTdd:dd:ddZ".utf8)
    for (character, expected) in zip(characters, layout) {
      if expected == UInt8(ascii: "d") {
        guard (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(character) else { return nil }
      } else if character != expected {
        return nil
      }
    }
    func number(_ range: Range<Int>) -> Int {
      characters[range].reduce(0) { $0 * 10 + Int($1 - UInt8(ascii: "0")) }
    }
    var components = DateComponents()
    components.year = number(0..<4)
    components.month = number(5..<7)
    components.day = number(8..<10)
    components.hour = number(11..<13)
    components.minute = number(14..<16)
    components.second = number(17..<19)
    guard let date = UTCTimestamp.calendar.date(from: components) else { return nil }
    let parsed = UTCTimestamp(date)
    // Out-of-range fields (month 13, day 32, hour 24, second 60) would be silently normalized
    // by the calendar; formatting back exposes them.
    guard parsed.rawValue == rawValue else { return nil }
    self = parsed
  }

  public var rawValue: String {
    let parts = UTCTimestamp.calendar.dateComponents(
      [.year, .month, .day, .hour, .minute, .second], from: date)
    func pad(_ value: Int?, _ width: Int) -> String {
      let digits = String(value ?? 0)
      return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }
    return "\(pad(parts.year, 4))-\(pad(parts.month, 2))-\(pad(parts.day, 2))T"
      + "\(pad(parts.hour, 2)):\(pad(parts.minute, 2)):\(pad(parts.second, 2))Z"
  }

  public var description: String { rawValue }

  public static func < (lhs: UTCTimestamp, rhs: UTCTimestamp) -> Bool {
    lhs.secondsSince1970 < rhs.secondsSince1970
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let text = try container.decode(String.self)
    guard let value = UTCTimestamp(rawValue: text) else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription:
          "Expected a UTC timestamp with whole seconds like 2026-10-17T14:02:11Z, got \(text)"
      )
    }
    self = value
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  private static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }()
}

/// A UUID written in lowercase, as every schema requires (`Foundation.UUID` encodes uppercase).
/// Decoding accepts the lowercase form only, so a decoded value re-encodes unchanged.
public struct LowercaseUUID: Hashable, Sendable, Codable, RawRepresentable,
  CustomStringConvertible
{
  public let uuid: UUID

  public init(_ uuid: UUID) {
    self.uuid = uuid
  }

  /// A new random UUID.
  public init() {
    uuid = UUID()
  }

  public init?(rawValue: String) {
    guard rawValue.utf8.count == 36, rawValue == rawValue.lowercased(),
      let uuid = UUID(uuidString: rawValue)
    else { return nil }
    self.uuid = uuid
  }

  public var rawValue: String { uuid.uuidString.lowercased() }

  public var description: String { rawValue }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let text = try container.decode(String.self)
    guard let value = LowercaseUUID(rawValue: text) else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Expected a lowercase UUID, got \(text)")
    }
    self = value
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

/// A point, vector or size `[x, y, z]` in metres, written as a three-number array.
public struct Vec3: Hashable, Sendable, Codable {
  public var x: Double
  public var y: Double
  public var z: Double

  public init(x: Double, y: Double, z: Double) {
    self.x = x
    self.y = y
    self.z = z
  }

  public init(from decoder: Decoder) throws {
    var container = try decoder.unkeyedContainer()
    x = try container.decode(Double.self)
    y = try container.decode(Double.self)
    z = try container.decode(Double.self)
    guard container.isAtEnd else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Expected exactly 3 numbers [x, y, z]")
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.unkeyedContainer()
    try container.encode(x)
    try container.encode(y)
    try container.encode(z)
  }
}

/// A rotation quaternion `[x, y, z, w]`, written as a four-number array.
public struct Quaternion: Hashable, Sendable, Codable {
  public var x: Double
  public var y: Double
  public var z: Double
  public var w: Double

  public init(x: Double, y: Double, z: Double, w: Double) {
    self.x = x
    self.y = y
    self.z = z
    self.w = w
  }

  public static let identity = Quaternion(x: 0, y: 0, z: 0, w: 1)

  public init(from decoder: Decoder) throws {
    var container = try decoder.unkeyedContainer()
    x = try container.decode(Double.self)
    y = try container.decode(Double.self)
    z = try container.decode(Double.self)
    w = try container.decode(Double.self)
    guard container.isAtEnd else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Expected exactly 4 numbers [x, y, z, w]")
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.unkeyedContainer()
    try container.encode(x)
    try container.encode(y)
    try container.encode(z)
    try container.encode(w)
  }
}

/// Encoder and decoder settings for contract JSON.
public enum CaptureContractJSON {
  /// Sorted keys (byte-stable output, so a file's SHA-256 does not depend on dictionary order)
  /// and unescaped slashes (package paths stay readable).
  public static func makeEncoder(prettyPrinted: Bool = false) -> JSONEncoder {
    let encoder = JSONEncoder()
    var formatting: JSONEncoder.OutputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    if prettyPrinted {
      formatting.insert(.prettyPrinted)
    }
    encoder.outputFormatting = formatting
    return encoder
  }

  public static func makeDecoder() -> JSONDecoder {
    JSONDecoder()
  }
}

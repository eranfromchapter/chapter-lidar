import Foundation

/// A parsed JSON value. Numbers are doubles; `true` and `1` stay different.
public enum JSON: Equatable, Decodable, CustomStringConvertible {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([JSON])
  case object([String: JSON])

  public static func parse(_ data: Data) throws -> JSON {
    try JSONDecoder().decode(JSON.self, from: data)
  }

  public static func parse(contentsOf url: URL) throws -> JSON {
    try parse(Data(contentsOf: url))
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([JSON].self) {
      self = .array(value)
    } else {
      self = .object(try container.decode([String: JSON].self))
    }
  }

  public subscript(key: String) -> JSON? {
    if case .object(let members) = self { return members[key] }
    return nil
  }

  public subscript(index: Int) -> JSON? {
    if case .array(let values) = self, values.indices.contains(index) { return values[index] }
    return nil
  }

  public var string: String? {
    if case .string(let value) = self { return value }
    return nil
  }

  public var number: Double? {
    if case .number(let value) = self { return value }
    return nil
  }

  public var array: [JSON]? {
    if case .array(let values) = self { return values }
    return nil
  }

  public var numbers: [Double]? {
    array.flatMap { values in
      let numbers = values.compactMap(\.number)
      return numbers.count == values.count ? numbers : nil
    }
  }

  public var description: String {
    switch self {
    case .null: return "null"
    case .bool(let value): return String(value)
    case .number(let value): return String(value)
    case .string(let value): return "\"\(value)\""
    case .array(let values): return "[" + values.map(\.description).joined(separator: ", ") + "]"
    case .object(let members):
      return "{" + members.keys.sorted().map { "\"\($0)\": \(members[$0]!)" }.joined(separator: ", ") + "}"
    }
  }
}

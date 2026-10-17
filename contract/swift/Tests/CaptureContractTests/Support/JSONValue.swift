import Foundation

/// A JSON value for semantic comparison: object key order and number formatting do not matter,
/// but a missing key, an extra key, a `null` or a changed value does.
enum JSONValue: Equatable, CustomStringConvertible {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  static func parse(_ data: Data) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: data)
  }

  var description: String {
    switch self {
    case .null: return "null"
    case .bool(let value): return String(value)
    case .number(let value): return String(value)
    case .string(let value): return "\"\(value)\""
    case .array(let values): return "[" + values.map(\.description).joined(separator: ", ") + "]"
    case .object(let members):
      return "{"
        + members.keys.sorted().map { "\"\($0)\": \(members[$0]!.description)" }
        .joined(separator: ", ") + "}"
    }
  }

  /// True when a `null` appears anywhere in the value. The contract never uses null.
  var containsNull: Bool {
    switch self {
    case .null: return true
    case .bool, .number, .string: return false
    case .array(let values): return values.contains { $0.containsNull }
    case .object(let members): return members.values.contains { $0.containsNull }
    }
  }

  /// Human-readable differences between two values, as JSON pointer paths. Empty when equal.
  func differences(from other: JSONValue, at path: String = "") -> [String] {
    switch (self, other) {
    case (.object(let left), .object(let right)):
      var result: [String] = []
      for key in Set(left.keys).union(right.keys).sorted() {
        let childPath = path + "/" + key
        switch (left[key], right[key]) {
        case (let l?, let r?): result += l.differences(from: r, at: childPath)
        case (_?, nil): result.append("\(childPath): missing after re-encoding")
        case (nil, _?): result.append("\(childPath): added by re-encoding")
        case (nil, nil): break
        }
      }
      return result
    case (.array(let left), .array(let right)):
      guard left.count == right.count else {
        return ["\(path): array length \(left.count) became \(right.count)"]
      }
      return zip(left, right).enumerated().flatMap { index, pair in
        pair.0.differences(from: pair.1, at: "\(path)/\(index)")
      }
    default:
      return self == other ? [] : ["\(path.isEmpty ? "/" : path): \(self) became \(other)"]
    }
  }
}

extension JSONValue: Decodable {
  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else {
      self = .object(try container.decode([String: JSONValue].self))
    }
  }
}

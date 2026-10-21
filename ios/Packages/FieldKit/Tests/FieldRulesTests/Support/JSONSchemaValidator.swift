import Foundation
import XCTest

/// A small JSON Schema (draft 2020-12 subset) validator for the contract schemas, so tests check
/// written files against contract/schema directly. It supports exactly the keywords
/// field-controls.schema.json uses and fails loudly on any other keyword, so a schema change
/// cannot silently pass.
struct JSONSchemaValidator {
  let root: [String: Any]

  /// contract/schema/<name>, found relative to this file
  /// (ios/Packages/FieldKit/Tests/FieldRulesTests/Support).
  static func loadSchema(named name: String) throws -> JSONSchemaValidator {
    let repoRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // Support
      .deletingLastPathComponent()  // FieldRulesTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // FieldKit
      .deletingLastPathComponent()  // Packages
      .deletingLastPathComponent()  // ios
      .deletingLastPathComponent()  // repository root
    let url = repoRoot.appendingPathComponent("contract/schema/\(name)")
    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    guard let schema = object as? [String: Any] else { throw ValidatorError.notAnObject }
    return JSONSchemaValidator(root: schema)
  }

  enum ValidatorError: Error {
    case notAnObject
    case unsupportedKeyword(String)
    case unresolvedReference(String)
  }

  private static let annotationKeywords: Set<String> = [
    "$schema", "$id", "title", "description", "format", "$defs",
  ]
  private static let assertionKeywords: Set<String> = [
    "$ref", "type", "const", "enum", "required", "properties", "additionalProperties", "items",
    "minItems", "uniqueItems", "minLength", "maxLength", "pattern", "exclusiveMinimum", "maximum",
  ]

  /// Validation errors as `path: message`; empty when the instance is valid.
  func validate(data: Data) throws -> [String] {
    let instance = try JSONSerialization.jsonObject(with: data)
    return try validate(instance, against: root, path: "$")
  }

  /// The same against one definition of the schema, `#/$defs/<name>` (a manifest photo entry).
  func validate(data: Data, definition name: String) throws -> [String] {
    let instance = try JSONSerialization.jsonObject(with: data)
    return try validate(instance, against: try resolve("#/$defs/\(name)"), path: "$")
  }

  func validate(_ instance: Any, against schema: [String: Any], path: String) throws -> [String] {
    for key in schema.keys
    where !Self.annotationKeywords.contains(key) && !Self.assertionKeywords.contains(key) {
      throw ValidatorError.unsupportedKeyword(key)
    }
    var errors: [String] = []

    if let reference = schema["$ref"] as? String {
      errors += try validate(instance, against: try resolve(reference), path: path)
    }
    if let type = schema["type"] as? String, !matches(instance, type: type) {
      return errors + ["\(path): expected \(type)"]
    }
    if let expected = schema["const"], !Self.equal(instance, expected) {
      errors.append("\(path): expected constant \(expected)")
    }
    if let allowed = schema["enum"] as? [Any],
      !allowed.contains(where: { Self.equal(instance, $0) })
    {
      errors.append("\(path): \(instance) is not one of \(allowed)")
    }

    if let object = instance as? [String: Any] {
      for name in schema["required"] as? [String] ?? [] where object[name] == nil {
        errors.append("\(path): missing required property \(name)")
      }
      let properties = schema["properties"] as? [String: Any] ?? [:]
      for (name, value) in object {
        if let child = properties[name] as? [String: Any] {
          errors += try validate(value, against: child, path: "\(path).\(name)")
        } else if schema["additionalProperties"] as? Bool == false {
          errors.append("\(path): unexpected property \(name)")
        }
      }
    }

    if let array = instance as? [Any] {
      if let minimum = schema["minItems"] as? Int, array.count < minimum {
        errors.append("\(path): needs at least \(minimum) items")
      }
      if schema["uniqueItems"] as? Bool == true {
        for (index, item) in array.enumerated()
        where array[..<index].contains(where: { Self.equal($0, item) }) {
          errors.append("\(path)[\(index)]: duplicate item")
        }
      }
      if let itemSchema = schema["items"] as? [String: Any] {
        for (index, item) in array.enumerated() {
          errors += try validate(item, against: itemSchema, path: "\(path)[\(index)]")
        }
      }
    }

    if let string = instance as? String {
      let length = string.unicodeScalars.count
      if let minimum = schema["minLength"] as? Int, length < minimum {
        errors.append("\(path): shorter than \(minimum)")
      }
      if let maximum = schema["maxLength"] as? Int, length > maximum {
        errors.append("\(path): longer than \(maximum)")
      }
      if let pattern = schema["pattern"] as? String {
        let expression = try NSRegularExpression(pattern: pattern)
        let range = NSRange(string.startIndex..., in: string)
        if expression.firstMatch(in: string, range: range) == nil {
          errors.append("\(path): '\(string)' does not match \(pattern)")
        }
      }
    }

    if let number = instance as? NSNumber {
      if let minimum = schema["exclusiveMinimum"] as? Double, !(number.doubleValue > minimum) {
        errors.append("\(path): must be greater than \(minimum)")
      }
      if let maximum = schema["maximum"] as? Double, number.doubleValue > maximum {
        errors.append("\(path): must be at most \(maximum)")
      }
    }
    return errors
  }

  private func resolve(_ reference: String) throws -> [String: Any] {
    guard reference.hasPrefix("#/") else { throw ValidatorError.unresolvedReference(reference) }
    var current: Any = root
    for part in reference.dropFirst(2).split(separator: "/") {
      guard let next = (current as? [String: Any])?[String(part)] else {
        throw ValidatorError.unresolvedReference(reference)
      }
      current = next
    }
    guard let schema = current as? [String: Any] else {
      throw ValidatorError.unresolvedReference(reference)
    }
    return schema
  }

  private func matches(_ instance: Any, type: String) -> Bool {
    switch type {
    case "object": return instance is [String: Any]
    case "array": return instance is [Any]
    case "string": return instance is String
    case "number": return instance is NSNumber
    default: return false
    }
  }

  private static func equal(_ left: Any, _ right: Any) -> Bool {
    if let l = left as? String, let r = right as? String { return l == r }
    if let l = left as? NSNumber, let r = right as? NSNumber { return l == r }
    if let l = left as? [String: Any], let r = right as? [String: Any] {
      return l.count == r.count
        && l.allSatisfy { key, value in r[key].map { equal(value, $0) } ?? false }
    }
    if let l = left as? [Any], let r = right as? [Any] {
      return l.count == r.count && zip(l, r).allSatisfy { equal($0, $1) }
    }
    return false
  }
}

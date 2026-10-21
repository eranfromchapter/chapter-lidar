import Foundation

/// A validator for the subset of JSON Schema (2020-12) that the contract schemas use, because
/// Swift has no JSON Schema library in the standard toolchain. Supported keywords: `$ref` (local
/// `#/...` pointers), `type`, `const`, `enum`, `required`, `dependentRequired`, `properties`,
/// `additionalProperties` (false or a schema), `items`, `minItems`, `maxItems`, `minLength`,
/// `maxLength`, `pattern`, `minimum`, `maximum`, `exclusiveMinimum`, `exclusiveMaximum`,
/// `if`/`then`/`else`, `not`,
/// and the boolean schemas `true` and `false`. Any other keyword that would change
/// validation fails loudly (`unsupported keyword`), so a schema change cannot pass silently.
/// `format` and the annotation keywords (`description`, `title`, `$schema`, `$id`, `$defs`) are ignored.
public struct SchemaValidator {
  private let root: JSON

  public init(schemaURL: URL) throws {
    root = try JSON.parse(contentsOf: schemaURL)
  }

  private static let annotations: Set<String> = [
    "$schema", "$id", "$defs", "title", "description", "format",
  ]
  private static let supported: Set<String> = [
    "$ref", "type", "const", "enum", "required", "dependentRequired", "properties",
    "additionalProperties", "items", "minItems", "maxItems", "minLength", "maxLength", "pattern",
    "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "if", "then", "else", "not",
  ]

  /// Problems found in `instance`, as `<json pointer>: <problem>`. Empty when the instance is valid.
  public func validate(_ instance: JSON) -> [String] {
    var errors: [String] = []
    check(instance, against: root, at: "", into: &errors)
    return errors
  }

  public func validate(jsonData: Data) throws -> [String] {
    validate(try JSON.parse(jsonData))
  }

  private func resolve(_ reference: String) -> JSON? {
    guard reference.hasPrefix("#/") else { return nil }
    var current: JSON? = root
    for part in reference.dropFirst(2).split(separator: "/") {
      current = current?[String(part)]
    }
    return current
  }

  private func isValid(_ instance: JSON, against schema: JSON) -> Bool {
    var errors: [String] = []
    check(instance, against: schema, at: "", into: &errors)
    return errors.isEmpty
  }

  private func check(_ instance: JSON, against schema: JSON, at path: String, into errors: inout [String]) {
    func fail(_ message: String) { errors.append("\(path.isEmpty ? "/" : path): \(message)") }
    if case .bool(let allowed) = schema {
      if !allowed { fail("no value is allowed here") }
      return
    }
    guard case .object(let keywords) = schema else { return }

    for key in keywords.keys.sorted()
    where !Self.supported.contains(key) && !Self.annotations.contains(key) {
      fail("unsupported keyword \(key) in the schema")
    }

    if case .string(let reference)? = keywords["$ref"] {
      if let target = resolve(reference) {
        check(instance, against: target, at: path, into: &errors)
      } else {
        fail("cannot resolve \(reference)")
      }
    }
    if let constant = keywords["const"], constant != instance {
      fail("expected \(constant), got \(instance)")
    }
    if case .array(let allowed)? = keywords["enum"], !allowed.contains(instance) {
      fail("\(instance) is not one of \(JSON.array(allowed))")
    }
    if case .string(let type)? = keywords["type"], !matches(type: type, instance) {
      fail("expected \(type), got \(instance)")
    }
    if let not = keywords["not"], isValid(instance, against: not) {
      fail("must not match \(not)")
    }
    if let condition = keywords["if"] {
      if isValid(instance, against: condition) {
        if let then = keywords["then"] { check(instance, against: then, at: path, into: &errors) }
      } else if let otherwise = keywords["else"] {
        check(instance, against: otherwise, at: path, into: &errors)
      }
    }

    switch instance {
    case .object(let members):
      if case .array(let required)? = keywords["required"] {
        for case .string(let name) in required where members[name] == nil {
          fail("missing required \(name)")
        }
      }
      if case .object(let dependencies)? = keywords["dependentRequired"] {
        for (present, needed) in dependencies.sorted(by: { $0.key < $1.key }) where members[present] != nil {
          for case .string(let name) in needed.array ?? [] where members[name] == nil {
            fail("missing \(name), required with \(present)")
          }
        }
      }
      let properties: [String: JSON]
      if case .object(let declared)? = keywords["properties"] { properties = declared } else { properties = [:] }
      if let additional = keywords["additionalProperties"] {
        for (name, value) in members.sorted(by: { $0.key < $1.key }) where properties[name] == nil {
          if case .bool(false) = additional {
            fail("unexpected property \(name)")
          } else {
            check(value, against: additional, at: "\(path)/\(name)", into: &errors)
          }
        }
      }
      for name in members.keys.sorted() {
        if let propertySchema = properties[name], let value = members[name] {
          check(value, against: propertySchema, at: "\(path)/\(name)", into: &errors)
        }
      }
    case .array(let values):
      if case .number(let minimum)? = keywords["minItems"], Double(values.count) < minimum {
        fail("fewer than \(Int(minimum)) items")
      }
      if case .number(let maximum)? = keywords["maxItems"], Double(values.count) > maximum {
        fail("more than \(Int(maximum)) items")
      }
      if let itemSchema = keywords["items"] {
        for (index, value) in values.enumerated() {
          check(value, against: itemSchema, at: "\(path)/\(index)", into: &errors)
        }
      }
    case .string(let text):
      if case .number(let minimum)? = keywords["minLength"], Double(text.count) < minimum {
        fail("shorter than \(Int(minimum)) characters")
      }
      if case .number(let maximum)? = keywords["maxLength"], Double(text.count) > maximum {
        fail("longer than \(Int(maximum)) characters")
      }
      if case .string(let pattern)? = keywords["pattern"] {
        if let expression = try? NSRegularExpression(pattern: pattern) {
          let range = NSRange(text.startIndex..., in: text)
          if expression.firstMatch(in: text, range: range) == nil {
            fail("\"\(text)\" does not match \(pattern)")
          }
        } else {
          fail("pattern \(pattern) is not a valid regular expression")
        }
      }
    case .number(let value):
      if case .number(let minimum)? = keywords["minimum"], value < minimum {
        fail("\(value) is below \(minimum)")
      }
      if case .number(let maximum)? = keywords["maximum"], value > maximum {
        fail("\(value) is above \(maximum)")
      }
      if case .number(let minimum)? = keywords["exclusiveMinimum"], value <= minimum {
        fail("\(value) is not above \(minimum)")
      }
      if case .number(let maximum)? = keywords["exclusiveMaximum"], value >= maximum {
        fail("\(value) is not below \(maximum)")
      }
    default:
      break
    }
  }

  private func matches(type: String, _ instance: JSON) -> Bool {
    switch (type, instance) {
    case ("object", .object), ("array", .array), ("string", .string), ("boolean", .bool),
      ("number", .number), ("null", .null):
      return true
    case ("integer", .number(let value)):
      return value == value.rounded()
    default:
      return false
    }
  }
}

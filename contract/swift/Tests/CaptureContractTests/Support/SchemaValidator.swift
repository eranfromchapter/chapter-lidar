import Foundation

// The union of ios/Packages/CaptureCore/Sources/CaptureTestSupport/SchemaValidator.swift and
// ios/Packages/PackageKit/Tests/PackageKitTests/Support/SchemaValidator.swift (this package has
// no dependencies), on `JSONValue`, plus `contains`, which verdict.schema.json uses.

/// A validator for the subset of JSON Schema (2020-12) that the contract schemas use, because
/// Swift has no JSON Schema library in the standard toolchain. Supported keywords: `$ref` (local
/// `#/...` pointers), `type`, `const`, `enum`, `required`, `dependentRequired`, `properties`,
/// `additionalProperties` (false or a schema), `items`, `contains`, `minItems`, `maxItems`,
/// `uniqueItems`, `minLength`, `maxLength`, `pattern`, `minimum`, `maximum`, `exclusiveMinimum`,
/// `exclusiveMaximum`, `if`/`then`/`else`, `not`, `allOf`, `anyOf`, and the boolean schemas `true`
/// and `false`. Any other keyword that would change validation fails loudly (`unsupported
/// keyword`), so a schema change cannot pass silently. `format` and the annotation keywords
/// (`description`, `title`, `$schema`, `$id`, `$defs`) are ignored.
struct SchemaValidator {
  private let root: JSONValue

  init(schemaURL: URL) throws {
    root = try JSONValue.parse(Data(contentsOf: schemaURL))
  }

  private static let annotations: Set<String> = [
    "$schema", "$id", "$defs", "title", "description", "format",
  ]
  private static let supported: Set<String> = [
    "$ref", "type", "const", "enum", "required", "dependentRequired", "properties",
    "additionalProperties", "items", "contains", "minItems", "maxItems", "uniqueItems",
    "minLength", "maxLength", "pattern", "minimum", "maximum", "exclusiveMinimum",
    "exclusiveMaximum", "if", "then", "else", "not", "allOf", "anyOf",
  ]

  /// Problems found in `instance`, as `<json pointer>: <problem>`. Empty when it is valid.
  func validate(_ instance: JSONValue) -> [String] {
    var errors: [String] = []
    check(instance, against: root, at: "", into: &errors)
    return errors
  }

  func validate(jsonData: Data) throws -> [String] {
    validate(try JSONValue.parse(jsonData))
  }

  private func resolve(_ reference: String) -> JSONValue? {
    guard reference.hasPrefix("#/") else { return nil }
    var current: JSONValue? = root
    for part in reference.dropFirst(2).split(separator: "/") {
      guard case .object(let members)? = current else { return nil }
      current = members[String(part)]
    }
    return current
  }

  private func isValid(_ instance: JSONValue, against schema: JSONValue) -> Bool {
    var errors: [String] = []
    check(instance, against: schema, at: "", into: &errors)
    return errors.isEmpty
  }

  private func check(
    _ instance: JSONValue, against schema: JSONValue, at path: String, into errors: inout [String]
  ) {
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
      fail("\(instance) is not one of \(JSONValue.array(allowed))")
    }
    if case .string(let type)? = keywords["type"], !matches(type: type, instance) {
      fail("expected \(type), got \(instance)")
    }
    if let not = keywords["not"], isValid(instance, against: not) {
      fail("must not match \(not)")
    }
    if case .array(let all)? = keywords["allOf"] {
      for subschema in all {
        check(instance, against: subschema, at: path, into: &errors)
      }
    }
    if case .array(let any)? = keywords["anyOf"],
      !any.contains(where: { isValid(instance, against: $0) })
    {
      fail("matches none of anyOf")
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
        for (present, needed) in dependencies.sorted(by: { $0.key < $1.key })
        where members[present] != nil {
          guard case .array(let names) = needed else { continue }
          for case .string(let name) in names where members[name] == nil {
            fail("missing \(name), required with \(present)")
          }
        }
      }
      let properties: [String: JSONValue]
      if case .object(let declared)? = keywords["properties"] {
        properties = declared
      } else {
        properties = [:]
      }
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
      if case .bool(true)? = keywords["uniqueItems"] {
        for (index, value) in values.enumerated() where values[..<index].contains(value) {
          fail("item \(index) repeats an earlier item")
        }
      }
      if let itemSchema = keywords["items"] {
        for (index, value) in values.enumerated() {
          check(value, against: itemSchema, at: "\(path)/\(index)", into: &errors)
        }
      }
      if let containsSchema = keywords["contains"],
        !values.contains(where: { isValid($0, against: containsSchema) })
      {
        fail("no item matches contains")
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

  private func matches(type: String, _ instance: JSONValue) -> Bool {
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

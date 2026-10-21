import Foundation
import XCTest

/// Locates the shared contract files in the repository. Nothing is copied into the package:
/// the tests read contract/schema and contract/examples in place, the same files the
/// TypeScript package tests read.
enum ContractFiles {
  /// contract/ (this file is contract/swift/Tests/CaptureContractTests/Support/ContractFiles.swift).
  static let contractDirectory: URL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // Support
    .deletingLastPathComponent()  // CaptureContractTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // swift
    .deletingLastPathComponent()  // contract

  static let schemaDirectory = contractDirectory.appendingPathComponent("schema", isDirectory: true)
  static let examplesDirectory = contractDirectory.appendingPathComponent(
    "examples", isDirectory: true)
  static let testVectorsDirectory = contractDirectory.appendingPathComponent(
    "test-vectors", isDirectory: true)

  static func schemaURL(_ fileName: String) -> URL {
    schemaDirectory.appendingPathComponent(fileName)
  }

  /// Names of every `*.schema.json` file, without the `.schema.json` suffix, sorted.
  static func schemaNames() throws -> [String] {
    let suffix = ".schema.json"
    return try FileManager.default.contentsOfDirectory(atPath: schemaDirectory.path)
      .filter { $0.hasSuffix(suffix) }
      .map { String($0.dropLast(suffix.count)) }
      .sorted()
  }

  /// Names of every example folder (one per schema), sorted.
  static func exampleFolderNames() throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: examplesDirectory.path)
      .filter { name in
        var isDirectory: ObjCBool = false
        let path = examplesDirectory.appendingPathComponent(name).path
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
          && isDirectory.boolValue
      }
      .sorted()
  }

  /// Every `*.json` file in contract/examples/<schema>/<kind>/, sorted by name.
  static func examples(schema: String, kind: String) throws -> [URL] {
    let directory =
      examplesDirectory
      .appendingPathComponent(schema, isDirectory: true)
      .appendingPathComponent(kind, isDirectory: true)
    return try FileManager.default.contentsOfDirectory(atPath: directory.path)
      .filter { $0.hasSuffix(".json") }
      .sorted()
      .map { directory.appendingPathComponent($0) }
  }

  /// Parses a JSON file into a loosely typed object tree.
  static func jsonObject(at url: URL) throws -> Any {
    try JSONSerialization.jsonObject(with: Data(contentsOf: url))
  }
}

/// Reads nested values out of a parsed schema with readable failures.
struct SchemaReader {
  let root: Any
  let name: String

  init(fileName: String) throws {
    root = try ContractFiles.jsonObject(at: ContractFiles.schemaURL(fileName))
    name = fileName
  }

  /// Follows a key path through nested objects, for example ["$defs", "role", "enum"].
  func value(at path: [String], file: StaticString = #filePath, line: UInt = #line) throws -> Any {
    var current: Any = root
    for key in path {
      guard let object = current as? [String: Any], let next = object[key] else {
        XCTFail("\(name): no value at \(path.joined(separator: "."))", file: file, line: line)
        throw SchemaReaderError.missing(path)
      }
      current = next
    }
    return current
  }

  func strings(at path: [String], file: StaticString = #filePath, line: UInt = #line) throws
    -> [String]
  {
    let value = try value(at: path, file: file, line: line)
    guard let strings = value as? [String] else {
      XCTFail(
        "\(name): \(path.joined(separator: ".")) is not a list of strings", file: file, line: line)
      throw SchemaReaderError.wrongType(path)
    }
    return strings
  }

  func string(at path: [String], file: StaticString = #filePath, line: UInt = #line) throws
    -> String
  {
    let value = try value(at: path, file: file, line: line)
    guard let string = value as? String else {
      XCTFail("\(name): \(path.joined(separator: ".")) is not a string", file: file, line: line)
      throw SchemaReaderError.wrongType(path)
    }
    return string
  }
}

enum SchemaReaderError: Error {
  case missing([String])
  case wrongType([String])
}

import CaptureContract
import Foundation
import PackageCore
import XCTest

/// The shared fixtures in fixtures/generated, read in place (nothing is copied into the package).
enum Fixtures {
  /// The repository root (this file is ios/Packages/PackageKit/Tests/PackageKitTests/Support/Fixtures.swift).
  static let repositoryRoot: URL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // Support
    .deletingLastPathComponent()  // PackageKitTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // PackageKit
    .deletingLastPathComponent()  // Packages
    .deletingLastPathComponent()  // ios
    .deletingLastPathComponent()  // repository root

  static var generatedDirectory: URL {
    repositoryRoot.appendingPathComponent("fixtures/generated", isDirectory: true)
  }

  static func schemaURL(_ fileName: String) -> URL {
    repositoryRoot.appendingPathComponent("contract/schema/\(fileName)")
  }

  static func manifestValidator() throws -> SchemaValidator {
    try SchemaValidator(schemaURL: schemaURL("manifest.schema.json"))
  }
}

/// One generated fixture package (`fixtures/generated/<name>/package`).
struct FixturePackage {
  let name: String
  let root: URL
  let manifest: PackageManifest
  let manifestData: Data

  init(_ name: String) throws {
    self.name = name
    root = Fixtures.generatedDirectory.appendingPathComponent("\(name)/package", isDirectory: true)
    let register = root.appendingPathComponent("Source Register", isDirectory: true)
    let visits = try FileManager.default.contentsOfDirectory(atPath: register.path)
    guard visits.count == 1, let visit = visits.first else {
      throw FixtureError("fixture \(name) has \(visits.count) Source Register folders")
    }
    let url = register.appendingPathComponent(visit).appendingPathComponent("manifest.json")
    manifestData = try Data(contentsOf: url)
    manifest = try CaptureContractJSON.makeDecoder().decode(PackageManifest.self, from: manifestData)
  }

  var visitId: LowercaseUUID { manifest.visitId }

  func url(for path: String) -> URL {
    var url = root
    for segment in path.split(separator: "/") { url.appendPathComponent(String(segment)) }
    return url
  }

  /// Captures of the visit, from the fixture's capture record.
  func captures() throws -> [CaptureRef] {
    let path = "Source Register/\(visitId.rawValue)/capture-record.json"
    let record = try JSON.parse(contentsOf: url(for: path))
    return try (record["captures"]?.array ?? []).map { capture in
      guard let id = capture["captureId"]?.string, let captureId = LowercaseUUID(rawValue: id),
        let areaKey = capture["areaKey"]?.string
      else { throw FixtureError("capture without captureId or areaKey") }
      return CaptureRef(captureId: captureId, areaKey: areaKey)
    }
  }

  /// Every file of the fixture except its manifest, as package paths.
  func filePaths() -> [String] {
    manifest.files.map(\.path)
  }
}

struct FixtureError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}

/// Builds a draft from a fixture's files the way the app does: visit files first, then per capture
/// the CaptureCore raw exports and model, the PlanExport and MeshExport files derived from them,
/// and the labeled site photos. Roles, mimes and `derivedFrom` come from this table, not from the
/// fixture's manifest; only the photo labels (FieldKit's photo records in the app) are read from it.
enum FixtureDraft {
  struct Spec {
    let fileName: String
    let role: FileRole
    let mime: String
    let component: String
    let derivedFrom: [String]
  }

  static let perCapture: [Spec] = [
    Spec(fileName: "roomplan.json", role: .rawRoomplanJSON, mime: "application/json", component: "CaptureCore", derivedFrom: []),
    Spec(fileName: "depth-samples.bin", role: .rawDepth, mime: "application/octet-stream", component: "CaptureCore", derivedFrom: []),
    Spec(fileName: "capture-model.json", role: .captureModel, mime: "application/json", component: "CaptureCore", derivedFrom: ["roomplan.json"]),
    Spec(fileName: "plan.dxf", role: .planDXF, mime: "image/vnd.dxf", component: "PlanExport", derivedFrom: ["capture-model.json"]),
    Spec(fileName: "rooms.csv", role: .roomsCSV, mime: "text/csv", component: "PlanExport", derivedFrom: ["capture-model.json"]),
    Spec(fileName: "plan-sheet.pdf", role: .planPDF, mime: "application/pdf", component: "PlanExport", derivedFrom: ["capture-model.json"]),
    Spec(fileName: "plan.png", role: .planPNG, mime: "image/png", component: "PlanExport", derivedFrom: ["capture-model.json"]),
    Spec(fileName: "plan.svg", role: .planSVG, mime: "image/svg+xml", component: "PlanExport", derivedFrom: ["capture-model.json"]),
    Spec(fileName: "mesh.glb", role: .meshGLB, mime: "model/gltf-binary", component: "MeshExport", derivedFrom: ["capture-model.json"]),
    Spec(fileName: "mesh.obj", role: .meshOBJ, mime: "model/obj", component: "MeshExport", derivedFrom: ["capture-model.json"]),
    Spec(fileName: "mesh.mtl", role: .meshMTL, mime: "model/mtl", component: "MeshExport", derivedFrom: ["capture-model.json"]),
    Spec(fileName: "mesh-texture.png", role: .texture, mime: "image/png", component: "MeshExport", derivedFrom: []),
    Spec(fileName: "points.las", role: .pointCloudLAS, mime: "application/vnd.las", component: "MeshExport", derivedFrom: ["depth-samples.bin"]),
  ]

  /// A draft of `fixture`. `source` maps a fixture package path to the file to read (defaults to
  /// the fixture file itself). `visitId` defaults to the fixture's.
  static func make(
    _ fixture: FixturePackage,
    visitId: LowercaseUUID? = nil,
    packageId: LowercaseUUID = LowercaseUUID(),
    generatorPrefix: String = "chapter-fixtures/",
    generatorVersion: String = "1.0.0",
    source: ((String) -> URL)? = nil
  ) throws -> PackageDraft {
    let fixtureVisit = fixture.visitId.rawValue
    let locate = source ?? { fixture.url(for: $0) }
    var draft = PackageDraft(visitId: visitId ?? fixture.visitId, packageId: packageId)

    try draft.add(
      PackageFileInput(
        source: locate("Source Register/\(fixtureVisit)/capture-record.json"),
        role: .captureRecord, fileName: "capture-record.json", mime: "application/json",
        generator: generatorPrefix + "CaptureRecord", generatorVersion: generatorVersion))
    try draft.add(
      PackageFileInput(
        source: locate("Field Measurements/\(fixtureVisit)/field-controls.json"),
        role: .fieldControls, fileName: "field-controls.json", mime: "application/json",
        generator: generatorPrefix + "FieldControls", generatorVersion: generatorVersion))

    let photoLabels = Dictionary(
      fixture.manifest.files.compactMap { file in file.photo.map { (file.path, $0) } },
      uniquingKeysWith: { first, _ in first })

    for capture in try fixture.captures() {
      let folder = "Original Exports/\(capture.areaKey)/\(capture.captureId.rawValue)/"
      var paths: [String: String] = [:]
      for spec in perCapture {
        let path = try draft.add(
          PackageFileInput(
            source: locate(folder + spec.fileName), role: spec.role, fileName: spec.fileName,
            capture: capture, mime: spec.mime, generator: generatorPrefix + spec.component,
            generatorVersion: generatorVersion,
            derivedFrom: try spec.derivedFrom.map { name in
              guard let path = paths[name] else { throw FixtureError("\(name) not added yet") }
              return path
            }))
        paths[spec.fileName] = path
      }
      let photoFolder = "Site Photos/\(capture.areaKey)/\(capture.captureId.rawValue)/"
      let photoNames = try FileManager.default.contentsOfDirectory(
        atPath: fixture.url(for: String(photoFolder.dropLast())).path
      ).sorted()
      for name in photoNames {
        guard let labels = photoLabels[photoFolder + name] else {
          throw FixtureError("no labels for \(photoFolder + name)")
        }
        try draft.add(
          PackageFileInput(
            source: locate(photoFolder + name), role: .photo, fileName: name, capture: capture,
            mime: "image/jpeg", generator: generatorPrefix + "FieldKit",
            generatorVersion: generatorVersion, photo: labels))
      }
    }
    return draft
  }
}

/// A temporary folder per test. Sealed packages are read-only, so cleanup makes them writable
/// first (test scaffolding only; PackageKit itself never deletes).
final class TemporaryFolder {
  let url: URL

  init() throws {
    url = FileManager.default.temporaryDirectory
      .appendingPathComponent("packagekit-tests-\(UUID().uuidString.lowercased())", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  func remove() {
    let fileManager = FileManager.default
    if let enumerator = fileManager.enumerator(atPath: url.path) {
      for case let path as String in enumerator {
        let item = url.appendingPathComponent(path).path
        // Never through a symbolic link: setAttributes follows links, and a test's links point
        // at fixture files outside this folder.
        guard let attributes = try? fileManager.attributesOfItem(atPath: item),
          attributes[.type] as? FileAttributeType != .typeSymbolicLink
        else { continue }
        try? fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: item)
      }
    }
    try? fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: url.path)
    try? fileManager.removeItem(at: url)
  }
}

/// SHA-256 of every file under `root`, keyed by package path.
func fingerprints(under root: URL) throws -> [String: FileDigest] {
  var result: [String: FileDigest] = [:]
  let fileManager = FileManager.default
  guard let enumerator = fileManager.enumerator(atPath: root.path) else { return result }
  for case let path as String in enumerator {
    var isDirectory: ObjCBool = false
    let url = root.appendingPathComponent(path)
    guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue
    else { continue }
    result[path] = try FileDigest.of(fileAt: url)
  }
  return result
}

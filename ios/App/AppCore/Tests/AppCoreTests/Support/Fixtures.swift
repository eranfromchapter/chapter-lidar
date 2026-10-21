import CaptureContract
import FieldRules
import Foundation
import PhotoStore
import XCTest

@testable import AppCore

/// The generated fixtures, read in place.
enum Fixtures {
  /// Repository root (this file is ios/App/AppCore/Tests/AppCoreTests/Support/Fixtures.swift).
  static let repositoryRoot: URL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // Support
    .deletingLastPathComponent()  // AppCoreTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // AppCore
    .deletingLastPathComponent()  // App
    .deletingLastPathComponent()  // ios
    .deletingLastPathComponent()  // repository root

  static func package(_ name: String) -> URL {
    repositoryRoot.appendingPathComponent("fixtures/generated/\(name)/package", isDirectory: true)
  }

  static func url(_ root: URL, _ path: String) -> URL {
    var url = root
    for segment in path.split(separator: "/") { url.appendPathComponent(String(segment)) }
    return url
  }

  static func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("appcore-tests-\(UUID().uuidString.lowercased())", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  /// Removes a temporary folder that holds sealed (read-only) packages: makes everything
  /// writable first (test scaffolding only; the app never deletes).
  static func removeTemporaryDirectory(_ url: URL) {
    let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
    while let item = enumerator?.nextObject() as? URL {
      try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: item.path)
    }
    try? FileManager.default.removeItem(at: url)
  }

  static func manifestValidator() throws -> SchemaValidator {
    try SchemaValidator(
      schemaURL: repositoryRoot.appendingPathComponent("contract/schema/manifest.schema.json"))
  }
}

/// A visit on the "phone" built from a fixture package: the fixture's raw originals copied where
/// CaptureFlowModel writes them, its photos saved through PhotoRecordStore and its capture record
/// and field controls decoded. What the app has in hand when "Before you leave" passes.
struct FixtureVisit {
  let workspace: VisitWorkspace
  let record: CaptureRecord
  let controls: FieldControls
  let photos: [PhotoRecord]
  let manifest: PackageManifest

  init(_ name: String, in base: URL) throws {
    let root = Fixtures.package(name)
    let register = root.appendingPathComponent("Source Register", isDirectory: true)
    let visit = try XCTUnwrap(FileManager.default.contentsOfDirectory(atPath: register.path).first)
    let decoder = CaptureContractJSON.makeDecoder()
    manifest = try decoder.decode(
      PackageManifest.self,
      from: Data(contentsOf: register.appendingPathComponent("\(visit)/manifest.json")))
    record = try decoder.decode(
      CaptureRecord.self,
      from: Data(contentsOf: register.appendingPathComponent("\(visit)/capture-record.json")))
    let controlsEntry = try XCTUnwrap(manifest.files.first { $0.role == .fieldControls })
    controls = try decoder.decode(
      FieldControls.self, from: Data(contentsOf: Fixtures.url(root, controlsEntry.path)))

    workspace = try VisitWorkspace.create(in: base)
    let builder = VisitPackageBuilder(workspace: workspace, appVersion: "1.0.0")
    for capture in record.captures {
      let target = builder.originalsDirectory(of: capture)
      try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
      for name in ["roomplan.json", "depth-samples.bin"] {
        let path = "Original Exports/\(capture.areaKey)/\(capture.captureId.rawValue)/\(name)"
        try FileManager.default.copyItem(
          at: Fixtures.url(root, path), to: target.appendingPathComponent(name))
      }
    }

    let store = try PhotoRecordStore(files: DiskPhotoFileStore(root: workspace.photosRoot))
    var saved: [PhotoRecord] = []
    for entry in manifest.files where entry.role == .photo {
      let captureId = try XCTUnwrap(entry.captureId)
      let areaKey = try XCTUnwrap(entry.areaKey)
      saved.append(
        try store.save(
          original: Data(contentsOf: Fixtures.url(root, entry.path)),
          capture: FieldControls.CaptureRef(captureId: captureId, areaKey: areaKey),
          labels: try XCTUnwrap(entry.photo)))
    }
    photos = saved
  }

  /// The manifest of a fixture package folder.
  static func manifest(of root: URL) throws -> PackageManifest {
    let register = root.appendingPathComponent("Source Register", isDirectory: true)
    let visit = try XCTUnwrap(FileManager.default.contentsOfDirectory(atPath: register.path).first)
    return try CaptureContractJSON.makeDecoder().decode(
      PackageManifest.self,
      from: Data(contentsOf: register.appendingPathComponent("\(visit)/manifest.json")))
  }

  /// SHA-256 of every original the phone holds for this visit (raw scan files and photos).
  func originalDigests() throws -> [String: String] {
    var digests: [String: String] = [:]
    for root in [workspace.originalsRoot, workspace.photosRoot] {
      let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
      while let url = enumerator?.nextObject() as? URL {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
          !isDirectory.boolValue
        else { continue }
        digests[url.path] = PhotoStore.SHA256.hexDigest(of: try Data(contentsOf: url))
      }
    }
    return digests
  }
}

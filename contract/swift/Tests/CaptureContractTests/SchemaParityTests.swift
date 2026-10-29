import CaptureContract
import Foundation
import XCTest

/// AC3: the Swift enums and folder layout match contract/schema exactly. Each test reads the
/// schema file and fails on any value that is missing in Swift or extra in Swift.
final class SchemaParityTests: XCTestCase {
  // MARK: Roles

  func testFileRoleMatchesManifestRoleEnum() throws {
    let manifest = try SchemaReader(fileName: "manifest.schema.json")
    try assertSameValues(
      FileRole.allCases.map(\.rawValue), try manifest.strings(at: ["$defs", "role", "enum"]),
      "FileRole vs manifest.schema.json $defs.role.enum")
  }

  func testVisitRolesMatchManifestVisitRoleEnum() throws {
    let manifest = try SchemaReader(fileName: "manifest.schema.json")
    try assertSameValues(
      FileRole.visitRoles.map(\.rawValue),
      try manifest.strings(at: ["$defs", "visitRole", "enum"]),
      "FileRole.visitRoles vs manifest.schema.json $defs.visitRole.enum")
    for role in FileRole.allCases {
      XCTAssertEqual(role.isVisitWide, FileRole.visitRoles.contains(role), "\(role).isVisitWide")
    }
  }

  func testGeometrySourceRoleMatchesCaptureModelSchema() throws {
    let model = try SchemaReader(fileName: "capture-model.schema.json")
    try assertSameValues(
      GeometrySourceRole.allCases.map(\.rawValue),
      try model.strings(at: ["$defs", "sourceRole", "enum"]),
      "GeometrySourceRole vs capture-model.schema.json $defs.sourceRole.enum")
    for source in GeometrySourceRole.allCases {
      XCTAssertEqual(source.fileRole.rawValue, source.rawValue, "\(source).fileRole")
    }
  }

  // MARK: Folder layout

  func testLayoutConstantsMatchLayoutJSON() throws {
    let layout = try SchemaReader(fileName: "layout.json")
    XCTAssertEqual(PackageLayout.version, try layout.string(at: ["layoutVersion"]))
    XCTAssertEqual(PackageLayout.manifestPathTemplate, try layout.string(at: ["manifestPath"]))

    let fileNames = try XCTUnwrap(
      try layout.value(at: ["fileNames"]) as? [String: String], "layout.json fileNames")
    XCTAssertEqual(
      fileNames,
      [
        "capture_record": PackageLayout.captureRecordFileName,
        "capture_model": PackageLayout.captureModelFileName,
        "field_controls": PackageLayout.fieldControlsFileName,
        "manifest": PackageLayout.manifestFileName,
        "sketch_measurements": PackageLayout.sketchMeasurementsFileName,
        "walkthrough_log": PackageLayout.walkthroughLogFileName,
      ],
      "PackageLayout file names vs layout.json fileNames")

    let manifest = try SchemaReader(fileName: "manifest.schema.json")
    XCTAssertEqual(
      LayoutVersion.allCases.map(\.rawValue),
      [try manifest.string(at: ["properties", "layoutVersion", "const"])],
      "LayoutVersion vs manifest.schema.json layoutVersion const")
    XCTAssertEqual(LayoutVersion.current.rawValue, PackageLayout.version)
  }

  func testFoldersMatchLayoutJSON() throws {
    let folders = try layoutFolders()
    try assertSameValues(
      PackageFolder.allCases.map(\.rawValue), folders.map { try string($0, "id") },
      "PackageFolder vs layout.json folders[].id")

    for entry in folders {
      let id = try string(entry, "id")
      guard let folder = PackageFolder(rawValue: id) else { continue }
      XCTAssertEqual(folder.name, try string(entry, "name"), "\(id).name")
      XCTAssertEqual(folder.pathTemplate, try string(entry, "pathTemplate"), "\(id).pathTemplate")
      XCTAssertEqual(folder.scope.rawValue, try string(entry, "scope"), "\(id).scope")
      XCTAssertEqual(
        folder.producedBy.rawValue, try string(entry, "producedBy"), "\(id).producedBy")
      XCTAssertEqual(folder.groupBy.map(\.rawValue), try strings(entry, "groupBy"), "\(id).groupBy")
      try assertSameValues(
        folder.roles.map(\.rawValue), try strings(entry, "roles"), "\(id).roles")
    }
  }

  func testFolderScopeAndProducerEnumsCoverLayoutJSON() throws {
    let folders = try layoutFolders()
    try assertSameValues(
      FolderScope.allCases.map(\.rawValue), Array(Set(try folders.map { try string($0, "scope") })),
      "FolderScope vs layout.json scope values")
    try assertSameValues(
      FolderProducer.allCases.map(\.rawValue),
      Array(Set(try folders.map { try string($0, "producedBy") })),
      "FolderProducer vs layout.json producedBy values")
    try assertSameValues(
      FolderGroupKey.allCases.map(\.rawValue),
      Array(Set(try folders.flatMap { try strings($0, "groupBy") })),
      "FolderGroupKey vs layout.json groupBy values")
  }

  func testVisitScopedFoldersHoldExactlyTheVisitRoles() throws {
    let folders = try layoutFolders()
    let visitRolesInLayout = try folders.filter { try string($0, "scope") == "visit" }
      .flatMap { try strings($0, "roles") }
    try assertSameValues(
      FileRole.visitRoles.map(\.rawValue), visitRolesInLayout,
      "FileRole.visitRoles vs roles of layout.json folders with scope visit")
  }

  func testEveryRoleBelongsToExactlyOneFolder() throws {
    let rolesInLayout = try layoutFolders().flatMap { try strings($0, "roles") }
    XCTAssertEqual(
      rolesInLayout.count, Set(rolesInLayout).count, "layout.json lists a role in two folders")
    try assertSameValues(
      FileRole.allCases.map(\.rawValue), rolesInLayout, "FileRole vs every role in layout.json")
    for role in FileRole.allCases {
      let owners = PackageFolder.allCases.filter { $0.roles.contains(role) }
      guard owners.count == 1 else {
        XCTFail("\(role) is in \(owners.count) Swift folders, expected exactly 1")
        continue
      }
      XCTAssertEqual(owners, [role.folder], "\(role) folder")
      XCTAssertEqual(role.folder.scope == .visit, role.isVisitWide, "\(role) scope")
    }
  }

  // MARK: Schema versions

  /// Each document's Swift version type against its own schema's `schemaVersion`: a `const` for
  /// one version, an `enum` for several.
  func testEachDocumentsSchemaVersionsMatchItsSchema() throws {
    let versions: [String: [String]] = [
      "capture-record": CaptureRecordSchemaVersion.allCases.map(\.rawValue),
      "capture-model": CaptureModelSchemaVersion.allCases.map(\.rawValue),
      "field-controls": SchemaVersion.allCases.map(\.rawValue),
      "manifest": ManifestSchemaVersion.allCases.map(\.rawValue),
      "sketch-measurements": SketchMeasurementsSchemaVersion.allCases.map(\.rawValue),
      "walkthrough-log": WalkthroughLogSchemaVersion.allCases.map(\.rawValue),
      "verdict": SchemaVersion.allCases.map(\.rawValue),
    ]
    XCTAssertEqual(
      Set(versions.keys), Set(try ContractFiles.schemaNames()), "a version type for every schema")
    for (name, swift) in versions.sorted(by: { $0.key < $1.key }) {
      let schema = try SchemaReader(fileName: "\(name).schema.json")
      let property = try XCTUnwrap(
        try schema.value(at: ["properties", "schemaVersion"]) as? [String: Any],
        "\(name) schemaVersion")
      let values: [String]
      if let single = property["const"] as? String {
        values = [single]
      } else {
        values = try XCTUnwrap(
          property["enum"] as? [String], "\(name) schemaVersion has no const or string enum")
      }
      try assertSameValues(swift, values, "\(name) schemaVersion")
    }
  }

  func testCaptureModelWritesTheNewestVersionAndLimitsTheOldest() throws {
    let schema = try SchemaReader(fileName: "capture-model.schema.json")
    XCTAssertEqual(
      CaptureModelSchemaVersion.current.rawValue,
      try schema.strings(at: ["properties", "schemaVersion", "enum"]).last,
      "CaptureModelSchemaVersion.current vs the newest capture-model.schema.json schemaVersion")
    XCTAssertEqual(
      CaptureModelSchemaVersion.v1.rawValue,
      try schema.string(at: ["if", "properties", "schemaVersion", "const"]),
      "the version capture-model.schema.json refuses the 1.1.0 fields in")
  }

  func testCaptureRecordWritesTheNewestVersionAndLimitsTheOldest() throws {
    let schema = try SchemaReader(fileName: "capture-record.schema.json")
    XCTAssertEqual(
      CaptureRecordSchemaVersion.current.rawValue,
      try schema.strings(at: ["properties", "schemaVersion", "enum"]).last,
      "CaptureRecordSchemaVersion.current vs the newest capture-record.schema.json schemaVersion")
    let rules = try XCTUnwrap(try schema.value(at: ["allOf"]) as? [[String: Any]])
    func refused(in version: CaptureRecordSchemaVersion) throws -> [String] {
      let found = rules.first { rule in
        let condition = (rule["if"] as? [String: Any])?["properties"] as? [String: Any]
        return (condition?["schemaVersion"] as? [String: Any])?["const"] as? String
          == version.rawValue
      }
      let properties = try XCTUnwrap(
        ["then", "properties", "captures", "items", "properties"].reduce(found as Any?) {
          ($0 as? [String: Any])?[$1]
        } as? [String: Any], "no rule for \(version.rawValue)")
      return Array(properties.keys)
    }
    let compass = ["heading", "headingAccuracy", "headingSource", "headingRecordedAt", "headingIssue"]
    let sketch = ["captureSource", "sketch", "walkthrough"]
    try assertSameValues(
      try refused(in: .v1), compass + sketch, "fields refused in a 1.0.0 capture record")
    try assertSameValues(try refused(in: .v1_1), sketch, "fields refused in a 1.1.0 capture record")
  }

  func testManifestWritesTheNewestVersionAndRetiresTheRetiredRoles() throws {
    let schema = try SchemaReader(fileName: "manifest.schema.json")
    let versions = try schema.strings(at: ["properties", "schemaVersion", "enum"])
    XCTAssertEqual(ManifestSchemaVersion.current.rawValue, versions.last)
    let rules = try XCTUnwrap(try schema.value(at: ["allOf"]) as? [[String: Any]])
    func rule(for version: ManifestSchemaVersion) throws -> [String: Any] {
      let found = rules.first { rule in
        let condition = (rule["if"] as? [String: Any])?["properties"] as? [String: Any]
        return (condition?["schemaVersion"] as? [String: Any])?["const"] as? String
          == version.rawValue
      }
      return try XCTUnwrap(found?["then"] as? [String: Any], "no rule for \(version.rawValue)")
    }
    func value(_ object: [String: Any], _ path: [String]) -> Any? {
      path.reduce(object as Any?) { ($0 as? [String: Any])?[$1] }
    }
    let retired = try XCTUnwrap(
      value(
        try rule(for: .current),
        ["properties", "files", "items", "properties", "role", "not", "enum"]) as? [String])
    try assertSameValues(
      FileRole.retiredRoles.map(\.rawValue), retired,
      "FileRole.retiredRoles vs the roles manifest 1.1.0 refuses")
    for role in FileRole.allCases {
      XCTAssertEqual(role.isRetired, FileRole.retiredRoles.contains(role), "\(role).isRetired")
    }
    let photo = try XCTUnwrap(
      value(try rule(for: .v1), ["properties", "files", "items", "properties", "photo", "properties"])
        as? [String: Any])
    XCTAssertEqual(Array(photo.keys), ["directionSource"], "fields refused in a 1.0.0 manifest")
  }

  // MARK: Other closed enums and constants

  func testCaptureRecordEnumsMatchSchema() throws {
    let schema = try SchemaReader(fileName: "capture-record.schema.json")
    try assertEnum(CaptureMode.self, schema, ["$defs", "captureMode", "enum"])
    try assertEnum(
      HeadingSource.self, schema, ["$defs", "capture", "properties", "headingSource", "enum"])
    try assertEnum(
      HeadingIssue.self, schema, ["$defs", "capture", "properties", "headingIssue", "enum"])
    try assertEnum(
      DeviceOSName.self, schema, ["properties", "device", "properties", "osName", "enum"])
    try assertEnum(
      CaptureSource.self, schema, ["$defs", "capture", "properties", "captureSource", "enum"])
    try assertEnum(
      SketchCompleteness.self, schema,
      ["$defs", "capture", "properties", "sketch", "properties", "measurements", "enum"])
    try assertEnum(
      CeilingHeightSource.self, schema,
      ["$defs", "capture", "properties", "sketch", "properties", "ceilingHeightSource", "enum"])
    try assertEnum(
      WalkthroughScaleSource.self, schema,
      ["$defs", "capture", "properties", "walkthrough", "properties", "scaleSource", "enum"])
    try assertEnum(
      DisplayUnitSystem.self, schema,
      ["$defs", "capture", "properties", "units", "properties", "display", "enum"])
    try assertConst(
      LengthUnit.self, schema,
      ["$defs", "capture", "properties", "units", "properties", "length", "const"])
  }

  func testCaptureModelEnumsMatchSchema() throws {
    let schema = try SchemaReader(fileName: "capture-model.schema.json")
    try assertEnum(DetectionConfidence.self, schema, ["$defs", "confidence", "enum"])
    try assertEnum(
      ObjectCategory.self, schema, ["$defs", "object", "properties", "category", "enum"])
    try assertEnum(RoomType.self, schema, ["$defs", "roomType", "enum"])
    try assertEnum(RoomTypeSource.self, schema, ["$defs", "roomTypeSource", "enum"])
    let coordinateSystem = ["properties", "coordinateSystem", "properties"]
    try assertConst(LengthUnit.self, schema, coordinateSystem + ["units", "const"])
    try assertConst(Handedness.self, schema, coordinateSystem + ["handedness", "const"])
    try assertConst(UpAxis.self, schema, coordinateSystem + ["up", "const"])
  }

  func testFieldControlsEnumsMatchSchema() throws {
    let schema = try SchemaReader(fileName: "field-controls.schema.json")
    try assertEnum(EnteredUnit.self, schema, ["$defs", "enteredUnit", "enum"])
    try assertEnum(
      MeasurementMethod.self, schema, ["$defs", "measurement", "properties", "method", "enum"])
    try assertEnum(DistanceAxis.self, schema, ["$defs", "distance", "properties", "axis", "enum"])
  }

  func testManifestEnumsMatchSchema() throws {
    let schema = try SchemaReader(fileName: "manifest.schema.json")
    try assertEnum(PhotoDirection.self, schema, ["$defs", "photoDirection", "enum"])
    try assertEnum(PhotoSubject.self, schema, ["$defs", "photoSubject", "enum"])
    try assertEnum(
      PhotoDirectionSource.self, schema,
      ["$defs", "photo", "properties", "directionSource", "enum"])
  }

  func testVerdictEnumsMatchSchema() throws {
    let schema = try SchemaReader(fileName: "verdict.schema.json")
    try assertEnum(VerdictOutcome.self, schema, ["$defs", "outcome", "enum"])
    try assertEnum(FindingSeverity.self, schema, ["$defs", "severity", "enum"])
    try assertEnum(
      CheckStatus.self, schema, ["$defs", "checkResult", "properties", "status", "enum"])
    XCTAssertEqual(
      Verdict.fixedStatement, try schema.string(at: ["properties", "statement", "const"]),
      "Verdict.fixedStatement vs verdict.schema.json statement const")
  }

  // MARK: Helpers

  private func layoutFolders() throws -> [[String: Any]] {
    let layout = try SchemaReader(fileName: "layout.json")
    let folders = try XCTUnwrap(
      try layout.value(at: ["folders"]) as? [[String: Any]], "layout.json folders")
    XCTAssertFalse(folders.isEmpty, "layout.json has no folders")
    return folders
  }

  private func string(_ object: [String: Any], _ key: String) throws -> String {
    try XCTUnwrap(object[key] as? String, "layout.json folder \(key) is not a string")
  }

  private func strings(_ object: [String: Any], _ key: String) throws -> [String] {
    try XCTUnwrap(object[key] as? [String], "layout.json folder \(key) is not a list of strings")
  }

  /// Same values with no duplicates on either side; order is not compared.
  private func assertSameValues(
    _ swift: [String], _ schema: [String], _ what: String,
    file: StaticString = #filePath, line: UInt = #line
  ) throws {
    XCTAssertEqual(
      swift.count, Set(swift).count, "\(what): duplicate in Swift", file: file, line: line)
    XCTAssertEqual(
      schema.count, Set(schema).count, "\(what): duplicate in schema", file: file, line: line)
    let missing = Set(schema).subtracting(swift).sorted()
    let extra = Set(swift).subtracting(schema).sorted()
    XCTAssertEqual(missing, [], "\(what): missing in Swift", file: file, line: line)
    XCTAssertEqual(extra, [], "\(what): extra in Swift", file: file, line: line)
  }

  private func assertEnum<E: CaseIterable & RawRepresentable>(
    _ type: E.Type, _ schema: SchemaReader, _ path: [String],
    file: StaticString = #filePath, line: UInt = #line
  ) throws where E.RawValue == String {
    try assertSameValues(
      type.allCases.map(\.rawValue), try schema.strings(at: path, file: file, line: line),
      "\(type) vs \(schema.name) \(path.joined(separator: "."))", file: file, line: line)
  }

  private func assertConst<E: CaseIterable & RawRepresentable>(
    _ type: E.Type, _ schema: SchemaReader, _ path: [String],
    file: StaticString = #filePath, line: UInt = #line
  ) throws where E.RawValue == String {
    try assertSameValues(
      type.allCases.map(\.rawValue), [try schema.string(at: path, file: file, line: line)],
      "\(type) vs \(schema.name) \(path.joined(separator: "."))", file: file, line: line)
  }
}

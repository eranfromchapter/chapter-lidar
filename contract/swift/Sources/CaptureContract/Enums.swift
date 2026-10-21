// Closed value sets from contract/schema. SchemaParityTests reads the schema files and fails
// when a case here is missing from, or extra to, the schema.

/// `schemaVersion` of the field controls and the verdict. The capture model, the capture record
/// and the manifest have their own versions (`CaptureModelSchemaVersion`,
/// `CaptureRecordSchemaVersion`, `ManifestSchemaVersion`).
public enum SchemaVersion: String, CaseIterable, Codable, Sendable {
  case v1 = "1.0.0"

  public static let current: SchemaVersion = .v1
}

/// `schemaVersion` of the capture record. 1.1.0 adds the optional compass reading of each capture
/// (`heading`, `headingAccuracy`, `headingSource`, `headingRecordedAt`) and `headingIssue`, so
/// every 1.0.0 document is also a valid 1.1.0 document. Both are read; `CaptureRecord` always
/// writes `current`.
public enum CaptureRecordSchemaVersion: String, CaseIterable, Codable, Sendable {
  case v1 = "1.0.0"
  case v1_1 = "1.1.0"

  public static let current: CaptureRecordSchemaVersion = .v1_1
}

/// `schemaVersion` of the manifest. 1.1.0 adds the optional `photo.directionSource` and retires
/// the role `spatial_report_pdf` (`FileRole.retiredRoles`). Both are read; `PackageManifest`
/// writes `current` except for a manifest that lists a retired role, which is written as 1.0.0
/// (see `PackageManifest.writtenSchemaVersion`).
public enum ManifestSchemaVersion: String, CaseIterable, Codable, Sendable {
  case v1 = "1.0.0"
  case v1_1 = "1.1.0"

  public static let current: ManifestSchemaVersion = .v1_1
}

/// `schemaVersion` of the capture model. 1.1.0 adds optional fields (room type and its source,
/// door `isOpen`, object attributes and parent), so every 1.0.0 document is also a valid 1.1.0
/// document. Both are read; `CaptureModel` always writes `current`.
public enum CaptureModelSchemaVersion: String, CaseIterable, Codable, Sendable {
  case v1 = "1.0.0"
  case v1_1 = "1.1.0"

  public static let current: CaptureModelSchemaVersion = .v1_1
}

/// Version of contract/schema/layout.json that manifest paths follow (`layoutVersion`).
public enum LayoutVersion: String, CaseIterable, Codable, Sendable {
  case v1 = "1.0.0"

  public static let current: LayoutVersion = .v1
}

// MARK: Capture record

/// Capture mode, shown to users as One room, Whole floor, Exterior.
public enum CaptureMode: String, CaseIterable, Codable, Sendable {
  case room
  case floor
  case exterior
}

/// Geometry is always metres.
public enum LengthUnit: String, CaseIterable, Codable, Sendable {
  case metres = "m"
}

/// Unit system shown to the operator.
public enum DisplayUnitSystem: String, CaseIterable, Codable, Sendable {
  case metric
  case imperial
}

public enum DeviceOSName: String, CaseIterable, Codable, Sendable {
  case iOS
  case iPadOS
}

/// North of a compass reading (capture record 1.1.0 `headingSource`): true north, corrected with
/// the phone's location, or magnetic north only (Location off). The one heading source type of
/// the app; photo headings use it too.
public enum HeadingSource: String, CaseIterable, Codable, Sendable {
  case trueNorth = "true"
  case magnetic
}

/// Why a capture has no heading although the app tried (capture record 1.1.0 `headingIssue`).
public enum HeadingIssue: String, CaseIterable, Codable, Sendable {
  /// Readings disagreed or could not be matched to the scan.
  case rejected
  /// The compass reported no valid accuracy.
  case notCalibrated = "not_calibrated"
  /// No usable compass on the device.
  case unavailable
}

// MARK: Capture model

public enum Handedness: String, CaseIterable, Codable, Sendable {
  case right
}

public enum UpAxis: String, CaseIterable, Codable, Sendable {
  case positiveY = "+Y"
}

/// What a room is used for (capture model 1.1.0).
public enum RoomType: String, CaseIterable, Codable, Sendable {
  case livingRoom = "living_room"
  case diningRoom = "dining_room"
  case kitchen
  case bedroom
  case bathroom
  case closet
  case hallway
  case laundry
  case office
  case utility
  case other
}

/// Where a room type came from (capture model 1.1.0).
public enum RoomTypeSource: String, CaseIterable, Codable, Sendable {
  /// The RoomPlan section label inside the room.
  case roomplanSection = "roomplan_section"
  /// The room's objects, for example a toilet makes a bathroom.
  case inferred
  /// Chosen by the operator.
  case `operator`
}

/// Detection confidence reported by the capture framework.
public enum DetectionConfidence: String, CaseIterable, Codable, Sendable {
  case low
  case medium
  case high
}

/// Category of a recognized object.
public enum ObjectCategory: String, CaseIterable, Codable, Sendable {
  case bathtub
  case bed
  case chair
  case dishwasher
  case fireplace
  case oven
  case refrigerator
  case sink
  case sofa
  case stairs
  case storage
  case stove
  case table
  case television
  case toilet
  case washerDryer = "washer_dryer"
  case other
}

/// Subset of the manifest file roles that a capture's geometry can come from.
public enum GeometrySourceRole: String, CaseIterable, Codable, Sendable {
  case rawRoomplanJSON = "raw_roomplan_json"
  case rawDepth = "raw_depth"
  case meshGLB = "mesh_glb"
  case meshOBJ = "mesh_obj"
  case pointCloudLAS = "point_cloud_las"

  /// The same value as a manifest file role.
  public var fileRole: FileRole {
    FileRole(rawValue: rawValue)!
  }
}

// MARK: Field controls

/// Unit the operator entered a value in. `ftIn` is feet and inches, for example 24' 8".
public enum EnteredUnit: String, CaseIterable, Codable, Sendable {
  case mm
  case cm
  case m
  case inches = "in"
  case ft
  case ftIn = "ft_in"
}

/// Independent instrument used. Values read from the scan are not field controls.
public enum MeasurementMethod: String, CaseIterable, Codable, Sendable {
  case tape
  case laser
}

/// Axis of a long distance; B is perpendicular to A within the same capture.
public enum DistanceAxis: String, CaseIterable, Codable, Sendable {
  case a = "A"
  case b = "B"
}

// MARK: Manifest

/// Direction the camera was looking.
public enum PhotoDirection: String, CaseIterable, Codable, Sendable {
  case north = "N"
  case east = "E"
  case south = "S"
  case west = "W"
}

public enum PhotoSubject: String, CaseIterable, Codable, Sendable {
  case opening
  case cabinetry
  case ceiling
  case fixture
  case equipment
  case defect
  case general
}

/// How a photo's direction was set (manifest 1.1.0 `photo.directionSource`).
public enum PhotoDirectionSource: String, CaseIterable, Codable, Sendable {
  /// Pre-filled from the phone's compass when the photo was taken and kept by the operator.
  case compass
  /// Chosen or changed by the operator.
  case manual
}

// MARK: Verdict

/// Shown as ● Ready, ▲ Limited, ■ Blocked.
public enum VerdictOutcome: String, CaseIterable, Codable, Sendable {
  case ready
  case limited
  case blocked
}

/// blocker prevents the task; limitation allows it with a named limitation; info records
/// evidence, including passed checks.
public enum FindingSeverity: String, CaseIterable, Codable, Sendable {
  case blocker
  case limitation
  case info
}

public enum CheckStatus: String, CaseIterable, Codable, Sendable {
  case passed
  case failed
  case notApplicable = "not_applicable"
}

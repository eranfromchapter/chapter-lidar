import Foundation

/// Identity and provenance strings shared by all writers.
public enum ExportInfo {
  /// Version of the exporters, written into `asset.generator` (GLB) and the LAS header.
  public static let version = "0.1.0"

  /// LAS system identifier.
  public static let systemIdentifier = "Chapter Capture"

  /// GLB `asset.generator`, for example `Chapter Capture 0.1.0`.
  public static func generator(version: String = ExportInfo.version) -> String {
    "\(systemIdentifier) \(version)"
  }
}

/// How the point cloud was measured. The package manifest records this (F6) so a LAS from a phone
/// depth sensor is never labelled raw survey data.
public enum ExportProvenance {
  /// Value for the manifest's provenance of the LAS file.
  public static let lasSource = "phone_depth_sensor"
  /// Always false: phone depth data is not survey-grade.
  public static let isSurveyGrade = false
  /// Human-readable statement, also written into the LAS provenance VLR.
  public static let statement =
    "Derived from a phone depth sensor (LiDAR). Not raw survey data. Local coordinates in metres, Z up."
}

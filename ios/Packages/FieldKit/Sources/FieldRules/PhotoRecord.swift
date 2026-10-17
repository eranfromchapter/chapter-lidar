import CaptureContract
import Foundation

/// Container format of an original site photograph.
public enum PhotoFormat: String, CaseIterable, Codable, Sendable {
  case jpeg
  case heic

  public var fileExtension: String {
    switch self {
    case .jpeg: return "jpg"
    case .heic: return "heic"
    }
  }

  public var mime: String {
    switch self {
    case .jpeg: return "image/jpeg"
    case .heic: return "image/heic"
    }
  }
}

/// One saved site photograph: where its untouched original is, its fingerprint and its labels.
/// The labels are the manifest's `PhotoLabels` (room, direction, subject, takenAt) so the package
/// assembler can copy them straight into the manifest entry.
public struct PhotoRecord: Hashable, Sendable, Codable {
  public var captureId: LowercaseUUID
  public var areaKey: String
  /// Photo number within the capture, starting at 1 (`photo-0001`).
  public var sequence: Int
  /// Package-relative path, for example `Site Photos/floor-1/{captureId}/photo-0014.heic`.
  public var path: String
  public var format: PhotoFormat
  /// Lowercase hex SHA-256 of the original file bytes.
  public var sha256: String
  public var bytes: Int64
  public var labels: PackageManifest.PhotoLabels

  public init(
    captureId: LowercaseUUID,
    areaKey: String,
    sequence: Int,
    path: String,
    format: PhotoFormat,
    sha256: String,
    bytes: Int64,
    labels: PackageManifest.PhotoLabels
  ) {
    self.captureId = captureId
    self.areaKey = areaKey
    self.sequence = sequence
    self.path = path
    self.format = format
    self.sha256 = sha256
    self.bytes = bytes
    self.labels = labels
  }

  public var room: String { labels.room }
  public var direction: PhotoDirection { labels.direction }
  public var subject: PhotoSubject { labels.subject }
  public var takenAt: UTCTimestamp { labels.takenAt }
  public var mime: String { format.mime }
}

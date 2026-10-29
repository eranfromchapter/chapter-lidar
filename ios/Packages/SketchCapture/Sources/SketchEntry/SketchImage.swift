import CaptureContract
import Foundation

/// The file kinds a sketch image may be (spec F14 2.1: JPEG, HEIC, PNG or PDF). The bytes are
/// copied into the package unchanged as `sketch.<ext>` (role `sketch_image`).
public enum SketchImageFormat: String, CaseIterable, Hashable, Sendable {
  case jpeg = "jpg"
  case png
  case heic
  case pdf

  public var fileExtension: String { rawValue }

  public var mime: String {
    switch self {
    case .jpeg: return "image/jpeg"
    case .png: return "image/png"
    case .heic: return "image/heic"
    case .pdf: return "application/pdf"
    }
  }

  /// The format from a file name's extension (`sketch.jpg`, `plan.PDF`), nil for any other.
  public init?(fileExtension: String) {
    switch fileExtension.lowercased() {
    case "jpg", "jpeg": self = .jpeg
    case "png": self = .png
    case "heic", "heif": self = .heic
    case "pdf": self = .pdf
    default: return nil
    }
  }

  /// The format read from the first bytes: JPEG `FF D8 FF`, PNG `89 50 4E 47`, PDF `%PDF`, HEIC
  /// an ISO media box with an `ftyp` brand of `heic`, `heix`, `mif1` or `msf1`. Nil when the
  /// bytes are none of these (the sketch screen then refuses the file).
  public static func detect(_ data: Data) -> SketchImageFormat? {
    guard data.count >= 12 else { return nil }
    let bytes = [UInt8](data.prefix(12))
    if bytes[0] == 0xFF, bytes[1] == 0xD8, bytes[2] == 0xFF { return .jpeg }
    if bytes[0] == 0x89, bytes[1] == 0x50, bytes[2] == 0x4E, bytes[3] == 0x47 { return .png }
    if bytes[0] == 0x25, bytes[1] == 0x50, bytes[2] == 0x44, bytes[3] == 0x46 { return .pdf }
    if bytes[4] == 0x66, bytes[5] == 0x74, bytes[6] == 0x79, bytes[7] == 0x70 {
      let brand = String(decoding: bytes[8..<12], as: UTF8.self)
      if ["heic", "heix", "hevc", "mif1", "msf1"].contains(brand) { return .heic }
    }
    return nil
  }

  /// The file name in the capture's originals folder: `sketch.jpg`.
  public var fileName: String { "\(SketchImageFormat.baseName).\(fileExtension)" }

  public static let baseName = "sketch"

  /// The sketch image of a capture's originals folder, when there is one: the first of
  /// `sketch.jpg`, `sketch.png`, `sketch.heic`, `sketch.pdf` that exists.
  public static func existingImage(in directory: URL) -> (url: URL, format: SketchImageFormat)? {
    for format in allCases {
      let url = directory.appendingPathComponent(format.fileName)
      if FileManager.default.fileExists(atPath: url.path) { return (url, format) }
    }
    return nil
  }
}

/// The sketch the operator chose on "What are you drawing from?": its bytes, kept unchanged,
/// and what they are.
public struct SketchImageSelection: Hashable, Sendable {
  public var data: Data
  public var format: SketchImageFormat

  public init(data: Data, format: SketchImageFormat) {
    self.data = data
    self.format = format
  }

  /// The selection of `data` when its bytes are a supported image or PDF; nil otherwise.
  public init?(data: Data) {
    guard let format = SketchImageFormat.detect(data) else { return nil }
    self.init(data: data, format: format)
  }

  public var fileName: String { format.fileName }
}

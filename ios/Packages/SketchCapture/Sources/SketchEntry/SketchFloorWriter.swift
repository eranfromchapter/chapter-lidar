import CaptureContract
import Foundation

/// A file "Finish floor" wrote into the capture's originals folder.
public struct SketchWrittenFile: Sendable, Equatable {
  public var fileName: String
  public var byteCount: Int

  public init(fileName: String, byteCount: Int) {
    self.fileName = fileName
    self.byteCount = byteCount
  }
}

public enum SketchFloorWriterError: Error, Equatable, CustomStringConvertible {
  case alreadyWritten(String)
  case writeFailed(String)

  public var description: String {
    switch self {
    case .alreadyWritten(let name): return "\(name) is already written for this capture."
    case .writeFailed(let reason): return "The sketch could not be saved: \(reason)"
    }
  }
}

/// Writes the originals of a sketch capture (spec F14 2.4): `sketch.<ext>` (the bytes as
/// chosen, unchanged) and `sketch-measurements.json` (what the operator entered, pretty printed
/// with sorted keys) into `<originals root>/Original Exports/{areaKey}/{captureId}/`. Originals
/// are never overwritten, as the scan's raw originals are not.
public enum SketchFloorWriter {
  public static func write(
    measurements: SketchMeasurements, image: SketchImageSelection?, to directory: URL
  ) throws -> [SketchWrittenFile] {
    var files: [(name: String, data: Data)] = []
    if let image {
      files.append((image.fileName, image.data))
    }
    let encoded: Data
    do {
      encoded = try CaptureContractJSON.makeEncoder(prettyPrinted: true).encode(measurements)
    } catch {
      throw SketchFloorWriterError.writeFailed(String(describing: error))
    }
    files.append((PackageLayout.sketchMeasurementsFileName, encoded))

    for file in files
    where FileManager.default.fileExists(atPath: directory.appendingPathComponent(file.name).path) {
      throw SketchFloorWriterError.alreadyWritten(file.name)
    }
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      for file in files {
        try file.data.write(to: directory.appendingPathComponent(file.name), options: .atomic)
      }
    } catch {
      throw SketchFloorWriterError.writeFailed(error.localizedDescription)
    }
    return files.map { SketchWrittenFile(fileName: $0.name, byteCount: $0.data.count) }
  }

  /// The package path of the capture's folder: `Original Exports/{areaKey}/{captureId}/`.
  public static func packageFolder(areaKey: String, captureId: LowercaseUUID) -> String {
    "\(PackageFolder.originalExports.name)/\(areaKey)/\(captureId.rawValue)/"
  }
}

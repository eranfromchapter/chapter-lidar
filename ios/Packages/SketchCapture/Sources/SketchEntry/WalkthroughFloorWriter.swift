import CaptureContract
import Foundation

/// Writes the originals of an AR walkthrough capture (spec F15 2, 4) at Finish floor into
/// `<originals root>/Original Exports/{areaKey}/{captureId}/`: `walkthrough-log.json` (every
/// tap and recorded camera pose, pretty printed with sorted keys), `sketch-measurements.json`
/// (the F14 document the converter derived from the log) and `walkthrough.mp4` (the recorded
/// video, moved there from where it was recorded) when there is one. Originals are never
/// overwritten, as the scan's raw originals are not.
public enum WalkthroughFloorWriter {
  /// File name of the recorded video in the capture's folder (role `walkthrough_video`).
  public static let videoFileName = "walkthrough.mp4"

  /// The package path of the video: `Original Exports/{areaKey}/{captureId}/walkthrough.mp4`.
  public static func videoPackagePath(areaKey: String, captureId: LowercaseUUID) -> String {
    SketchFloorWriter.packageFolder(areaKey: areaKey, captureId: captureId) + videoFileName
  }

  /// The package path of the log, the measurements' `source.path`.
  public static func logPackagePath(areaKey: String, captureId: LowercaseUUID) -> String {
    SketchFloorWriter.packageFolder(areaKey: areaKey, captureId: captureId)
      + PackageLayout.walkthroughLogFileName
  }

  /// `video`: the recorded file (moved, not copied), nil when nothing was recorded. A log that
  /// names a video is written only with that video.
  @discardableResult
  public static func write(
    log: WalkthroughLog, measurements: SketchMeasurements, video: URL?, to directory: URL
  ) throws -> [SketchWrittenFile] {
    let encoder = CaptureContractJSON.makeEncoder(prettyPrinted: true)
    let logData: Data
    let measurementsData: Data
    do {
      logData = try encoder.encode(log)
      measurementsData = try encoder.encode(measurements)
    } catch {
      throw SketchFloorWriterError.writeFailed(String(describing: error))
    }
    let names = [PackageLayout.walkthroughLogFileName, PackageLayout.sketchMeasurementsFileName]
      + (video == nil ? [] : [videoFileName])
    for name in names
    where FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path) {
      throw SketchFloorWriterError.alreadyWritten(name)
    }
    var written: [SketchWrittenFile] = []
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      if let video {
        let target = directory.appendingPathComponent(videoFileName)
        try FileManager.default.moveItem(at: video, to: target)
        let size = (try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        written.append(SketchWrittenFile(fileName: videoFileName, byteCount: size))
      }
      try logData.write(
        to: directory.appendingPathComponent(PackageLayout.walkthroughLogFileName),
        options: .atomic)
      written.append(
        SketchWrittenFile(fileName: PackageLayout.walkthroughLogFileName, byteCount: logData.count))
      try measurementsData.write(
        to: directory.appendingPathComponent(PackageLayout.sketchMeasurementsFileName),
        options: .atomic)
      written.append(
        SketchWrittenFile(
          fileName: PackageLayout.sketchMeasurementsFileName, byteCount: measurementsData.count))
    } catch {
      throw SketchFloorWriterError.writeFailed(error.localizedDescription)
    }
    return written
  }
}

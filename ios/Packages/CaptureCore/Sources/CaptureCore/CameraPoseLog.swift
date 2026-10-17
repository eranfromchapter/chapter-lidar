import CaptureContract
import CaptureModelMapping
import Foundation

/// Camera intrinsics (pixels) of the capture camera.
public struct CameraIntrinsics: Codable, Sendable, Equatable {
  public var fx: Double
  public var fy: Double
  public var cx: Double
  public var cy: Double
  public var imageWidth: Int
  public var imageHeight: Int

  public init(fx: Double, fy: Double, cx: Double, cy: Double, imageWidth: Int, imageHeight: Int) {
    self.fx = fx
    self.fy = fy
    self.cx = cx
    self.cy = cy
    self.imageWidth = imageWidth
    self.imageHeight = imageHeight
  }
}

/// One camera pose: seconds since the scan started and the camera-to-world transform
/// (four column arrays, like RoomPlan, in the capture frame, metres, +Y up).
public struct CameraPose: Codable, Sendable, Equatable {
  public var timestamp: Double
  public var transform: Matrix4

  public init(timestamp: Double, transform: Matrix4) {
    self.timestamp = timestamp
    self.transform = transform
  }
}

/// `camera-poses.json`: intrinsics and per-frame camera poses of one capture.
public struct CameraPoseLog: Codable, Sendable, Equatable {
  public var formatVersion: Int
  public var intrinsics: CameraIntrinsics?
  public var frames: [CameraPose]

  public static let currentFormatVersion = 1

  public init(
    formatVersion: Int = CameraPoseLog.currentFormatVersion, intrinsics: CameraIntrinsics? = nil,
    frames: [CameraPose] = []
  ) {
    self.formatVersion = formatVersion
    self.intrinsics = intrinsics
    self.frames = frames
  }

  public func encoded() throws -> Data {
    try CaptureContractJSON.makeEncoder(prettyPrinted: true).encode(self)
  }

  public static func decode(_ data: Data) throws -> CameraPoseLog {
    try JSONDecoder().decode(CameraPoseLog.self, from: data)
  }
}

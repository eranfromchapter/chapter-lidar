import CaptureContract

/// What the phone can do, read by the Apple-only code from ARKit and RoomPlan.
public struct DeviceCapabilities: Sendable, Equatable {
  /// Hardware model identifier, for example iPhone17,1.
  public var model: String
  public var osName: DeviceOSName
  public var osVersion: String
  /// `ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)`: true only with LiDAR.
  public var supportsSceneReconstructionMesh: Bool
  /// `RoomCaptureSession.isSupported`.
  public var roomPlanSupported: Bool

  public init(
    model: String, osName: DeviceOSName, osVersion: String, supportsSceneReconstructionMesh: Bool,
    roomPlanSupported: Bool
  ) {
    self.model = model
    self.osName = osName
    self.osVersion = osVersion
    self.supportsSceneReconstructionMesh = supportsSceneReconstructionMesh
    self.roomPlanSupported = roomPlanSupported
  }
}

public enum DeviceGateFailure: Sendable, Equatable {
  case noLidar
  case roomPlanUnsupported
  case osTooOld(minimumMajor: Int)

  /// A clear message for the operator.
  public var message: String {
    switch self {
    case .noLidar:
      return "This device has no LiDAR scanner. Chapter Capture needs an iPhone Pro or iPad Pro with LiDAR."
    case .roomPlanUnsupported:
      return "This device does not support Apple RoomPlan, which Chapter Capture needs to scan rooms."
    case .osTooOld(let major):
      return "Update to iOS \(major) or later to use Chapter Capture."
    }
  }
}

public struct DeviceGateResult: Sendable, Equatable {
  public var failures: [DeviceGateFailure]

  public var isSupported: Bool { failures.isEmpty }

  /// All failure messages, one per line; nil when the device is supported.
  public var message: String? {
    failures.isEmpty ? nil : failures.map(\.message).joined(separator: "\n")
  }
}

/// The device gate: LiDAR present and RoomPlan supported, or a clear message.
public enum DeviceGate {
  public static let minimumOSMajor = 17

  public static func evaluate(_ capabilities: DeviceCapabilities) -> DeviceGateResult {
    var failures: [DeviceGateFailure] = []
    if !capabilities.supportsSceneReconstructionMesh {
      failures.append(.noLidar)
    }
    if !capabilities.roomPlanSupported {
      failures.append(.roomPlanUnsupported)
    }
    if let major = capabilities.osVersion.split(separator: ".").first.flatMap({ Int($0) }),
      major < minimumOSMajor
    {
      failures.append(.osTooOld(minimumMajor: minimumOSMajor))
    }
    return DeviceGateResult(failures: failures)
  }
}

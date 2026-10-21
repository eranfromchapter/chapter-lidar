#if canImport(RoomPlan) && canImport(ARKit) && os(iOS)
  import ARKit
  import CaptureContract
  import CaptureCore
  import Foundation
  import RoomPlan
  import UIKit

  /// Hardware and OS facts of this phone.
  enum DeviceHardware {
    /// Model identifier such as `iPhone17,1`. The simulator reports the model it pretends to be.
    static var modelIdentifier: String {
      if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
        return simulated
      }
      var system = utsname()
      uname(&system)
      let identifier = Mirror(reflecting: system.machine).children.reduce(into: "") { text, element in
        guard let value = element.value as? Int8, value != 0 else { return }
        text.append(Character(UnicodeScalar(UInt8(bitPattern: value))))
      }
      return identifier.isEmpty ? "unknown" : identifier
    }

    /// `major.minor.patch`, the form the capture record wants.
    static var osVersionString: String {
      let version = ProcessInfo.processInfo.operatingSystemVersion
      return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
  }

  extension DeviceCapabilities {
    /// What this phone can do: LiDAR scene reconstruction and RoomPlan. Feed it to `DeviceGate`.
    @MainActor
    public static func current() -> DeviceCapabilities {
      DeviceCapabilities(
        model: DeviceHardware.modelIdentifier,
        osName: UIDevice.current.userInterfaceIdiom == .pad ? .iPadOS : .iOS,
        osVersion: DeviceHardware.osVersionString,
        supportsSceneReconstructionMesh: ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh),
        roomPlanSupported: RoomCaptureSession.isSupported)
    }
  }

  extension DeviceInfo {
    /// Device, OS and the LiDAR flag for the capture record, read from the phone. The marketing
    /// name ("iPhone 16 Pro") comes from `DeviceNames`; nil for an identifier it does not know.
    @MainActor
    public static func current() -> DeviceInfo {
      let capabilities = DeviceCapabilities.current()
      return DeviceInfo(
        model: capabilities.model,
        marketingName: DeviceNames.marketingName(for: capabilities.model),
        osName: capabilities.osName,
        osVersion: capabilities.osVersion, hasLidar: capabilities.supportsSceneReconstructionMesh)
    }
  }
#endif

#if canImport(CoreLocation) && canImport(CoreMotion) && canImport(UIKit) && os(iOS)
  import CaptureContract
  import CaptureCore
  import Foundation

  /// The recorder of device test D0 (compass §13.5, `docs/qa/compass-device-tests.md`): while
  /// the phone lies flat with its top edge along a line of known bearing (or is held upright,
  /// camera along it), it logs every 0.5 s the bearing `CompassMath` computes from Core Motion
  /// next to `CLHeading`, and the Core Motion gravity check. D0 passes when they agree within 3°
  /// and every gravity check passes (`CompassDeviceCheckReport.passes`).
  ///
  /// Run it from the device test `CompassDeviceCheckTests` (scheme CaptureCore-Package on a
  /// phone) or from a debug screen; it writes no file itself and records no location.
  @MainActor
  public final class CompassDeviceCheck {
    public static let interval: TimeInterval = 0.5
    private let service: CompassService

    public init(service: CompassService) {
      self.service = service
    }

    /// Records for `seconds` and returns the lines with their summary. Cancelling stops early.
    public func record(seconds: TimeInterval) async -> CompassDeviceCheckReport {
      service.startScanSensors()
      defer { service.stopScanSensors() }
      let start = Date()
      var lines: [CompassDeviceCheckLine] = []
      while !Task.isCancelled, Date().timeIntervalSince(start) < seconds {
        try? await Task.sleep(for: .milliseconds(Int(Self.interval * 1000)))
        guard let motion = service.motionRing.latest, let heading = service.latestHeading else {
          continue
        }
        lines.append(
          CompassDeviceCheckLine(
            time: Date().timeIntervalSince(start), motion: motion, heading: heading))
      }
      return CompassDeviceCheckReport(lines: lines)
    }
  }
#endif

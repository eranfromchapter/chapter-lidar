import CaptureContract
import Foundation

/// The compass of the floor being scanned, as the live scan's chip shows it (compass §5.2).
/// `LiveCaptureSession` emits it as `CaptureSessionEvent.compass` whenever the best reading
/// changes, when the 30 s start period ends, and at each 4 Hz tick for the camera bearing.
public enum CompassLiveState: Hashable, Sendable {
  /// The start period: nothing usable accepted yet (`N · reading…`).
  case reading
  /// The best reading so far is usable. `cameraBearing` is the bearing the camera looks at
  /// (compass §2.3), nil when the camera points steeply up or down (the chip keeps its last
  /// angle).
  case result(CompassState, cameraBearing: Double?)
  /// The start period is over and the best reading so far is not usable; attempts continue
  /// silently until Finish floor (`N · not verified`).
  case notVerified

  /// The usable state, if any.
  public var state: CompassState? {
    if case .result(let state, _) = self, state.isUsable { return state }
    return nil
  }

  public var cameraBearing: Double? {
    if case .result(_, let bearing) = self { return bearing }
    return nil
  }
}

/// The pre-check on "What are you scanning?" (compass §3.2): the phone's own compass health
/// before the scan, shown to the operator and never stored.
public enum CompassPrecheckState: Hashable, Sendable {
  /// On appear and after Read again.
  case reading
  /// The heading of the phone's top edge, accuracy (whole degrees, rounded up), north, and the
  /// end of the 2 s window (`{AGO}` counts from it).
  case result(heading: Double, accuracy: Int, source: HeadingSource, readAt: Date)
  /// No valid accuracy within 5 s.
  case notCalibrated
  /// The phone has no usable compass.
  case unavailable

  /// The state of a result under the shared thresholds; nil for the other cases.
  public var state: CompassState? {
    guard case .result(let heading, let accuracy, let source, let readAt) = self else {
      return nil
    }
    return CompassState(reading: heading, accuracy: accuracy, source: source, at: readAt)
  }
}

/// Whether Chapter Capture may use the location (only to turn the compass into true north).
public enum CompassAuthorization: Hashable, Sendable {
  case notDetermined
  /// Denied or restricted: north is magnetic, so at best approximate.
  case denied
  /// When In Use or Always (reduced accuracy is enough).
  case authorized
}

/// The bearing of the back camera from Core Motion alone, for the photo's "Looking toward"
/// pre-fill (phone-field §3.6). The app's `CompassPhotoHeading` adapter turns it into
/// FieldRules' `PhotoHeadingSample`.
public struct CompassCameraSample: Hashable, Sendable {
  /// Camera axis, degrees clockwise from north, `0 ..< 360`.
  public var azimuth: Double
  /// Length of the horizontal part of the unit camera axis, `0 ... 1`.
  public var horizontalComponent: Double
  /// `CLHeading.headingAccuracy`; nil when invalid.
  public var accuracy: Double?
  public var source: HeadingSource
  public var sampledAt: Date

  public init(
    azimuth: Double, horizontalComponent: Double, accuracy: Double?, source: HeadingSource,
    sampledAt: Date
  ) {
    self.azimuth = azimuth
    self.horizontalComponent = horizontalComponent
    self.accuracy = accuracy
    self.source = source
    self.sampledAt = sampledAt
  }
}

/// The phone's compass for the capture screens: the pre-check, the location permission and the
/// photo camera bearing. `CompassService` (target `CaptureCompass`) is the device one, the app's
/// single owner of the location and motion managers; `FakeCompass` is the scripted one for tests
/// and UI tests. The scan-start reading itself runs inside `LiveCaptureSession`.
@MainActor
public protocol CompassProviding: AnyObject {
  /// False when the phone has no usable compass (`unavailable`).
  var isAvailable: Bool { get }
  var authorization: CompassAuthorization { get }
  /// Asks for When In Use authorization when it is not determined yet; nothing otherwise. Only
  /// "What are you scanning?" calls it, the first time it appears.
  func requestAuthorization()
  /// Runs the pre-check (2 s of headings, up to 5 s) and returns its result; never `.reading`.
  /// Cancelling the task stops the sensors and returns `.notCalibrated`.
  func precheck() async -> CompassPrecheckState
  /// Opens Chapter Capture's page in Settings (Location).
  func openSettings()
  /// Starts and stops the sensors behind `cameraSample()`.
  func startCameraHeading()
  func stopCameraHeading()
  /// The latest camera bearing, nil when there is none.
  func cameraSample() -> CompassCameraSample?
}

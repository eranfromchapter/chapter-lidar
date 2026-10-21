#if canImport(SwiftUI) && canImport(UIKit)
  import CaptureContract
  import FieldRules
  import Foundation

  /// Where the photo step gets the camera heading at the shutter (phone-field §3.6). The app
  /// passes an adapter over its one compass service (`CompassPhotoHeading`, compass §3.5), so
  /// the phone runs a single location and motion manager; tests and previews pass
  /// `FixedPhotoHeading`. The viewfinder starts it on appear and stops it on disappear.
  @MainActor
  public protocol PhotoHeadingProviding: AnyObject {
    func start()
    func stop()
    /// The newest sample, or nil when there is none (no compass, not calibrated, simulator).
    func currentSample() -> PhotoHeadingSample?
  }

  /// A heading that never moves: for tests, previews and the UI-test compass (85° ±8° true
  /// gives "E"). Each sample is stamped with the time it is asked for.
  @MainActor
  public final class FixedPhotoHeading: PhotoHeadingProviding {
    public var azimuthDegrees: Double?
    public var horizontalComponent: Double
    public var accuracyDegrees: Double?
    public var source: HeadingSource
    private let now: () -> Date
    public private(set) var isRunning = false

    /// `azimuthDegrees` nil: a provider without a reading (`currentSample()` is nil).
    public init(
      azimuthDegrees: Double?, accuracyDegrees: Double? = 8, source: HeadingSource = .trueNorth,
      horizontalComponent: Double = 1, now: @escaping () -> Date = Date.init
    ) {
      self.azimuthDegrees = azimuthDegrees
      self.accuracyDegrees = accuracyDegrees
      self.source = source
      self.horizontalComponent = horizontalComponent
      self.now = now
    }

    public func start() { isRunning = true }
    public func stop() { isRunning = false }

    public func currentSample() -> PhotoHeadingSample? {
      guard let azimuthDegrees else { return nil }
      return PhotoHeadingSample(
        azimuthDegrees: azimuthDegrees, horizontalComponent: horizontalComponent,
        accuracyDegrees: accuracyDegrees, source: source, sampledAt: now())
    }
  }
#endif

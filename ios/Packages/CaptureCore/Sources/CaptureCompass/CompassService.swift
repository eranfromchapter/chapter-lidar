#if canImport(CoreLocation) && canImport(CoreMotion) && canImport(UIKit) && os(iOS)
  import CaptureContract
  import CaptureCore
  import CoreLocation
  import CoreMotion
  import Foundation
  import UIKit
  import os

  /// The phone's one compass (compass §3.1, §3.5): it owns the app's single `CLLocationManager`
  /// and `CMMotionManager` and serves the three consumers:
  ///
  /// - the pre-check on "What are you scanning?" (`precheck()`, headings only);
  /// - the scan-start reading of `LiveCaptureSession` (`startScanSensors()`: device motion at
  ///   60 Hz into a 1 s ring, headings for their accuracy, location for true north);
  /// - the photo heading (`startCameraHeading()` / `cameraSample()`), through the app's
  ///   `CompassPhotoHeading` adapter.
  ///
  /// Core Motion uses `.xTrueNorthZVertical` when it is available and location is authorised,
  /// else `.xMagneticNorthZVertical`; the frame in use is the reading's north. When the
  /// authorisation changes while device motion runs, it restarts in the new frame (the scan's
  /// window then starts again). Location is requested at 3 km accuracy only while a consumer
  /// runs, and its values are dropped at once: nothing about the phone's position is kept,
  /// logged or sent. The system calibration overlay is never shown.
  @MainActor
  public final class CompassService: NSObject, CompassProviding {
    /// Device motion rate of the scan and the photo heading.
    public static let motionInterval: TimeInterval = 1.0 / 60
    nonisolated static let log = Logger(subsystem: "com.hellochapter.capture", category: "compass")

    private let locationManager = CLLocationManager()
    private let motionManager = CMMotionManager()
    private let motionQueue: OperationQueue = {
      let queue = OperationQueue()
      queue.name = "CompassService.motion"
      queue.maxConcurrentOperationCount = 1
      return queue
    }()
    private let delegateProxy = DelegateProxy()

    /// The last second of device motion while the scan or the photo heading runs.
    public let motionRing = CompassMotionRing()
    /// The newest `CLHeading`, while any consumer runs.
    public private(set) var latestHeading: CompassHeadingSample?
    /// North of the device-motion frame in use.
    public private(set) var motionSource: HeadingSource = .magnetic

    private var headingUsers = 0
    private var motionUsers = 0
    private var headingListeners: [UUID: (CompassHeadingSample) -> Void] = [:]

    public override init() {
      super.init()
      delegateProxy.owner = self
      locationManager.delegate = delegateProxy
      locationManager.headingFilter = kCLHeadingFilterNone
      locationManager.headingOrientation = .portrait
      locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
      locationManager.distanceFilter = 1000
      motionManager.deviceMotionUpdateInterval = Self.motionInterval
    }

    // MARK: CompassProviding

    public var isAvailable: Bool {
      CLLocationManager.headingAvailable() && Self.northReferenceFrame(authorized: false) != nil
    }

    public var authorization: CompassAuthorization {
      switch locationManager.authorizationStatus {
      case .notDetermined: return .notDetermined
      case .authorizedWhenInUse, .authorizedAlways: return .authorized
      default: return .denied
      }
    }

    public func requestAuthorization() {
      guard locationManager.authorizationStatus == .notDetermined else { return }
      locationManager.requestWhenInUseAuthorization()
    }

    public func openSettings() {
      guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
      UIApplication.shared.open(url)
    }

    public func precheck() async -> CompassPrecheckState {
      guard CLLocationManager.headingAvailable() else { return .unavailable }
      var reading = PrecheckReading(startedAt: Date())
      var pending: [CompassHeadingSample] = []
      let listener = UUID()
      headingListeners[listener] = { pending.append($0) }
      acquireHeading()
      defer {
        headingListeners[listener] = nil
        releaseHeading()
      }
      while !Task.isCancelled {
        for sample in pending {
          if let result = reading.add(sample) { return result }
        }
        pending.removeAll()
        if let result = reading.poll(now: Date()) { return result }
        try? await Task.sleep(for: .milliseconds(100))
      }
      return .notCalibrated
    }

    public func startCameraHeading() {
      acquireHeading()
      acquireMotion()
    }

    public func stopCameraHeading() {
      releaseMotion()
      releaseHeading()
    }

    public func cameraSample() -> CompassCameraSample? {
      guard let motion = motionRing.latest else { return nil }
      let axis = CompassMath.cameraAxisInReference(rotationMatrix: motion.attitude)
      let accuracy = latestHeading.flatMap { $0.isValid ? $0.accuracy : nil }
      return CompassCameraSample(
        azimuth: CompassMath.bearing(inReference: axis),
        horizontalComponent: CompassMath.horizontalComponent(inReference: axis),
        accuracy: accuracy, source: motion.source,
        sampledAt: Date(timeIntervalSinceNow: motion.timestamp - ProcessInfo.processInfo.systemUptime))
    }

    // MARK: Scan

    /// True when the phone cannot give a north-referenced reading at all (the scan records
    /// `unavailable`).
    public var isUnavailableForScan: Bool { !isAvailable }

    /// Starts what the scan-start reading needs. Pair with `stopScanSensors()`.
    public func startScanSensors() {
      acquireHeading()
      acquireMotion()
    }

    public func stopScanSensors() {
      releaseMotion()
      releaseHeading()
    }

    // MARK: Sensors

    private func acquireHeading() {
      headingUsers += 1
      guard headingUsers == 1 else { return }
      locationManager.startUpdatingHeading()
      updateLocationUpdates()
    }

    private func releaseHeading() {
      guard headingUsers > 0 else { return }
      headingUsers -= 1
      guard headingUsers == 0 else { return }
      locationManager.stopUpdatingHeading()
      latestHeading = nil
      updateLocationUpdates()
    }

    /// Location runs only while a consumer runs and only when authorised: `trueHeading` and the
    /// true-north frame need it. The values are discarded by the delegate.
    private func updateLocationUpdates() {
      if (headingUsers > 0 || motionUsers > 0) && authorization == .authorized {
        locationManager.startUpdatingLocation()
      } else {
        locationManager.stopUpdatingLocation()
      }
    }

    private func acquireMotion() {
      motionUsers += 1
      guard motionUsers == 1 else { return }
      startDeviceMotion()
      updateLocationUpdates()
    }

    private func releaseMotion() {
      guard motionUsers > 0 else { return }
      motionUsers -= 1
      guard motionUsers == 0 else { return }
      motionManager.stopDeviceMotionUpdates()
      motionRing.removeAll()
      updateLocationUpdates()
    }

    /// The north-referenced frame to use: true north when it exists and location is
    /// authorised, else magnetic; nil when the phone has neither.
    static func northReferenceFrame(authorized: Bool) -> (CMAttitudeReferenceFrame, HeadingSource)? {
      let frames = CMMotionManager.availableAttitudeReferenceFrames()
      if authorized, frames.contains(.xTrueNorthZVertical) {
        return (.xTrueNorthZVertical, .trueNorth)
      }
      if frames.contains(.xMagneticNorthZVertical) {
        return (.xMagneticNorthZVertical, .magnetic)
      }
      return nil
    }

    private func startDeviceMotion() {
      guard motionManager.isDeviceMotionAvailable,
        let (frame, source) = Self.northReferenceFrame(authorized: authorization == .authorized)
      else {
        Self.log.info("compass: no north-referenced device motion on this phone")
        return
      }
      motionManager.stopDeviceMotionUpdates()
      motionRing.removeAll()
      motionSource = source
      let ring = motionRing
      motionManager.startDeviceMotionUpdates(using: frame, to: motionQueue) { motion, _ in
        guard let motion else { return }
        ring.append(Self.sample(motion, source: source))
      }
    }

    nonisolated static func sample(_ motion: CMDeviceMotion, source: HeadingSource)
      -> CompassMotionSample
    {
      let m = motion.attitude.rotationMatrix
      let rate = motion.rotationRate
      return CompassMotionSample(
        timestamp: motion.timestamp,
        attitude: CompassMath.Matrix3(
          m11: m.m11, m12: m.m12, m13: m.m13, m21: m.m21, m22: m.m22, m23: m.m23, m31: m.m31,
          m32: m.m32, m33: m.m33),
        gravity: Vec3(x: motion.gravity.x, y: motion.gravity.y, z: motion.gravity.z),
        rotationRate: (rate.x * rate.x + rate.y * rate.y + rate.z * rate.z).squareRoot(),
        magneticFieldCalibrated: motion.magneticField.accuracy != .uncalibrated, source: source)
    }

    // MARK: Delegate

    fileprivate func didUpdateHeading(_ heading: CLHeading) {
      let sample = CompassHeadingSample(
        date: heading.timestamp, trueHeading: heading.trueHeading,
        magneticHeading: heading.magneticHeading, accuracy: heading.headingAccuracy)
      latestHeading = sample
      for listener in headingListeners.values { listener(sample) }
    }

    fileprivate func authorizationDidChange() {
      updateLocationUpdates()
      // A new frame for the device motion in use; the scan's window starts again with it.
      if motionUsers > 0 { startDeviceMotion() }
    }
  }

  /// `CLLocationManagerDelegate` without exposing the conformance on `CompassService`. Core
  /// Location calls it on the main thread, where the manager was made.
  private final class DelegateProxy: NSObject, CLLocationManagerDelegate {
    weak var owner: CompassService?

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
      MainActor.assumeIsolated { owner?.didUpdateHeading(newHeading) }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
      // Only needed so Core Location can turn magnetic into true north. Dropped, never stored.
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
      CompassService.log.info("compass: location unavailable, north stays magnetic")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
      MainActor.assumeIsolated { owner?.authorizationDidChange() }
    }

    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
      false
    }
  }
#endif

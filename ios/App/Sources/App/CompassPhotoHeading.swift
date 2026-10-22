import CaptureCore
import FieldKitUI
import FieldRules
import Foundation

/// The photo step's camera heading ("Looking toward" pre-fill, phone-field §3.6) from the app's
/// one compass (compass §3.5, critique R-23): the same `CompassService` that reads the scan, so
/// the phone runs a single location manager and a single motion manager. In UI tests the
/// compass is the scripted `FakeCompass` (85° ±8° true gives "E", critique R-24).
@MainActor
final class CompassPhotoHeading: PhotoHeadingProviding {
  private let compass: any CompassProviding

  init(compass: any CompassProviding) {
    self.compass = compass
  }

  func start() { compass.startCameraHeading() }

  func stop() { compass.stopCameraHeading() }

  func currentSample() -> PhotoHeadingSample? {
    compass.cameraSample().map {
      PhotoHeadingSample(
        azimuthDegrees: $0.azimuth, horizontalComponent: $0.horizontalComponent,
        accuracyDegrees: $0.accuracy, source: $0.source, sampledAt: $0.sampledAt)
    }
  }
}

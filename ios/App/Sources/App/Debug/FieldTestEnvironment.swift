// Field-test mode. DEBUG ONLY: this file is compiled only in the Debug configuration (`#if DEBUG`,
// and ios/project.yml excludes `FieldTest*` files from Release builds), and it is selected only
// when Info.plist `ChapterFieldTest` (build setting `CHAPTER_FIELD_TEST`) is YES.
//
// The real phone scans and photographs, with the real compass (one `CompassService`: the step 2
// pre-check, the scan-start reading, the photo heading); sign-in and the station are the
// in-process stubs of the UI-test mode, so a visit runs end to end before Entra and the station
// exist. Sealed packages stay in Application Support/FieldTestVisits (the visits of earlier
// field-test builds are listed on the Captures home too); copy them off the phone with
//   xcrun devicectl device copy from --device <id> --domain-type appDataContainer \
//     --domain-identifier com.hellochapter.capture --source Library/Application\ Support/FieldTestVisits \
//     --destination <folder>
#if DEBUG
  import AppCore
  import CaptureCompass
  import CaptureCore
  import CaptureRoomPlan
  import FieldKitUI
  import Foundation
  import StationClient

  enum FieldTestEnvironment {
    static let operatorName = "Field test (nothing is uploaded)"

    @MainActor
    static func services(cacheRoot: URL) -> AppServices {
      let storage = UITestBlobStorage()
      let station = StationAPI(
        configuration: try! StationClientConfiguration(stationURL: UITestStationTransport.stationURL),
        tokenProvider: UITestTokenProvider(),
        transport: UITestStationTransport(storage: storage))
      let compass = CompassService()
      return AppServices(
        station: station,
        projects: ProjectStore(
          source: station, cacheDirectory: cacheRoot.appendingPathComponent("StationCache")),
        blobTransport: UITestBlobTransport(storage: storage), signIn: nil,
        capabilities: DeviceCapabilities.current(), device: DeviceInfo.current(),
        makeSession: { _ in LiveCaptureSession(compass: compass) },
        photoSource: .camera(CameraEngine()), compass: compass,
        fixedOperator: SignedInOperator(name: operatorName, userId: nil))
    }
  }
#endif

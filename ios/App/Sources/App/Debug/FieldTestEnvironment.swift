// Field-test mode. DEBUG ONLY: this file is compiled only in the Debug configuration (`#if DEBUG`,
// and ios/project.yml excludes `FieldTest*` files from Release builds), and it is selected only
// when Info.plist `ChapterFieldTest` (build setting `CHAPTER_FIELD_TEST`) is YES.
//
// The real phone scans and photographs, with the real compass (one `CompassService`: the step 2
// pre-check, the scan-start reading, the photo heading); sign-in and the station are the
// in-process stubs of the UI-test mode, so a visit runs end to end before Entra and the station
// exist. One exception, only when the developer put an Anthropic API key in the untracked
// Local.xcconfig (`CHAPTER_ANTHROPIC_API_KEY`): a sketch photo goes to the Claude API to be read
// (spec F16, `FieldTestSketchReader`); without a key the fixture reading answers. Sealed
// packages stay in Application Support/FieldTestVisits (the visits of earlier field-test builds
// are listed on the Captures home too); copy them off the phone with
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
  import SketchEntry
  import StationClient

  enum FieldTestEnvironment {
    static let operatorName = "Field test (nothing is uploaded)"

    @MainActor
    static func services(cacheRoot: URL) -> AppServices {
      let storage = UITestBlobStorage()
      let sketch = sketchReader()
      let transport = UITestStationTransport(storage: storage, sketchReader: sketch.reader)
      let station = StationAPI(
        configuration: try! StationClientConfiguration(stationURL: UITestStationTransport.stationURL),
        tokenProvider: UITestTokenProvider(),
        transport: transport)
      let compass = CompassService()
      var services = AppServices(
        station: station,
        projects: ProjectStore(
          source: station, cacheDirectory: cacheRoot.appendingPathComponent("StationCache")),
        blobTransport: UITestBlobTransport(storage: storage), signIn: nil,
        capabilities: DeviceCapabilities.current(), device: DeviceInfo.current(),
        makeSession: { _ in LiveCaptureSession(compass: compass) },
        photoSource: .camera(CameraEngine()), compass: compass,
        fixedOperator: SignedInOperator(name: operatorName, userId: nil))
      // "Delete all photos" lets go of the photos the stub station holds in memory.
      services.stationPhotoBlobs = { transport.erasePhotoBlobs() }
      services.sketchInterpreter = StationSketchInterpreter(station: station)
      services.sketchReaderNotice = sketch.notice
      return services
    }

    /// Info.plist key of the field test's Anthropic API key (build setting
    /// `CHAPTER_ANTHROPIC_API_KEY`, set only in the untracked `Local.xcconfig`; Release.xcconfig
    /// empties it).
    static let anthropicKeyInfoKey = "ChapterAnthropicAPIKey"

    /// How the field test reads a sketch photo (spec F16): with an API key, Claude directly
    /// (`FieldTestSketchReader`, the contract prompt and reading schema bundled in Debug); without
    /// one, the UI tests' fixture reading and a notice saying so.
    static func sketchReader() -> (reader: UITestSketchReader?, notice: String?) {
      let fixture = Bundle.main.url(forResource: "UITestSketchInterpretation", withExtension: "json")
        .flatMap { try? Data(contentsOf: $0) }
      let demo: UITestSketchReader? = fixture.map { .fixture($0, delay: 2) }
      let key = (Bundle.main.object(forInfoDictionaryKey: anthropicKeyInfoKey) as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !key.isEmpty, !key.hasPrefix("$("),
        let promptURL = Bundle.main.url(forResource: "sketch-interpretation", withExtension: "md"),
        let schemaURL = Bundle.main.url(
          forResource: "sketch-interpretation.schema", withExtension: "json"),
        let prompt = try? String(contentsOf: promptURL, encoding: .utf8),
        let schema = try? Data(contentsOf: schemaURL),
        let reader = try? FieldTestSketchReader(
          apiKey: key, systemPrompt: prompt, interpretationSchema: schema)
      else { return (demo, SketchPhotoText.demoNotice) }
      return (.claude(reader), nil)
    }
  }
#endif

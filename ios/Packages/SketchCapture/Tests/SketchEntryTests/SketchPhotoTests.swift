#if canImport(Observation)
  import CaptureContract
  import Foundation
  import SketchEntry
  import SketchReading
  import SketchSolver
  import XCTest

  #if canImport(ImageIO)
    import CoreGraphics
    import ImageIO
    import UniformTypeIdentifiers
  #endif

  /// The interpreter of the tests: the reading it is given, or the error, after an optional
  /// wait (so a reading can be cancelled).
  private struct StubInterpreter: SketchInterpreting {
    var result: Result<SketchInterpretation, Error>
    var delay: UInt64 = 0

    func interpret(imageData: Data, mediaType: String) async throws -> SketchInterpretation {
      if delay > 0 { try await Task.sleep(nanoseconds: delay) }
      return try result.get()
    }
  }

  /// "Photograph a sketch" (spec F16 2): the photo, the reading, the one length, Check, and
  /// the files Finish floor writes.
  @MainActor
  final class SketchPhotoTests: XCTestCase {
    /// The app's UI-test reading: a 4 x 3 m bedroom, door, window, bed and wardrobe, no
    /// written dimensions (ios/App/Sources/App/Debug/UITestSketchInterpretation.json).
    static func fixture() throws -> SketchInterpretation {
      // SketchPhotoTests.swift, SketchEntryTests, Tests, SketchCapture, Packages: ios/.
      let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
      let url = root.appendingPathComponent("App/Sources/App/Debug/UITestSketchInterpretation.json")
      return try CaptureContractJSON.makeDecoder().decode(
        SketchInterpretation.self, from: try Data(contentsOf: url))
    }

    static let jpeg = SketchImageSelection(
      data: Data([0xFF, 0xD8, 0xFF, 0xE0] + [UInt8](repeating: 0x20, count: 16) + [0xFF, 0xD9]),
      format: .jpeg)

    private func model(_ interpreter: StubInterpreter, notice: String? = nil) -> SketchPhotoModel {
      SketchPhotoModel(
        floorLabel: "Floor 1", areaKey: "floor-1", mode: .room, displayUnits: .imperial,
        notice: notice, interpreter: interpreter,
        prepare: { SketchPhotoUploadImage(data: $0.data, mediaType: $0.format.mime) })
    }

    func testAnUndimensionedSketchAsksForOneLengthThenReachesCheck() async throws {
      let model = model(StubInterpreter(result: .success(try Self.fixture())))
      XCTAssertEqual(model.phase, .source)
      await model.read(Self.jpeg)
      XCTAssertEqual(model.phase, .oneLength)
      XCTAssertTrue(model.needsOneLength)
      XCTAssertEqual(model.drawnWalls.count, 4)
      XCTAssertEqual(model.lengthContinueTitle, SketchPhotoText.chooseWall)

      model.selectWall("0-0")
      XCTAssertEqual(model.selectedWall?.roomLabel, "Bedroom")
      XCTAssertEqual(model.lengthContinueTitle, SketchPhotoText.enterLength)
      model.length.text = "13' 1.5\""
      XCTAssertEqual(model.lengthContinueTitle, "Continue")
      model.continueFromLength()

      XCTAssertEqual(model.phase, .check)
      let result = try XCTUnwrap(model.result, model.solveError ?? "no result")
      XCTAssertEqual(model.completenessWord, "Limited", "an undimensioned sketch is estimated")
      XCTAssertTrue(model.canFinish)
      XCTAssertEqual(result.model.rooms.count, 1)
      let measurements = try XCTUnwrap(model.measurements)
      XCTAssertEqual(measurements.source.kind, .handSketch)
      XCTAssertEqual(
        measurements.source.interpretation,
        "Original Exports/floor-1/\(model.captureId.rawValue)/sketch-interpretation.json")
      XCTAssertEqual(
        measurements.source.path, "Original Exports/floor-1/\(model.captureId.rawValue)/sketch.jpg")
      // The converter may renumber the walls (counter-clockwise); the typed one is measured.
      let measured = (measurements.rooms.first?.walls ?? []).compactMap(\.length).filter(\.measured)
      XCTAssertEqual(measured.count, 1, "only the typed wall is measured")
      XCTAssertEqual(measured.first?.valueMm ?? 0, 4001.1, accuracy: 1)

      model.backFromCheck()
      XCTAssertEqual(model.phase, .oneLength, "Back goes to the one length")
    }

    func testANoticeLeadsTheNotes() async throws {
      let model = model(StubInterpreter(result: .success(try Self.fixture())), notice: "Demo")
      await model.read(Self.jpeg)
      XCTAssertEqual(model.leadingNotes.first, "Demo")
    }

    func testAPhotoThatIsNotAPlanSaysWhy() async throws {
      var reading = try Self.fixture()
      reading.reading = SketchInterpretation.Reading(
        isFloorPlan: false, problem: "A photo of a cat.", dimensionUnits: .none, rooms: [])
      let model = model(StubInterpreter(result: .success(reading)))
      await model.read(Self.jpeg)
      XCTAssertEqual(model.phase, .problem)
      XCTAssertTrue(model.problemIsNotAPlan)
      XCTAssertEqual(model.problem, "A photo of a cat.")
      model.retake()
      XCTAssertEqual(model.phase, .source)
      XCTAssertNil(model.problem)
    }

    func testAReaderErrorIsShownInItsOwnWords() async {
      struct Offline: Error, CustomStringConvertible {
        var description: String { "The station cannot be reached." }
      }
      let model = model(StubInterpreter(result: .failure(Offline())))
      await model.read(Self.jpeg)
      XCTAssertEqual(model.phase, .problem)
      XCTAssertFalse(model.problemIsNotAPlan)
      XCTAssertEqual(model.problem, "The station cannot be reached.")
    }

    func testCancelDropsTheReading() async throws {
      let model = model(StubInterpreter(result: .success(try Self.fixture()), delay: 300_000_000))
      let reading = Task { await model.read(Self.jpeg) }
      try await Task.sleep(nanoseconds: 50_000_000)
      XCTAssertEqual(model.phase, .reading)
      model.cancelReading()
      await reading.value
      XCTAssertEqual(model.phase, .source, "the late answer is dropped")
      XCTAssertNil(model.interpretation)
    }

    func testFinishFloorWritesThePhotoTheReadingAndTheMeasurements() async throws {
      let model = model(StubInterpreter(result: .success(try Self.fixture())))
      await model.read(Self.jpeg)
      model.selectWall("0-0")
      model.length.text = "13' 1.5\""
      model.continueFromLength()
      let measurements = try XCTUnwrap(model.measurements)
      let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("sketch-photo-\(UUID().uuidString)", isDirectory: true)
      defer { try? FileManager.default.removeItem(at: folder) }
      let written = try SketchFloorWriter.write(
        measurements: measurements, image: model.image, interpretation: model.interpretation,
        to: folder)
      XCTAssertEqual(
        written.map(\.fileName), ["sketch.jpg", "sketch-interpretation.json", "sketch-measurements.json"])
      XCTAssertEqual(
        try Data(contentsOf: folder.appendingPathComponent("sketch.jpg")), Self.jpeg.data,
        "the photo unchanged")
      let kept = try CaptureContractJSON.makeDecoder().decode(
        SketchInterpretation.self,
        from: try Data(contentsOf: folder.appendingPathComponent("sketch-interpretation.json")))
      XCTAssertEqual(kept, model.interpretation)
      let text = try String(
        contentsOf: folder.appendingPathComponent("sketch-interpretation.json"), encoding: .utf8)
      XCTAssertTrue(text.contains("\"ceilingHeightMm\" : null"), "the reading writes its nulls")
    }

    #if canImport(ImageIO)
      /// A large PNG goes as a JPEG at most 2048 px long; a small upright one as it is.
      func testTheUploadIsDownscaledToJPEG() throws {
        func png(width: Int, height: Int) throws -> Data {
          let context = try XCTUnwrap(
            CGContext(
              data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
          context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
          context.fill(CGRect(x: 0, y: 0, width: width, height: height))
          let image = try XCTUnwrap(context.makeImage())
          let data = NSMutableData()
          let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil))
          CGImageDestinationAddImage(destination, image, nil)
          XCTAssertTrue(CGImageDestinationFinalize(destination))
          return data as Data
        }
        let large = try SketchPhotoUpload.prepare(
          SketchImageSelection(data: try png(width: 3000, height: 1500), format: .png))
        XCTAssertEqual(large.mediaType, "image/jpeg")
        let source = try XCTUnwrap(CGImageSourceCreateWithData(large.data as CFData, nil))
        let properties = try XCTUnwrap(
          CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue, 2048)
        XCTAssertEqual((properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue, 1024)

        let smallData = try png(width: 400, height: 300)
        let small = try SketchPhotoUpload.prepare(SketchImageSelection(data: smallData, format: .png))
        XCTAssertEqual(small, SketchPhotoUploadImage(data: smallData, mediaType: "image/png"))
      }
    #endif
  }
#endif

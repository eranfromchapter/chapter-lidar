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

    func testTheDemoReadingIsUnmistakable() async throws {
      let demo = model(StubInterpreter(result: .success(try Self.fixture())))
      XCTAssertNil(demo.banner, "nothing read yet")
      await demo.read(Self.jpeg)
      XCTAssertTrue(demo.isDemoReading, "the fixture's model is demo-fixture")
      XCTAssertEqual(
        demo.banner, "Demo reading \u{2014} not your sketch. Add an API key to read real sketches.")

      var real = try Self.fixture()
      real.model = "claude-opus-5-5"
      let read = model(StubInterpreter(result: .success(real)))
      await read.read(Self.jpeg)
      XCTAssertFalse(read.isDemoReading)
      XCTAssertNil(read.banner)

      let noticed = model(StubInterpreter(result: .success(real)), notice: "Field test")
      XCTAssertEqual(noticed.banner, "Field test", "the host's notice before and after reading")
    }

    func testAnUploadNoteLeadsTheNotes() async throws {
      let model = SketchPhotoModel(
        floorLabel: "Floor 1", areaKey: "floor-1", mode: .room, displayUnits: .imperial,
        interpreter: StubInterpreter(result: .success(try Self.fixture())),
        prepare: { SketchPhotoUploadImage(data: $0.data, mediaType: $0.format.mime, note: "First 3 pages.") })
      await model.read(Self.jpeg)
      model.selectWall("0-0")
      model.length.text = "13'"
      model.continueFromLength()
      XCTAssertEqual(model.phase, .check)
      XCTAssertEqual(model.leadingNotes.first, "First 3 pages.")
    }

    /// Answers each call with the next result (the last one again when they run out), after
    /// `delay` nanoseconds; counts the calls.
    private final class ScriptedInterpreter: SketchInterpreting, @unchecked Sendable {
      private let lock = NSLock()
      private var results: [Result<SketchInterpretation, Error>]
      private(set) var calls = 0
      let delay: UInt64

      init(_ results: [Result<SketchInterpretation, Error>], delay: UInt64 = 0) {
        self.results = results
        self.delay = delay
      }

      func interpret(imageData: Data, mediaType: String) async throws -> SketchInterpretation {
        let result = lock.withLock { () -> Result<SketchInterpretation, Error> in
          calls += 1
          return results.count > 1 ? results.removeFirst() : results[0]
        }
        if delay > 0 { try await Task.sleep(nanoseconds: delay) }
        return try result.get()
      }
    }

    private struct Failed: Error, CustomStringConvertible {
      var description: String { "The Claude API answered 529: overloaded_error" }
    }

    func testAFailedReadingCanBeTriedAgainWithTheSamePhoto() async throws {
      let interpreter = ScriptedInterpreter([.failure(Failed()), .success(try Self.fixture())])
      let model = SketchPhotoModel(
        floorLabel: "Floor 1", areaKey: "floor-1", interpreter: interpreter,
        prepare: { SketchPhotoUploadImage(data: $0.data, mediaType: $0.format.mime) })
      await model.read(Self.jpeg)
      XCTAssertEqual(model.phase, .problem, "a failure waits for the operator, never hand entry")
      XCTAssertFalse(model.problemIsNotAPlan)
      XCTAssertEqual(model.problem, "The Claude API answered 529: overloaded_error")
      model.retry()
      let deadline = Date().addingTimeInterval(5)
      while model.phase != .oneLength, Date() < deadline {
        try await Task.sleep(nanoseconds: 20_000_000)
      }
      XCTAssertEqual(model.phase, .oneLength, "the same photo read again")
      XCTAssertEqual(interpreter.calls, 2)
      XCTAssertEqual(model.image, Self.jpeg)
    }

    func testAReadingStoppedByTheBackgroundSaysTheAppWasClosed() async throws {
      let interpreter = ScriptedInterpreter([.failure(URLError(.networkConnectionLost))], delay: 200_000_000)
      let model = SketchPhotoModel(
        floorLabel: "Floor 1", areaKey: "floor-1", interpreter: interpreter,
        prepare: { SketchPhotoUploadImage(data: $0.data, mediaType: $0.format.mime) })
      let reading = Task { await model.read(Self.jpeg) }
      try await Task.sleep(nanoseconds: 50_000_000)
      XCTAssertEqual(model.phase, .reading)
      model.appDidEnterBackground()
      await reading.value
      XCTAssertEqual(model.phase, .problem)
      XCTAssertEqual(
        model.problem,
        "The reading stopped because the app was closed. Try again and keep the app open.")

      // In the foreground the same failure says its own words.
      await model.read(Self.jpeg)
      XCTAssertEqual(model.phase, .problem)
      XCTAssertNotEqual(model.problem, SketchPhotoText.closedDuringReading)
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

    /// A PDF goes as the PDF itself, every page; the package keeps the original bytes.
    func testAPDFIsSentWhole() throws {
      #if canImport(ImageIO)
        let data = try Self.pdf(pages: 3)
      #else
        let data = Data("%PDF-1.7\n% not parsed on Linux\n%%EOF\n".utf8)
      #endif
      let upload = try SketchPhotoUpload.prepare(SketchImageSelection(data: data, format: .pdf))
      XCTAssertEqual(upload, SketchPhotoUploadImage(data: data, mediaType: "application/pdf"))
      XCTAssertNil(upload.note)
    }

    #if canImport(PDFKit)
      /// A PDF over the page or size limit is trimmed to its first pages, with a note; one whose
      /// first page alone is too large goes as that page drawn as a JPEG.
      func testAPDFOverTheLimitsIsTrimmedToItsFirstPages() throws {
        let data = try Self.pdf(pages: 6)
        let byPages = try SketchPhotoUpload.preparePDF(data, maxPages: 4)
        XCTAssertEqual(byPages.mediaType, "application/pdf")
        XCTAssertEqual(try Self.pageCount(byPages.data), 4)
        XCTAssertEqual(
          byPages.note,
          "The PDF has 6 pages and is too large to send whole: Claude read the first 4 pages.")

        let limit = data.count / 2
        let bySize = try SketchPhotoUpload.preparePDF(data, maxBytes: limit)
        XCTAssertEqual(bySize.mediaType, "application/pdf")
        XCTAssertLessThanOrEqual(bySize.data.count, limit)
        let kept = try Self.pageCount(bySize.data)
        XCTAssertGreaterThanOrEqual(kept, 1)
        XCTAssertLessThan(kept, 6)
        XCTAssertNotNil(bySize.note)

        let tiny = try SketchPhotoUpload.preparePDF(data, maxBytes: 100)
        XCTAssertEqual(tiny.mediaType, "image/jpeg", "not even one page fits")
        XCTAssertNotNil(tiny.note)
      }
    #endif

    #if canImport(ImageIO)
      /// A PDF of `pages` US Letter pages, each with 400 random lines (so pages weigh alike).
      static func pdf(pages: Int) throws -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let consumer = try XCTUnwrap(CGDataConsumer(data: data as CFMutableData))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, nil))
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<pages {
          context.beginPDFPage(nil)
          for _ in 0..<400 {
            let x0 = Double.random(in: 0...612, using: &generator)
            let y0 = Double.random(in: 0...792, using: &generator)
            let x1 = Double.random(in: 0...612, using: &generator)
            let y1 = Double.random(in: 0...792, using: &generator)
            context.move(to: CGPoint(x: x0, y: y0))
            context.addLine(to: CGPoint(x: x1, y: y1))
          }
          context.strokePath()
          context.endPDFPage()
        }
        context.closePDF()
        return data as Data
      }

      static func pageCount(_ data: Data) throws -> Int {
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        return try XCTUnwrap(CGPDFDocument(provider)).numberOfPages
      }

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

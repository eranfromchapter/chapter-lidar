import CaptureContract
import Foundation
import PackageCore
import SketchReading
import SketchSolver
import StationClient
import XCTest

@testable import AppCore

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// "Photograph a sketch" through the app's rules (spec F16): the station reader's answers, the
/// in-process station of the UI tests and field tests, the field-test build's direct Claude
/// request, and the package of a sketch read by Claude.
final class SketchPhotoCaptureTests: XCTestCase {
  /// The UI tests' reading: a 4 x 3 m bedroom, no written dimensions.
  static let fixtureURL = Fixtures.repositoryRoot.appendingPathComponent(
    "ios/App/Sources/App/Debug/UITestSketchInterpretation.json")
  static let schemaURL = Fixtures.repositoryRoot.appendingPathComponent(
    "contract/schema/sketch-interpretation.schema.json")

  /// A 1 x 1 PNG header (IHDR 1600 x 1200), enough for `ImageHeader`.
  static let png: Data = {
    var bytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13]
    bytes += Array("IHDR".utf8)
    bytes += [0, 0, 0x06, 0x40, 0, 0, 0x04, 0xB0, 8, 2, 0, 0, 0]
    return Data(bytes)
  }()

  private func station(_ reader: UITestSketchReader?) throws -> StationSketchInterpreter {
    let transport = UITestStationTransport(storage: UITestBlobStorage(), sketchReader: reader)
    return StationSketchInterpreter(
      station: StationClient(
        configuration: try StationClientConfiguration(stationURL: UITestStationTransport.stationURL),
        tokenProvider: UITestTokenProvider(), transport: transport))
  }

  // MARK: The fixture

  func testTheFixtureIsAContractValidReadingWithoutDimensions() throws {
    let data = try Data(contentsOf: Self.fixtureURL)
    let errors = try SchemaValidator(schemaURL: Self.schemaURL).validate(jsonData: data)
    XCTAssertEqual(errors, [])
    let fixture = try CaptureContractJSON.makeDecoder().decode(SketchInterpretation.self, from: data)
    XCTAssertTrue(fixture.reading.isFloorPlan)
    XCTAssertEqual(fixture.reading.dimensions, [], "no written dimensions: the one-length step runs")
    XCTAssertEqual(fixture.reading.rooms.map(\.label), ["Bedroom"])
    XCTAssertEqual(
      Set(fixture.reading.rooms[0].furniture.map(\.category)), [.bed, .storage])
    XCTAssertEqual(
      Set(fixture.reading.rooms[0].openings.map(\.kind)), [.door, .window])
  }

  // MARK: The station reader

  func testTheStationAnswersTheFixtureWithThePhotosSize() async throws {
    let fixture = try Data(contentsOf: Self.fixtureURL)
    let read = try await station(.fixture(fixture, delay: 0))
      .interpret(imageData: Self.png, mediaType: "image/png")
    XCTAssertEqual(read.image, .init(width: 1600, height: 1200))
    XCTAssertEqual(read.reading.rooms.count, 1)
  }

  func testANonPlanIsNotAFloorPlanWithTheReadingsProblem() async throws {
    var fixture = try CaptureContractJSON.makeDecoder().decode(
      SketchInterpretation.self, from: try Data(contentsOf: Self.fixtureURL))
    fixture.reading = SketchInterpretation.Reading(
      isFloorPlan: false, problem: "The photo shows a cat.", dimensionUnits: .none, rooms: [])
    let data = try CaptureContractJSON.makeEncoder().encode(fixture)
    do {
      _ = try await station(.fixture(data, delay: 0)).interpret(imageData: Self.png, mediaType: "image/png")
      XCTFail("expected notAFloorPlan")
    } catch {
      XCTAssertEqual(error as? SketchReadingError, .notAFloorPlan("The photo shows a cat."))
    }
  }

  func testAStationWithoutAReaderCannotReadSketchesNow() async throws {
    do {
      _ = try await station(nil).interpret(imageData: Self.png, mediaType: "image/png")
      XCTFail("expected unavailable")
    } catch {
      XCTAssertEqual(error as? SketchReaderError, .unavailable)
      XCTAssertEqual(
        (error as? SketchReaderError)?.description,
        "The station cannot read sketches right now. Try again later, or enter the sketch by hand.")
    }
  }

  func testOtherStatusesSayTheProblemTitle() {
    let problem = Problem(type: "about:blank", title: "Bad Gateway", status: 502, code: "sketch_truncated")
    XCTAssertEqual(
      StationSketchInterpreter.readerError(.server(status: 502, problem: problem)),
      .failed("Bad Gateway"))
    XCTAssertEqual(StationSketchInterpreter.readerError(.offline), .offline)
  }

  // MARK: The field-test build's direct request

  private final class Recorder: HTTPTransport, @unchecked Sendable {
    let lock = NSLock()
    var requests: [URLRequest] = []
    let answer: (Int, Data)

    init(status: Int, body: Data) {
      answer = (status, body)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
      lock.withLock { requests.append(request) }
      return (
        answer.1,
        HTTPURLResponse(
          url: request.url!, statusCode: answer.0, httpVersion: "HTTP/1.1", headerFields: [:])!
      )
    }
  }

  private func message(text: String, stopReason: String = "end_turn") throws -> Data {
    try JSONSerialization.data(withJSONObject: [
      "id": "msg_1", "type": "message", "role": "assistant", "model": "claude-opus-5-5",
      "content": [["type": "thinking", "thinking": ""], ["type": "text", "text": text]],
      "stop_reason": stopReason,
    ])
  }

  private func reader(_ transport: Recorder) throws -> FieldTestSketchReader {
    try FieldTestSketchReader(
      apiKey: "test-key-not-real", systemPrompt: "PROMPT",
      interpretationSchema: try Data(contentsOf: Self.schemaURL), transport: transport,
      now: { Date(timeIntervalSince1970: 1_800_000_000) })
  }

  func testTheDirectRequestIsTheMessagesCallWithTheReadingSchema() async throws {
    let fixture = try CaptureContractJSON.makeDecoder().decode(
      SketchInterpretation.self, from: try Data(contentsOf: Self.fixtureURL))
    let readingJSON = String(
      decoding: try CaptureContractJSON.makeEncoder().encode(fixture.reading), as: UTF8.self)
    let transport = Recorder(status: 200, body: try message(text: readingJSON))
    let read = try await reader(transport).read(imageData: Self.png, mediaType: "image/png")
    XCTAssertEqual(read.reading, fixture.reading)
    XCTAssertEqual(read.model, "claude-opus-5-5")
    XCTAssertEqual(read.image, .init(width: 1600, height: 1200))

    let request = try XCTUnwrap(transport.requests.first)
    XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "test-key-not-real")
    XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
    XCTAssertEqual(request.value(forHTTPHeaderField: "content-type"), "application/json")
    let body = try XCTUnwrap(
      JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
    XCTAssertEqual(body["model"] as? String, "claude-opus-5-5")
    XCTAssertEqual(body["max_tokens"] as? Int, 16000)
    XCTAssertEqual(body["system"] as? String, "PROMPT")
    XCTAssertNil(body["thinking"], "Opus 5.5 always thinks; effort sets how hard")
    let config = try XCTUnwrap(body["output_config"] as? [String: Any])
    XCTAssertEqual(config["effort"] as? String, "high")
    let format = try XCTUnwrap(config["format"] as? [String: Any])
    XCTAssertEqual(format["type"] as? String, "json_schema")
    let schema = try XCTUnwrap(format["schema"] as? [String: Any])
    XCTAssertEqual(
      Set((schema["required"] as? [String]) ?? []),
      ["isFloorPlan", "problem", "dimensionUnits", "ceilingHeightMm", "rooms", "dimensions"])
    let schemaText = String(
      decoding: try JSONSerialization.data(withJSONObject: schema), as: UTF8.self)
    XCTAssertFalse(schemaText.contains("$ref"), "references resolved")
    let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
    XCTAssertEqual(messages.count, 1)
    XCTAssertEqual(messages[0]["role"] as? String, "user")
    let content = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
    XCTAssertEqual(content.map { $0["type"] as? String }, ["image", "text"])
    let source = try XCTUnwrap(content[0]["source"] as? [String: Any])
    XCTAssertEqual(source["type"] as? String, "base64")
    XCTAssertEqual(source["media_type"] as? String, "image/png")
    XCTAssertEqual(source["data"] as? String, Self.png.base64EncodedString())
    XCTAssertEqual(content[1]["text"] as? String, "Read this floor-plan sketch.")
  }

  func testARefusalAndAnAPIErrorAreErrors() async throws {
    do {
      _ = try await reader(Recorder(status: 200, body: try message(text: "", stopReason: "refusal")))
        .read(imageData: Self.png, mediaType: "image/png")
      XCTFail("expected a refusal")
    } catch {
      XCTAssertEqual(error as? FieldTestSketchReaderError, .refused)
    }
    let apiError = Data(
      #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#.utf8)
    do {
      _ = try await reader(Recorder(status: 401, body: apiError))
        .read(imageData: Self.png, mediaType: "image/png")
      XCTFail("expected an API error")
    } catch {
      XCTAssertEqual(
        error as? FieldTestSketchReaderError,
        .api(status: 401, message: "authentication_error: invalid x-api-key"))
    }
  }

  // MARK: The package

  func testASketchReadByClaudeIsPackagedWithItsInterpretation() throws {
    let base = try Fixtures.temporaryDirectory()
    defer { Fixtures.removeTemporaryDirectory(base) }
    let example = Fixtures.repositoryRoot.appendingPathComponent(
      "contract/examples/sketch-measurements/valid/two-rooms.json")
    let data = try Data(contentsOf: example)
    let measurements = try CaptureContractJSON.makeDecoder().decode(SketchMeasurements.self, from: data)
    var capture = Make.capture("Floor 1", captureId: measurements.captureId)
    capture.areaKey = measurements.areaKey
    capture.captureSource = .sketch
    let record = Make.record([capture], visitId: measurements.visitId)
    let workspace = try VisitWorkspace.create(in: base)
    let builder = VisitPackageBuilder(workspace: workspace, appVersion: "2.0.0")
    let originals = builder.originalsDirectory(of: capture)
    try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
    try data.write(to: originals.appendingPathComponent(PackageLayout.sketchMeasurementsFileName))
    try Self.png.write(to: originals.appendingPathComponent("sketch.png"))
    try Data(contentsOf: Self.fixtureURL).write(
      to: originals.appendingPathComponent(PackageLayout.sketchInterpretationFileName))

    let plan: VisitPackagePlan
    do {
      plan = try builder.plan(record: record, photos: [], controls: FieldControls(visitId: record.visitId))
    } catch VisitPackageError.captureModel(_, let reason)
      where reason.contains(SketchSolverError.notImplemented.description)
    {
      throw XCTSkip("the sketch solver is not built yet")
    }
    let folder = "Original Exports/\(capture.areaKey)/\(capture.captureId.rawValue)/"
    let entry = { (role: FileRole) in plan.draft.entries.first { $0.input.role == role } }
    let interpretation = try XCTUnwrap(entry(.sketchInterpretation))
    XCTAssertEqual(interpretation.path, folder + "sketch-interpretation.json")
    XCTAssertEqual(interpretation.input.mime, "application/json")
    XCTAssertEqual(interpretation.input.derivedFrom, [folder + "sketch.png"])
    XCTAssertEqual(
      try XCTUnwrap(entry(.sketchMeasurements)).input.derivedFrom,
      [folder + "sketch-interpretation.json", folder + "sketch.png"])
    let model = [
      folder + "sketch-measurements.json", folder + "sketch-interpretation.json",
      folder + "sketch.png",
    ]
    XCTAssertEqual(try XCTUnwrap(entry(.captureModel)).input.derivedFrom, model)
    XCTAssertEqual(try builder.originalPaths(of: capture, in: plan.draft), model)
    XCTAssertNotNil(entry(.meshGLB))

    XCTAssertEqual(
      PackageReview.exportRows([
        .sketchImage, .sketchInterpretation, .sketchMeasurements, .captureModel, .meshGLB,
      ]).last,
      .init(kind: .raw, label: "sketch read by Claude + measurements \u{00B7} capture model", count: 4))
  }

  // MARK: Image headers

  func testTheHeaderGivesThePixelSize() {
    XCTAssertEqual(ImageHeader.size(of: Self.png), .init(width: 1600, height: 1200))
    // SOI, APP0 (length 4), SOF0 with height 300 and width 400.
    let jpeg = Data([
      0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x04, 0x00, 0x00, 0xFF, 0xC0, 0x00, 0x11, 0x08, 0x01, 0x2C,
      0x01, 0x90, 0x03,
    ])
    XCTAssertEqual(ImageHeader.size(of: jpeg), .init(width: 400, height: 300))
    XCTAssertNil(ImageHeader.size(of: Data([1, 2, 3])))
  }
}

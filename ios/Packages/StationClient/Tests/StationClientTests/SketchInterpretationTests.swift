import CaptureContract
import Foundation
import StationClient
import XCTest

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// `POST /sketch-interpretations` (spec F16): the photo goes as base64 JSON with the bearer
/// token; 200 is the interpretation, 422 says why the photo is not a plan, 503 is the station
/// that cannot read sketches now.
final class SketchInterpretationTests: XCTestCase {
  static func example(_ name: String) throws -> String {
    String(
      decoding: try RepoFiles.data("contract/examples/sketch-interpretation/valid/\(name).json"),
      as: UTF8.self)
  }

  func testThePhotoIsSentAsBase64WithTheTokenAndTheReadingComesBack() async throws {
    let transport = StubTransport([.respond(.json(200, try Self.example("bedroom-and-closet")))])
    let image = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
    let interpretation = try await makeClient(transport: transport).createSketchInterpretation(
      SketchInterpretationRequest(mediaType: "image/jpeg", imageData: image))

    XCTAssertTrue(interpretation.reading.isFloorPlan)
    XCTAssertFalse(interpretation.reading.rooms.isEmpty)
    let request = try XCTUnwrap(transport.requests.first)
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.url?.absoluteString, "https://station.test/v1/sketch-interpretations")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    let body = try XCTUnwrap(
      JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
    XCTAssertEqual(body["mediaType"] as? String, "image/jpeg")
    XCTAssertEqual(body["data"] as? String, image.base64EncodedString())
    XCTAssertNil(body["hint"], "omitted when nil")
  }

  func testAPDFIsSentWholeAsADocument() async throws {
    let transport = StubTransport([.respond(.json(200, try Self.example("bedroom-and-closet")))])
    let pdf = Data("%PDF-1.7\n% two pages\n%%EOF\n".utf8)
    _ = try await makeClient(transport: transport).createSketchInterpretation(
      SketchInterpretationRequest(mediaType: "application/pdf", imageData: pdf))
    let request = try XCTUnwrap(transport.requests.first)
    let body = try XCTUnwrap(
      JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
    XCTAssertEqual(body["mediaType"] as? String, "application/pdf")
    XCTAssertEqual(body["data"] as? String, pdf.base64EncodedString(), "the PDF's bytes, untouched")
  }

  func testNotAPlanCarriesTheReadingsProblem() async throws {
    let interpretation = try Self.example("not-a-plan")
    let problem = """
      {"type":"about:blank","title":"Not a floor plan","status":422,"code":"sketch_not_a_plan",
       "detail":"The photo is not a floor plan.","interpretation":\(interpretation)}
      """
    let transport = StubTransport([
      .respond(StubResponse(status: 422, body: Data(problem.utf8), contentType: "application/problem+json"))
    ])
    let error = await captureError {
      _ = try await makeClient(transport: transport).createSketchInterpretation(
        SketchInterpretationRequest(mediaType: "image/png", imageData: Data([1, 2, 3])))
    }
    let rejected = try XCTUnwrap(error as? SketchInterpretationRejected)
    XCTAssertEqual(rejected.problem?.code, "sketch_not_a_plan")
    let reading = try XCTUnwrap(rejected.interpretation?.reading)
    XCTAssertFalse(reading.isFloorPlan)
    XCTAssertEqual(rejected.reason, reading.problem)
  }

  func testARefusalSaysTheDetail() async throws {
    let transport = StubTransport([
      .respond(.problem(422, code: "sketch_refused", detail: "Claude declined to read the photo."))
    ])
    let error = await captureError {
      _ = try await makeClient(transport: transport).createSketchInterpretation(
        SketchInterpretationRequest(mediaType: "image/jpeg", imageData: Data([1])))
    }
    let rejected = try XCTUnwrap(error as? SketchInterpretationRejected)
    XCTAssertNil(rejected.interpretation)
    XCTAssertEqual(rejected.reason, "Claude declined to read the photo.")
  }

  func testAStationWithoutAKeyAnswers503() async throws {
    let transport = StubTransport([
      .respond(.problem(503, code: "sketch_unavailable"))
    ])
    let error = await captureError {
      _ = try await makeClient(transport: transport).createSketchInterpretation(
        SketchInterpretationRequest(mediaType: "image/jpeg", imageData: Data([1])))
    }
    guard case .server(503, let problem)? = error as? StationError else {
      return XCTFail("expected a 503, got \(String(describing: error))")
    }
    XCTAssertEqual(problem?.code, "sketch_unavailable")
  }
}

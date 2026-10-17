import CaptureCore
import CaptureModelMapping
import CaptureTestSupport
import Foundation
import XCTest

final class RawOriginalsTests: XCTestCase {
  private var temporary: URL!

  override func setUpWithError() throws {
    temporary = FileManager.default.temporaryDirectory.appendingPathComponent("CaptureCoreTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: temporary)
  }

  private func fixtureOriginals() throws -> (RawOriginals, Data, Data) {
    let fixture = try Fixtures.load("box-room")
    let roomPlan = try fixture.roomPlanData()
    let depth = try fixture.depthSamplesData()
    let poses = CameraPoseLog(
      intrinsics: CameraIntrinsics(fx: 1400, fy: 1400, cx: 960, cy: 720, imageWidth: 1920, imageHeight: 1440),
      frames: [CameraPose(timestamp: 0.5, transform: .identity)])
    let mesh = RawMeshAnchor(
      identifier: "6a2b69ba-7e80-46dd-9175-2a31a7bb9bae", transform: .identity,
      vertices: [0, 0, 0, 1, 0, 0, 0, 0, 1], triangles: [0, 1, 2])
    return (
      RawOriginals(roomPlanJSON: roomPlan, depthSamples: try DepthSamplesCodec.decode(depth), cameraPoses: poses, meshAnchors: [mesh]),
      roomPlan, depth
    )
  }

  func testDepthSamplesFileRoundTripsByteForByte() throws {
    let data = try Fixtures.load("box-room").depthSamplesData()
    let samples = try DepthSamplesCodec.decode(data)
    XCTAssertGreaterThan(samples.count, 100)
    XCTAssertEqual(DepthSamplesCodec.encode(samples), data, "decode then encode gives the same bytes")
    XCTAssertEqual(data.prefix(4), Data("CHDS".utf8))
    XCTAssertTrue(samples.allSatisfy { $0.confidence <= 2 })
  }

  func testDepthSamplesRejectBadFiles() {
    XCTAssertThrowsError(try DepthSamplesCodec.decode(Data("NOPE".utf8) + Data(count: 12)))
    var data = DepthSamplesCodec.encode([DepthSample(x: 1, y: 2, z: 3, confidence: 2)])
    XCTAssertEqual(data.count, 32)
    data.removeLast()
    XCTAssertThrowsError(try DepthSamplesCodec.decode(data))
    var wrongVersion = DepthSamplesCodec.encode([])
    wrongVersion[4] = 2
    XCTAssertThrowsError(try DepthSamplesCodec.decode(wrongVersion))
  }

  func testDepthFilterKeepsMediumAndHighOnly() {
    let samples = (0...2).map { DepthSample(x: Float($0), y: 0, z: 0, confidence: UInt8($0)) }
    XCTAssertEqual(DepthSamplesCodec.filter(samples).map(\.confidence), [1, 2])
    XCTAssertEqual(DepthSamplesCodec.filter(samples, minimumConfidence: 2).map(\.confidence), [2])
  }

  func testOriginalsAreWrittenUnchanged() throws {
    let (originals, roomPlan, depth) = try fixtureOriginals()
    let folder = temporary.appendingPathComponent("originals")
    let written = try RawOriginalsWriter.write(originals, to: folder)
    XCTAssertEqual(
      written.map(\.fileName), ["roomplan.json", "depth-samples.bin", "camera-poses.json", "mesh-anchors.bin"])
    XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("roomplan.json")), roomPlan)
    XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("depth-samples.bin")), depth)

    let back = try RawOriginalsWriter.read(from: folder)
    XCTAssertEqual(back, originals)
  }

  func testDebugExportWritesExactlyTheThreeReadmeFiles() throws {
    let (originals, roomPlan, depth) = try fixtureOriginals()
    let folder = try DebugOriginalsExport.export(originals, to: temporary, folderName: "2026-11-03-bedroom-a")
    let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    XCTAssertEqual(names, ["camera-poses.json", "depth-samples.bin", "raw-roomplan.json"])
    XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("raw-roomplan.json")), roomPlan)
    XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("depth-samples.bin")), depth)
    // A debug export loads back as a replay source, so it can be fed to ReplaySession.
    XCTAssertNoThrow(try ReplaySource.load(directory: folder))
  }

  func testExistingOriginalsAreNeverOverwritten() throws {
    let (originals, _, _) = try fixtureOriginals()
    let folder = temporary.appendingPathComponent("originals")
    try RawOriginalsWriter.write(originals, to: folder)
    XCTAssertThrowsError(try RawOriginalsWriter.write(originals, to: folder)) {
      guard case .directoryNotEmpty = $0 as? RawOriginalsError else { return XCTFail("\($0)") }
    }
  }

  func testEmptyRoomPlanJSONIsRefused() {
    XCTAssertThrowsError(try RawOriginalsWriter.write(RawOriginals(roomPlanJSON: Data()), to: temporary.appendingPathComponent("x")))
  }

  func testCameraPosesAreEncodedWithSortedKeysAndRoundTrip() throws {
    let (originals, _, _) = try fixtureOriginals()
    let data = try originals.cameraPoses.encoded()
    XCTAssertEqual(try CameraPoseLog.decode(data), originals.cameraPoses)
    XCTAssertEqual(try originals.cameraPoses.encoded(), data, "byte-stable")
  }

  func testMeshAnchorsRoundTripAndRejectBrokenMeshes() throws {
    let (originals, _, _) = try fixtureOriginals()
    let data = try MeshAnchorsCodec.encode(originals.meshAnchors)
    XCTAssertEqual(try MeshAnchorsCodec.decode(data), originals.meshAnchors)
    let bad = RawMeshAnchor(identifier: "6a2b69ba-7e80-46dd-9175-2a31a7bb9bae", transform: .identity, vertices: [0, 0, 0], triangles: [0, 0, 5])
    XCTAssertThrowsError(try MeshAnchorsCodec.encode([bad]))
    XCTAssertThrowsError(try MeshAnchorsCodec.decode(data.dropLast()))
  }
}

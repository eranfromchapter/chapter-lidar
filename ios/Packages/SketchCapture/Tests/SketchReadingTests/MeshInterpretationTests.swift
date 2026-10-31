import CaptureContract
import Foundation
import MeshExport
import SketchMesh
import SketchReading
import SketchSolver
import XCTest

/// AC3 of spec F16: furniture in the reading becomes capture model objects and coloured boxes in
/// the GLB.
final class MeshInterpretationTests: XCTestCase {
  private func solvedExample() throws -> SketchSolveResult {
    try Reading.solve(Reading.convert(Reading.example("bedroom-and-closet")))
  }

  func testAC3FurnitureBecomesObjectsAndColouredBoxesInTheGLB() throws {
    let model = try solvedExample().model
    XCTAssertEqual(model.objects.map(\.id), ["furniture-1", "furniture-2"])
    XCTAssertEqual(model.objects.map(\.category), [.bed, .storage])
    XCTAssertEqual(model.objects.map(\.roomId), ["room-1", "room-1"])
    XCTAssertEqual(model.objects.map(\.confidence), [.low, .low])
    XCTAssertEqual(model.objects[1].box.sizeM.y, 1.8, accuracy: 1e-9)

    let mesh = try SketchMesh.extrude(model)
    XCTAssertNoThrow(try mesh.validate())
    XCTAssertEqual(mesh.colors.count, mesh.vertexCount)
    let bounds = try XCTUnwrap(mesh.bounds)
    XCTAssertEqual(Double(bounds.min.y), 0, accuracy: 1e-6, "the floor is the lowest Y")
    XCTAssertEqual(Double(bounds.max.y), 2.438, accuracy: 1e-5, "the height extent is the room's")

    // Each piece is a closed box of 12 triangles in its category's colour.
    let bedColour = SketchMeshPalette.furniture(.bed)
    let storageColour = SketchMeshPalette.furniture(.storage)
    XCTAssertEqual(mesh.colors.filter { $0 == bedColour }.count, 36)
    XCTAssertEqual(mesh.colors.filter { $0 == storageColour }.count, 36)
    let bedTop = mesh.positions.indices.filter { mesh.colors[$0] == bedColour }.map { mesh.positions[$0].y }.max()
    XCTAssertEqual(Double(bedTop ?? 0), 0.55, accuracy: 1e-6)
    XCTAssertTrue(mesh.colors.contains(SketchMeshPalette.floor))
    XCTAssertTrue(mesh.colors.contains(SketchMeshPalette.wall))
    XCTAssertTrue(mesh.colors.contains(SketchMeshPalette.reveal))
    XCTAssertTrue(mesh.colors.contains(SketchMeshPalette.ceiling))

    // The GLB carries the colour as COLOR_0, one per vertex.
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "sketch-reading-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let floor = FloorMesh(areaKey: "floor-1", label: "Floor 1", mesh: mesh)
    let url = try GLBWriter.write(floors: [floor], to: directory.appendingPathComponent("mesh.glb"))
    let glb = try Data(contentsOf: url)
    XCTAssertEqual(glb[0..<4], Data("glTF".utf8))
    let declared = glb[8..<12].enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
    XCTAssertEqual(declared, glb.count)
    let jsonLength = glb[12..<16].enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
    XCTAssertEqual(glb[16..<20], Data("JSON".utf8))
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: glb[20..<(20 + jsonLength)]) as? [String: Any])
    let meshes = try XCTUnwrap(json["meshes"] as? [[String: Any]])
    let primitive = try XCTUnwrap((meshes.first?["primitives"] as? [[String: Any]])?.first)
    let attributes = try XCTUnwrap(primitive["attributes"] as? [String: Int])
    let accessors = try XCTUnwrap(json["accessors"] as? [[String: Any]])
    let colour = try XCTUnwrap(attributes["COLOR_0"])
    XCTAssertEqual(accessors[colour]["count"] as? Int, mesh.vertexCount)
    XCTAssertEqual(accessors[colour]["type"] as? String, "VEC4")
    XCTAssertEqual(accessors[colour]["componentType"] as? Int, 5121)
    let position = try XCTUnwrap(attributes["POSITION"])
    XCTAssertEqual(accessors[position]["count"] as? Int, mesh.vertexCount)

    // The OBJ carries it as vertex colours: x y z r g b.
    let obj = try OBJWriter.encode(floors: [floor])
    let text = String(decoding: obj.obj, as: UTF8.self)
    let vertices = text.split(separator: "\n").filter { $0.hasPrefix("v ") }
    XCTAssertEqual(vertices.count, mesh.vertexCount)
    XCTAssertTrue(vertices.allSatisfy { $0.split(separator: " ").count == 7 })
  }
}

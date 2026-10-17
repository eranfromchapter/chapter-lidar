import CaptureContract
import Foundation
import XCTest

@testable import MeshExport

/// Locates the repository fixtures and the shared test-output folder.
enum Fixtures {
  static let names = ["box-room", "l-shaped-room", "two-room-apartment", "two-floor-house"]

  /// ios/Packages/MeshExport
  static let packageRoot: URL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()

  static let repoRoot: URL = packageRoot
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

  static let generated = repoRoot.appendingPathComponent("fixtures/generated")

  /// Every file the tests write is collected here for scripts/verify-exports.sh.
  static let testOutput = packageRoot.appendingPathComponent(".build/test-output")

  struct Truth: Decodable {
    struct Capture: Decodable {
      struct Bounds: Decodable {
        var min: [Double]
        var max: [Double]
      }
      var captureId: String
      var areaKey: String
      var label: String
      var boundsM: Bounds
    }
    var fixture: String
    var captures: [Capture]
  }

  /// One capture of a fixture with its inputs.
  struct Capture {
    var fixture: String
    var truth: Truth.Capture
    var directory: URL
    var model: CaptureModel

    var objURL: URL { directory.appendingPathComponent("mesh.obj") }
    var depthURL: URL { directory.appendingPathComponent("depth-samples.bin") }

    func floorMesh(withColors: Bool = true) throws -> FloorMesh {
      var mesh = try OBJFixtureReader.read(objURL)
      if withColors {
        mesh.colors = mesh.positions.map { p in
          RGB8(
            r: UInt8(Swift.max(0, Swift.min(255, Int(p.x * 40)))),
            g: UInt8(Swift.max(0, Swift.min(255, Int(p.y * 90)))),
            b: UInt8(Swift.max(0, Swift.min(255, Int(p.z * 40)))))
        }
      }
      return FloorMesh(areaKey: truth.areaKey, label: truth.label, mesh: mesh)
    }

    func depthSamples() throws -> [DepthSample] {
      try DepthSampleFile.read(contentsOf: depthURL)
    }
  }

  static func captures(of fixture: String) throws -> [Capture] {
    let root = generated.appendingPathComponent(fixture)
    let truth = try JSONDecoder().decode(
      Truth.self, from: Data(contentsOf: root.appendingPathComponent("truth.json")))
    return try truth.captures.map { capture in
      let directory = root.appendingPathComponent(
        "package/Original Exports/\(capture.areaKey)/\(capture.captureId)")
      let model = try JSONDecoder().decode(
        CaptureModel.self,
        from: Data(contentsOf: directory.appendingPathComponent("capture-model.json")))
      return Capture(fixture: fixture, truth: capture, directory: directory, model: model)
    }
  }

  static func allCaptures() throws -> [Capture] {
    try names.flatMap { try captures(of: $0) }
  }

  /// Folder under the shared test output for one fixture capture.
  static func outputDirectory(_ parts: String...) -> URL {
    parts.reduce(testOutput) { $0.appendingPathComponent($1) }
  }
}

/// Reads the fixtures' own mesh.obj (written by the TypeScript generator, independent of the
/// writers under test). Positions and normals only; `f a/b/c` faces.
enum OBJFixtureReader {
  static func read(_ url: URL) throws -> TriangleMesh {
    let text = try String(contentsOf: url, encoding: .utf8)
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var indices: [UInt32] = []
    for line in text.split(separator: "\n") {
      let parts = line.split(separator: " ")
      guard let tag = parts.first else { continue }
      switch tag {
      case "v":
        positions.append(SIMD3(Float(parts[1])!, Float(parts[2])!, Float(parts[3])!))
      case "vn":
        normals.append(SIMD3(Float(parts[1])!, Float(parts[2])!, Float(parts[3])!))
      case "f":
        for corner in parts.dropFirst() {
          indices.append(UInt32(corner.split(separator: "/")[0])! - 1)
        }
      default:
        break
      }
    }
    return TriangleMesh(positions: positions, normals: normals, indices: indices)
  }
}

/// Mesh builders for decimation and performance tests.
enum MeshFactory {
  /// Splits every triangle into n x n triangles (flat, same surface).
  static func subdivided(_ mesh: TriangleMesh, _ n: Int) -> TriangleMesh {
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var colors: [RGB8] = []
    var indices: [UInt32] = []
    let hasNormals = !mesh.normals.isEmpty
    let hasColors = !mesh.colors.isEmpty
    var corner = 0
    while corner + 2 < mesh.indices.count {
      let ia = Int(mesh.indices[corner])
      let ib = Int(mesh.indices[corner + 1])
      let ic = Int(mesh.indices[corner + 2])
      corner += 3
      let base = UInt32(positions.count)
      var rowStart: [Int: UInt32] = [:]
      for i in 0...n {
        rowStart[i] = UInt32(positions.count)
        for j in 0...(n - i) {
          let u = Float(i) / Float(n)
          let v = Float(j) / Float(n)
          let w = 1 - u - v
          positions.append(mesh.positions[ia] * w + mesh.positions[ib] * u + mesh.positions[ic] * v)
          if hasNormals { normals.append(mesh.normals[ia]) }
          if hasColors { colors.append(mesh.colors[ia]) }
        }
      }
      _ = base
      for i in 0..<n {
        for j in 0..<(n - i) {
          let a = rowStart[i]! + UInt32(j)
          let b = rowStart[i + 1]! + UInt32(j)
          let c = rowStart[i]! + UInt32(j) + 1
          indices.append(contentsOf: [a, b, c])
          if j < n - i - 1 {
            let d = rowStart[i + 1]! + UInt32(j) + 1
            indices.append(contentsOf: [b, d, c])
          }
        }
      }
    }
    return TriangleMesh(positions: positions, normals: normals, colors: colors, indices: indices)
  }

  /// Surface area of a mesh.
  static func area(_ mesh: TriangleMesh) -> Double {
    var total = 0.0
    var corner = 0
    while corner + 2 < mesh.indices.count {
      let a = mesh.positions[Int(mesh.indices[corner])]
      let b = mesh.positions[Int(mesh.indices[corner + 1])]
      let c = mesh.positions[Int(mesh.indices[corner + 2])]
      let n = cross3(b - a, c - a)
      total += Double((n.x * n.x + n.y * n.y + n.z * n.z).squareRoot()) / 2
      corner += 3
    }
    return total
  }
}

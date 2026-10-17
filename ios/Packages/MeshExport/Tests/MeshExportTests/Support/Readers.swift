import Foundation
import XCTest

@testable import MeshExport

/// Independent readers of the written files (the writers are not reused to check themselves).
struct GLBContents {
  var json: [String: Any]
  var bin: [UInt8]

  struct NodeData {
    var name: String
    var positions: [SIMD3<Float>]
    var normals: [SIMD3<Float>]
    var colors: [[UInt8]]
    var indices: [UInt32]
    var hasMatrix: Bool
  }

  static func read(_ data: Data) throws -> GLBContents {
    let bytes = [UInt8](data)
    func u32(_ o: Int) -> Int {
      Int(bytes[o]) | Int(bytes[o + 1]) << 8 | Int(bytes[o + 2]) << 16 | Int(bytes[o + 3]) << 24
    }
    XCTAssertEqual(u32(0), 0x4654_6C67)
    XCTAssertEqual(u32(4), 2)
    XCTAssertEqual(u32(8), bytes.count, "GLB length field")
    let jsonLength = u32(12)
    XCTAssertEqual(u32(16), 0x4E4F_534A)
    XCTAssertEqual(jsonLength % 4, 0)
    let jsonData = Data(bytes[20..<(20 + jsonLength)])
    let json = try JSONSerialization.jsonObject(with: jsonData) as! [String: Any]
    let binHeader = 20 + jsonLength
    let binLength = u32(binHeader)
    XCTAssertEqual(u32(binHeader + 4), 0x004E_4942)
    XCTAssertEqual(binLength % 4, 0)
    let bin = Array(bytes[(binHeader + 8)..<(binHeader + 8 + binLength)])
    XCTAssertEqual(binHeader + 8 + binLength, bytes.count)
    return GLBContents(json: json, bin: bin)
  }

  var generator: String {
    ((json["asset"] as! [String: Any])["generator"] as? String) ?? ""
  }

  var nodes: [[String: Any]] { json["nodes"] as! [[String: Any]] }

  func floorData(_ nodeIndex: Int) -> NodeData {
    let node = nodes[nodeIndex]
    let mesh = (json["meshes"] as! [[String: Any]])[node["mesh"] as! Int]
    let primitive = (mesh["primitives"] as! [[String: Any]])[0]
    let attributes = primitive["attributes"] as! [String: Int]
    let positions = vec3s(attributes["POSITION"]!)
    let normals = vec3s(attributes["NORMAL"]!)
    var colors: [[UInt8]] = []
    if let colorIndex = attributes["COLOR_0"] {
      let (view, accessor) = viewAndAccessor(colorIndex)
      let offset = (view["byteOffset"] as? Int ?? 0) + (accessor["byteOffset"] as? Int ?? 0)
      let count = accessor["count"] as! Int
      for i in 0..<count { colors.append(Array(bin[(offset + i * 4)..<(offset + i * 4 + 4)])) }
    }
    let (iview, iaccessor) = viewAndAccessor(primitive["indices"] as! Int)
    let ioffset = (iview["byteOffset"] as? Int ?? 0) + (iaccessor["byteOffset"] as? Int ?? 0)
    let icount = iaccessor["count"] as! Int
    let wide = (iaccessor["componentType"] as! Int) == 5125
    var indices: [UInt32] = []
    for i in 0..<icount {
      if wide {
        let o = ioffset + i * 4
        indices.append(
          UInt32(bin[o]) | UInt32(bin[o + 1]) << 8 | UInt32(bin[o + 2]) << 16
            | UInt32(bin[o + 3]) << 24)
      } else {
        let o = ioffset + i * 2
        indices.append(UInt32(bin[o]) | UInt32(bin[o + 1]) << 8)
      }
    }
    return NodeData(
      name: node["name"] as? String ?? "", positions: positions, normals: normals, colors: colors,
      indices: indices,
      hasMatrix: node["matrix"] != nil || node["rotation"] != nil || node["translation"] != nil
        || node["scale"] != nil)
  }

  private func viewAndAccessor(_ index: Int) -> ([String: Any], [String: Any]) {
    let accessor = (json["accessors"] as! [[String: Any]])[index]
    let view = (json["bufferViews"] as! [[String: Any]])[accessor["bufferView"] as! Int]
    return (view, accessor)
  }

  private func vec3s(_ accessorIndex: Int) -> [SIMD3<Float>] {
    let (view, accessor) = viewAndAccessor(accessorIndex)
    let offset = (view["byteOffset"] as? Int ?? 0) + (accessor["byteOffset"] as? Int ?? 0)
    let count = accessor["count"] as! Int
    func f(_ o: Int) -> Float {
      Float(
        bitPattern: UInt32(bin[o]) | UInt32(bin[o + 1]) << 8 | UInt32(bin[o + 2]) << 16
          | UInt32(bin[o + 3]) << 24)
    }
    return (0..<count).map { i in
      SIMD3(f(offset + i * 12), f(offset + i * 12 + 4), f(offset + i * 12 + 8))
    }
  }
}

/// Parsed OBJ for the checks.
struct OBJContents {
  var mtllib: [String] = []
  var objects: [String] = []
  var positions: [[Double]] = []  // x y z [r g b]
  var normalCount = 0
  var faces: [[Int]] = []
  var materialsUsed: [String] = []

  init(_ text: String) {
    for line in text.split(separator: "\n") {
      let parts = line.split(separator: " ", omittingEmptySubsequences: true)
      guard let tag = parts.first else { continue }
      switch tag {
      case "mtllib": mtllib.append(parts.dropFirst().joined(separator: " "))
      case "o": objects.append(String(parts[1]))
      case "v": positions.append(parts.dropFirst().map { Double($0)! })
      case "vn": normalCount += 1
      case "usemtl": materialsUsed.append(String(parts[1]))
      case "f": faces.append(parts.dropFirst().map { Int($0.split(separator: "/")[0])! })
      default: break
      }
    }
  }

  var bounds: (min: [Double], max: [Double]) {
    var lo = [Double.infinity, .infinity, .infinity]
    var hi = [-Double.infinity, -.infinity, -.infinity]
    for p in positions {
      for axis in 0..<3 {
        lo[axis] = Swift.min(lo[axis], p[axis])
        hi[axis] = Swift.max(hi[axis], p[axis])
      }
    }
    return (lo, hi)
  }
}

/// Reads a LAS 1.4 file: header fields and all point records.
struct LASContents {
  var bytes: [UInt8]

  init(_ data: Data) { bytes = [UInt8](data) }

  func u16(_ o: Int) -> Int { Int(bytes[o]) | Int(bytes[o + 1]) << 8 }
  func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
  func i32(_ o: Int) -> Int { Int(Int32(truncatingIfNeeded: u32(o))) }
  func u64(_ o: Int) -> UInt64 {
    (0..<8).reduce(UInt64(0)) { $0 | UInt64(bytes[o + $1]) << UInt64(8 * $1) }
  }
  func f64(_ o: Int) -> Double { Double(bitPattern: u64(o)) }
  func ascii(_ o: Int, _ n: Int) -> String {
    String(decoding: bytes[o..<(o + n)].prefix { $0 != 0 }, as: UTF8.self)
  }

  var signature: String { ascii(0, 4) }
  var versionMajor: Int { Int(bytes[24]) }
  var versionMinor: Int { Int(bytes[25]) }
  var globalEncoding: Int { u16(6) }
  var systemIdentifier: String { ascii(26, 32) }
  var generatingSoftware: String { ascii(58, 32) }
  var headerSize: Int { u16(94) }
  var pointDataOffset: Int { u32(96) }
  var vlrCount: Int { u32(100) }
  var format: Int { Int(bytes[104]) }
  var recordLength: Int { u16(105) }
  var legacyCount: Int { u32(107) }
  var scale: [Double] { [f64(131), f64(139), f64(147)] }
  var offset: [Double] { [f64(155), f64(163), f64(171)] }
  var pointCount: Int { Int(u64(247)) }
  var headerMax: [Double] { [f64(179), f64(195), f64(211)] }
  var headerMin: [Double] { [f64(187), f64(203), f64(219)] }

  /// Real coordinates and 8-bit-scaled colours of every record.
  func points() -> [(xyz: [Double], rgb: [Int], gps: Double, intensity: Int)] {
    (0..<pointCount).map { i in
      let base = pointDataOffset + i * recordLength
      let xyz = (0..<3).map { Double(i32(base + $0 * 4)) * scale[$0] + offset[$0] }
      return (
        xyz, [u16(base + 30), u16(base + 32), u16(base + 34)], f64(base + 22), u16(base + 12)
      )
    }
  }

  /// Extents recomputed from the records.
  func recomputedExtents() -> (min: [Double], max: [Double]) {
    var lo = [Double.infinity, .infinity, .infinity]
    var hi = [-Double.infinity, -.infinity, -.infinity]
    for p in points() {
      for axis in 0..<3 {
        lo[axis] = Swift.min(lo[axis], p.xyz[axis])
        hi[axis] = Swift.max(hi[axis], p.xyz[axis])
      }
    }
    return (lo, hi)
  }
}

import CaptureContract

// Small double-precision vector and matrix types for the mapping math. RoomPlan reports simd
// float values; the JSON of those values is decoded into doubles here, so the same code runs on
// Linux and on device.

public struct Vector3: Hashable, Sendable {
  public var x: Double
  public var y: Double
  public var z: Double

  public init(_ x: Double, _ y: Double, _ z: Double) {
    self.x = x
    self.y = y
    self.z = z
  }

  public static let zero = Vector3(0, 0, 0)

  public static func + (a: Vector3, b: Vector3) -> Vector3 {
    Vector3(a.x + b.x, a.y + b.y, a.z + b.z)
  }

  public static func - (a: Vector3, b: Vector3) -> Vector3 {
    Vector3(a.x - b.x, a.y - b.y, a.z - b.z)
  }

  public static func * (a: Vector3, s: Double) -> Vector3 {
    Vector3(a.x * s, a.y * s, a.z * s)
  }

  public func dot(_ other: Vector3) -> Double {
    x * other.x + y * other.y + z * other.z
  }

  public var length: Double { dot(self).squareRoot() }

  /// The vector scaled to length 1, or nil when it has no length.
  public var normalized: Vector3? {
    let l = length
    return l > 1e-12 ? self * (1 / l) : nil
  }

  /// The contract wire type, rounded to a micrometre so output is stable and has no `-0`.
  public var contractVec3: Vec3 {
    Vec3(x: x.cleaned, y: y.cleaned, z: z.cleaned)
  }
}

extension Double {
  /// Rounded to 1e-6 (a micrometre), with negative zero turned into zero.
  var cleaned: Double {
    let rounded = (self * 1_000_000).rounded() / 1_000_000
    return rounded == 0 ? 0 : rounded
  }
}

/// A 4x4 matrix stored column-major, like simd_float4x4: `columns[3]` holds the translation.
public struct Matrix4: Hashable, Sendable {
  public var columns: [[Double]]

  /// nil unless `columns` is four columns of four numbers.
  public init?(columns: [[Double]]) {
    guard columns.count == 4, columns.allSatisfy({ $0.count == 4 }) else { return nil }
    self.columns = columns
  }

  public static let identity = Matrix4(columns: [
    [1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1],
  ])!

  /// Axis `index` (0, 1 or 2): the first three numbers of that column.
  public func axis(_ index: Int) -> Vector3 {
    Vector3(columns[index][0], columns[index][1], columns[index][2])
  }

  public var translation: Vector3 { axis(3) }

  /// Maps a point from the local frame of this matrix into its parent frame.
  public func apply(to point: Vector3) -> Vector3 {
    axis(0) * point.x + axis(1) * point.y + axis(2) * point.z + translation
  }

  /// Unit quaternion of the rotation part, with `w >= 0` so equal rotations give equal numbers.
  /// Axes are normalized first, so a uniform scale does not matter.
  public var rotation: Quaternion {
    let a0 = axis(0).normalized ?? Vector3(1, 0, 0)
    let a1 = axis(1).normalized ?? Vector3(0, 1, 0)
    let a2 = axis(2).normalized ?? Vector3(0, 0, 1)
    // r<row><column>
    let r00 = a0.x
    let r10 = a0.y
    let r20 = a0.z
    let r01 = a1.x
    let r11 = a1.y
    let r21 = a1.z
    let r02 = a2.x
    let r12 = a2.y
    let r22 = a2.z
    var x: Double
    var y: Double
    var z: Double
    var w: Double
    let trace = r00 + r11 + r22
    if trace > 0 {
      let s = (trace + 1).squareRoot() * 2
      w = 0.25 * s
      x = (r21 - r12) / s
      y = (r02 - r20) / s
      z = (r10 - r01) / s
    } else if r00 > r11 && r00 > r22 {
      let s = (1 + r00 - r11 - r22).squareRoot() * 2
      w = (r21 - r12) / s
      x = 0.25 * s
      y = (r01 + r10) / s
      z = (r02 + r20) / s
    } else if r11 > r22 {
      let s = (1 + r11 - r00 - r22).squareRoot() * 2
      w = (r02 - r20) / s
      x = (r01 + r10) / s
      y = 0.25 * s
      z = (r12 + r21) / s
    } else {
      let s = (1 + r22 - r00 - r11).squareRoot() * 2
      w = (r10 - r01) / s
      x = (r02 + r20) / s
      y = (r12 + r21) / s
      z = 0.25 * s
    }
    let norm = (x * x + y * y + z * z + w * w).squareRoot()
    x /= norm
    y /= norm
    z /= norm
    w /= norm
    if w < 0 {
      x = -x
      y = -y
      z = -z
      w = -w
    }
    return Quaternion(x: x.cleaned, y: y.cleaned, z: z.cleaned, w: w.cleaned)
  }
}

extension Matrix4: Decodable {
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let columns = try container.decode([[Double]].self)
    guard let matrix = Matrix4(columns: columns) else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Expected a 4x4 matrix as four columns of four numbers")
    }
    self = matrix
  }
}

extension Matrix4: Encodable {
  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(columns)
  }
}

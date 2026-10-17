import CaptureContract

/// Plan-view polygon helpers. Plan coordinates are X and Z (the model is +Y up).
public enum PolygonMath {
  /// Signed shoelace sum in (x, z). Negative means counter-clockwise seen from +Y, which is the
  /// winding the capture model requires for room polygons.
  public static func signedArea(_ points: [Vector3]) -> Double {
    guard points.count >= 3 else { return 0 }
    var sum = 0.0
    for index in points.indices {
      let a = points[index]
      let b = points[(index + 1) % points.count]
      sum += a.x * b.z - b.x * a.z
    }
    return sum / 2
  }

  public static func area(_ points: [Vector3]) -> Double {
    abs(signedArea(points))
  }

  public static func perimeter(_ points: [Vector3]) -> Double {
    guard points.count >= 2 else { return 0 }
    var sum = 0.0
    for index in points.indices {
      let a = points[index]
      let b = points[(index + 1) % points.count]
      sum += ((b.x - a.x) * (b.x - a.x) + (b.z - a.z) * (b.z - a.z)).squareRoot()
    }
    return sum
  }

  /// Drops a repeated closing point (the contract wants the first point not repeated).
  public static func openLoop(_ points: [Vector3], tolerance: Double = 1e-6) -> [Vector3] {
    guard points.count > 1, let first = points.first, let last = points.last else { return points }
    if (first - last).length <= tolerance {
      return Array(points.dropLast())
    }
    return points
  }

  /// The same loop wound counter-clockwise seen from +Y. A clockwise loop keeps its first point
  /// and reverses the rest; a loop that is already counter-clockwise is returned unchanged.
  public static func counterClockwise(_ points: [Vector3]) -> [Vector3] {
    guard signedArea(points) > 0, let first = points.first else { return points }
    return [first] + points.dropFirst().reversed()
  }

  /// Horizontal distance from `point` to the infinite line through `start` and `end`, and the
  /// position of the point's projection along the segment (0 at `start`, `length` at `end`).
  static func project(_ point: Vector3, onto start: Vector3, _ end: Vector3) -> (
    distance: Double, along: Double
  )? {
    let dx = end.x - start.x
    let dz = end.z - start.z
    let length = (dx * dx + dz * dz).squareRoot()
    guard length > 1e-9 else { return nil }
    let ux = dx / length
    let uz = dz / length
    let px = point.x - start.x
    let pz = point.z - start.z
    let along = px * ux + pz * uz
    let distance = abs(px * -uz + pz * ux)
    return (distance, along)
  }
}

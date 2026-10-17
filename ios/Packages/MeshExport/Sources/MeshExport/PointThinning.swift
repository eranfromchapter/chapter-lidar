import Foundation

public struct ThinningOptions: Sendable, Equatable {
  /// Default voxel edge: 5 mm.
  public static let defaultVoxelSize = 0.005
  /// Default cap on the points written: 20 million.
  public static let defaultMaxPoints = 20_000_000

  /// Voxel edge in metres. At most one point is kept per voxel.
  public var voxelSize: Double
  /// Hard cap on the output. If the occupied voxels exceed it, the voxel edge grows in steps
  /// of 25% until they fit (so the cap is never exceeded and the whole room stays covered).
  public var maxPoints: Int
  /// Samples below this confidence (0 low, 1 medium, 2 high) are dropped. Default keeps all.
  public var minimumConfidence: UInt8

  public init(
    voxelSize: Double = ThinningOptions.defaultVoxelSize,
    maxPoints: Int = ThinningOptions.defaultMaxPoints,
    minimumConfidence: UInt8 = 0
  ) {
    self.voxelSize = voxelSize
    self.maxPoints = maxPoints
    self.minimumConfidence = minimumConfidence
  }
}

public struct ThinningResult: Sendable {
  public var points: [DepthSample]
  /// The voxel edge actually used: the requested one, or larger if the cap forced it.
  public var effectiveVoxelSize: Double
  /// Grid origin (Double of the minimum corner of the kept input). Voxel index of a point is
  /// `floor((p - gridOrigin) / effectiveVoxelSize)` per axis.
  public var gridOrigin: SIMD3<Double>
  public var inputCount: Int
  public var droppedLowConfidence: Int
}

/// Voxel thinning of depth samples: keeps the sample nearest to the centre of every occupied
/// voxel, in input order, so the result is deterministic.
public enum PointThinning {
  private struct VoxelKey: Hashable {
    var x: Int32
    var y: Int32
    var z: Int32
  }

  public static func thin(
    _ samples: [DepthSample], options: ThinningOptions = ThinningOptions()
  ) throws -> ThinningResult {
    guard options.voxelSize > 0, options.voxelSize.isFinite else {
      throw MeshExportError.invalidOption("voxel size must be positive")
    }
    guard options.maxPoints > 0 else {
      throw MeshExportError.invalidOption("point cap must be positive")
    }
    var candidates: [Int] = []
    candidates.reserveCapacity(samples.count)
    var origin = SIMD3<Double>(repeating: .infinity)
    for (index, s) in samples.enumerated() {
      guard s.confidence >= options.minimumConfidence else { continue }
      guard s.x.isFinite, s.y.isFinite, s.z.isFinite else { continue }
      candidates.append(index)
      origin = SIMD3(Swift.min(origin.x, Double(s.x)), Swift.min(origin.y, Double(s.y)), Swift.min(origin.z, Double(s.z)))
    }
    let dropped = samples.count - candidates.count
    guard !candidates.isEmpty else {
      return ThinningResult(
        points: [], effectiveVoxelSize: options.voxelSize, gridOrigin: .zero,
        inputCount: samples.count, droppedLowConfidence: dropped)
    }

    var voxel = options.voxelSize
    while true {
      let kept = pass(samples, candidates: candidates, origin: origin, voxel: voxel)
      if kept.count <= options.maxPoints {
        return ThinningResult(
          points: kept.map { samples[$0] }, effectiveVoxelSize: voxel, gridOrigin: origin,
          inputCount: samples.count, droppedLowConfidence: dropped)
      }
      voxel *= 1.25
    }
  }

  /// One thinning pass: indices of the kept samples, ascending.
  private static func pass(
    _ samples: [DepthSample], candidates: [Int], origin: SIMD3<Double>, voxel: Double
  ) -> [Int] {
    var best: [VoxelKey: (index: Int, distance: Double)] = [:]
    best.reserveCapacity(Swift.min(candidates.count, 1 << 22))
    for index in candidates {
      let s = samples[index]
      let fx = (Double(s.x) - origin.x) / voxel
      let fy = (Double(s.y) - origin.y) / voxel
      let fz = (Double(s.z) - origin.z) / voxel
      let key = VoxelKey(
        x: Int32(clamping: Int(fx.rounded(.down))), y: Int32(clamping: Int(fy.rounded(.down))),
        z: Int32(clamping: Int(fz.rounded(.down))))
      let dx = fx - fx.rounded(.down) - 0.5
      let dy = fy - fy.rounded(.down) - 0.5
      let dz = fz - fz.rounded(.down) - 0.5
      let distance = dx * dx + dy * dy + dz * dz
      if let current = best[key] {
        if distance < current.distance { best[key] = (index, distance) }
      } else {
        best[key] = (index, distance)
      }
    }
    return best.values.map { $0.index }.sorted()
  }
}

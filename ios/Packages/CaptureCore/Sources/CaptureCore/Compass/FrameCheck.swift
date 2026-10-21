import CaptureContract
import Foundation

/// The frame check at Finish floor (compass §3.4): does RoomPlan's final geometry (after
/// `RoomBuilder` / `StructureBuilder`) sit in the ARKit world frame of the live scan? Each
/// surface's plan-frame yaw in the last live update is compared with its yaw in the final
/// result, matched by identifier.
public enum FrameCheck {
  /// Fewest matched surfaces for a measured φ.
  public static let minimumMatches = 3
  /// Share of the matches that must lie within `agreement` of their median.
  public static let consensusShare = 0.7
  /// Degrees.
  public static let agreement = 2.0
  /// A measured φ larger than this is logged (`compass.frame_yaw`).
  public static let logThreshold = 2.0

  public struct Outcome: Hashable, Sendable {
    /// φ to add to H_W: the measured one when the surfaces agree, else the convention of device
    /// test D1 (`CompassMath.captureFrameYaw`).
    public var frameYaw: Double
    public var matches: Int
    /// True when φ was measured.
    public var consensus: Bool
  }

  /// The plan-frame angle of a surface's local X axis from the first column of its transform:
  /// `a = (columns.0.x, columns.0.z)`, `yaw = atan2(−a.z, a.x)` in degrees.
  public static func yaw(columnX x: Double, z: Double) -> Double {
    atan2(-z, x) * 180 / .pi
  }

  /// φ from the live and final yaws (identifier → degrees). Each φ_i = wrap(final − live) into
  /// (−90°, 90°], since a surface may be re-fitted end for end. With ≥ 3 matches and ≥ 70 % of
  /// them within 2° of their median, φ = the median; otherwise `fallback`.
  public static func frameYaw(
    live: [String: Double], final: [String: Double],
    fallback: Double = CompassMath.captureFrameYaw
  ) -> Outcome {
    let differences = final.compactMap { identifier, finalYaw in
      live[identifier].map { CompassMath.wrap90(finalYaw - $0) }
    }
    guard differences.count >= minimumMatches else {
      return Outcome(frameYaw: fallback, matches: differences.count, consensus: false)
    }
    let sorted = differences.sorted()
    let middle = sorted.count / 2
    let median =
      sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    let agreeing = sorted.filter { abs(CompassMath.wrap90($0 - median)) <= agreement }.count
    guard Double(agreeing) >= consensusShare * Double(sorted.count) else {
      return Outcome(frameYaw: fallback, matches: differences.count, consensus: false)
    }
    return Outcome(frameYaw: median, matches: differences.count, consensus: true)
  }
}

import CaptureContract
import CaptureModelMapping
import Foundation

// Furniture drawn on a sketch (spec F16 section 5) as capture model objects: an oriented box
// standing on the floor, its height by category when the sketch gave none.

extension SketchDefaults {
  /// The height a piece of furniture gets when the sketch does not give one, millimetres. Stairs
  /// take the room's height (nil here). Every height is clamped to the room's height.
  public static func furnitureHeightMm(_ category: ObjectCategory) -> Double? {
    switch category {
    case .bed: return 550
    case .sofa: return 850
    case .chair: return 900
    case .table: return 750
    case .storage: return 1800
    case .toilet: return 750
    case .sink: return 900
    case .bathtub: return 600
    case .stove: return 900
    case .oven: return 900
    case .refrigerator: return 1800
    case .dishwasher: return 850
    case .washerDryer: return 900
    case .television: return 600
    case .fireplace: return 1000
    case .stairs: return nil
    case .other: return 800
    }
  }
}

enum SketchFurniture {
  /// The room's furniture as objects: centre at half the height above the floor, size
  /// [width, height, depth], turned about +Y by `angleDeg`, confidence low (a drawing, not a
  /// measurement). A piece with no width or depth is left out.
  static func objects(
    _ furniture: [SketchMeasurements.Furniture], roomId: String, roomHeightMm: Double
  ) -> [CaptureModel.DetectedObject] {
    furniture.compactMap { item in
      guard item.widthM.isFinite, item.depthM.isFinite, item.widthM > 0, item.depthM > 0,
        item.x.isFinite, item.z.isFinite
      else { return nil }
      let roomHeightM: Double = roomHeightMm / 1000
      var heightM: Double = SketchDefaults.furnitureHeightMm(item.category).map { $0 / 1000 } ?? roomHeightM
      if let given = item.heightM, given.isFinite, given > 0 { heightM = given }
      heightM = min(heightM, roomHeightM)
      let half: Double = heightM / 2
      let center = Vector3(item.x, half, item.z).contractVec3
      let size = Vector3(item.widthM, heightM, item.depthM).contractVec3
      return CaptureModel.DetectedObject(
        id: item.id, category: item.category, roomId: roomId,
        box: CaptureModel.OrientedBox(center: center, sizeM: size, rotation: yaw(item.angleDeg)),
        confidence: .low)
    }
  }

  /// The unit quaternion of a turn by `degrees` about +Y (counter-clockwise seen from +Y, the
  /// right-hand rule), rounded so output is stable.
  static func yaw(_ degrees: Double) -> Quaternion {
    guard degrees.isFinite else { return .identity }
    let half: Double = degrees * Double.pi / 360
    let s: Double = rounded(sin(half))
    let c: Double = rounded(cos(half))
    if s == 0 { return .identity }
    return Quaternion(x: 0, y: s, z: 0, w: c)
  }

  private static func rounded(_ value: Double) -> Double {
    let result = (value * 1e9).rounded() / 1e9
    return result == 0 ? 0 : result
  }
}

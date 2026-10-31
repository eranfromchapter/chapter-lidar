import CaptureContract
import MeshExport

/// The colours of the sketch's 3D model (spec F16 section 5): per-vertex colours the GLB writes
/// as `COLOR_0` and the OBJ as vertex colours. Muted, so the model reads as a plan in 3D rather
/// than a render; furniture categories differ enough to tell apart at a glance.
public enum SketchMeshPalette {
  /// Wall faces, ends and tops: warm white.
  public static let wall = RGB8(r: 238, g: 233, b: 224)
  /// The floor: oak.
  public static let floor = RGB8(r: 190, g: 150, b: 105)
  /// The jambs, sills and heads of door, window and opening cut-outs: light grey.
  public static let reveal = RGB8(r: 210, g: 210, b: 210)
  /// The ceiling underside: white.
  public static let ceiling = RGB8(r: 250, g: 250, b: 248)

  /// A furniture block's colour by category.
  public static func furniture(_ category: ObjectCategory) -> RGB8 {
    switch category {
    case .bed: return RGB8(r: 132, g: 158, b: 186)  // dusty blue
    case .sofa: return RGB8(r: 122, g: 145, b: 112)  // sage
    case .chair: return RGB8(r: 184, g: 124, b: 92)  // terracotta
    case .table: return RGB8(r: 120, g: 88, b: 64)  // walnut
    case .storage: return RGB8(r: 168, g: 152, b: 130)  // taupe
    case .toilet: return RGB8(r: 226, g: 234, b: 238)  // porcelain
    case .sink: return RGB8(r: 200, g: 214, b: 222)  // pale blue-grey
    case .bathtub: return RGB8(r: 214, g: 228, b: 234)  // porcelain blue
    case .stove: return RGB8(r: 86, g: 88, b: 94)  // charcoal
    case .oven: return RGB8(r: 108, g: 108, b: 116)  // graphite
    case .refrigerator: return RGB8(r: 192, g: 198, b: 204)  // steel
    case .dishwasher: return RGB8(r: 164, g: 170, b: 178)  // brushed steel
    case .washerDryer: return RGB8(r: 182, g: 200, b: 212)  // laundry blue
    case .television: return RGB8(r: 48, g: 48, b: 54)  // screen black
    case .fireplace: return RGB8(r: 152, g: 86, b: 70)  // brick
    case .stairs: return RGB8(r: 158, g: 128, b: 98)  // stair wood
    case .other: return RGB8(r: 176, g: 166, b: 190)  // muted lavender
    }
  }
}

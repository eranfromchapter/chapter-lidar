import CaptureContract
import Foundation

/// The outline the operator picks for a room (spec F14 1.3): a rectangle (four walls, every
/// corner a left turn), an L-shape (six walls, one right turn at the inside corner), or any
/// other rectilinear outline with `corners` corners whose turns the operator sets per corner.
public enum SketchRoomShape: Hashable, Sendable {
  case rectangle
  /// `insideWall` (0 ... 5) is the wall whose end corner is the re-entrant one.
  case lShape(insideWall: Int)
  case other(corners: Int)

  public static let minimumCorners = 3
  public static let maximumCorners = 12

  /// The segmented control's three choices.
  public enum Kind: String, CaseIterable, Hashable, Sendable {
    case rectangle
    case lShape
    case other

    public var title: String {
      switch self {
      case .rectangle: return "Rectangle"
      case .lShape: return "L-shape"
      case .other: return "Other"
      }
    }

    /// The shape a fresh choice of this kind starts as.
    public var defaultShape: SketchRoomShape {
      switch self {
      case .rectangle: return .rectangle
      case .lShape: return .lShape(insideWall: 1)
      case .other: return .other(corners: 5)
      }
    }
  }

  public var kind: Kind {
    switch self {
    case .rectangle: return .rectangle
    case .lShape: return .lShape
    case .other: return .other
    }
  }

  public var wallCount: Int {
    switch self {
    case .rectangle: return 4
    case .lShape: return 6
    case .other(let corners):
      return min(max(corners, Self.minimumCorners), Self.maximumCorners)
    }
  }

  /// The turn at the end of wall `index` that the shape fixes; nil when the operator sets it
  /// (any wall of "other").
  public func fixedTurn(atEndOfWall index: Int) -> SketchTurn? {
    switch self {
    case .rectangle: return .left
    case .lShape(let inside): return index == inside ? .right : .left
    case .other: return nil
    }
  }
}

/// One wall of a room as entered: its length, the corner at its end, whether it is exterior and
/// which wall of an earlier room is the same partition.
public struct SketchWallDraft: Hashable, Sendable, Identifiable {
  public var id: String
  public var length: SketchLengthField
  /// The corner at the end of this wall (spec 2.3): left, right or unsquare.
  public var turn: SketchTurn
  public var isExterior: Bool
  public var sharedWith: SketchMeasurements.SharedWall?

  public init(
    id: String, length: SketchLengthField, turn: SketchTurn = .left, isExterior: Bool = false,
    sharedWith: SketchMeasurements.SharedWall? = nil
  ) {
    self.id = id
    self.length = length
    self.turn = turn
    self.isExterior = isExterior
    self.sharedWith = sharedWith
  }
}

/// A corner-to-corner distance through the room: the diagonal across an unsquare corner, or
/// the squareness check of a rectangle ("Also measured").
public struct SketchDiagonalDraft: Hashable, Sendable, Identifiable {
  public var from: Int
  public var to: Int
  public var length: SketchLengthField

  public init(from: Int, to: Int, length: SketchLengthField) {
    self.from = from
    self.to = to
    self.length = length
  }

  public var id: String { "\(from)-\(to)" }
}

/// A door, window or opening in one wall as entered: the required set (width, distance from a
/// corner; sill and height for a window) and the "Also measured" door height.
public struct SketchOpeningDraft: Hashable, Sendable, Identifiable {
  public var id: String
  public var kind: SketchOpeningKind
  public var wallId: String
  public var width: SketchLengthField
  public var height: SketchLengthField
  /// Windows only.
  public var sill: SketchLengthField
  public var fromCorner: SketchWallCorner
  public var fromCornerDistance: SketchLengthField

  public init(
    id: String, kind: SketchOpeningKind, wallId: String, units: SketchUnits,
    fromCorner: SketchWallCorner = .start
  ) {
    self.id = id
    self.kind = kind
    self.wallId = wallId
    width = SketchLengthField(unit: units.short)
    height = SketchLengthField(unit: units.short)
    sill = SketchLengthField(unit: units.short)
    self.fromCorner = fromCorner
    fromCornerDistance = SketchLengthField(unit: units.short)
  }

  /// "Door 1", "Window 2", "Opening 1", from the id.
  public var title: String { SketchText.openingTitle(id: id, kind: kind) }
}

/// One room as entered on the Rooms and measurements screen.
public struct SketchRoomDraft: Hashable, Sendable, Identifiable {
  public var id: String
  /// The room's name as the operator wrote it ("Bedroom"); the capture model's label.
  public var label: String
  public var type: RoomType?
  public var shape: SketchRoomShape
  /// "Are all corners square?" Off: the turn of each corner is chosen, and an unsquare corner
  /// needs a diagonal across it.
  public var allCornersSquare: Bool
  /// In order around the room, counter-clockwise seen from above as drawn.
  public var walls: [SketchWallDraft]
  public var diagonals: [SketchDiagonalDraft]
  public var openings: [SketchOpeningDraft]
  /// This room's own ceiling height, when it differs from the floor's.
  public var ceilingHeight: SketchLengthField

  public init(
    id: String, label: String = "", type: RoomType? = nil, shape: SketchRoomShape = .rectangle,
    allCornersSquare: Bool = true, walls: [SketchWallDraft], diagonals: [SketchDiagonalDraft] = [],
    openings: [SketchOpeningDraft] = [], ceilingHeight: SketchLengthField
  ) {
    self.id = id
    self.label = label
    self.type = type
    self.shape = shape
    self.allCornersSquare = allCornersSquare
    self.walls = walls
    self.diagonals = diagonals
    self.openings = openings
    self.ceilingHeight = ceilingHeight
  }

  public var cleanedLabel: String { label.trimmingCharacters(in: .whitespacesAndNewlines) }

  /// The name shown for the room: its label, else "Room N" for its position.
  public func displayName(position: Int) -> String {
    cleanedLabel.isEmpty ? "Room \(position)" : cleanedLabel
  }

  public func wall(_ wallId: String) -> SketchWallDraft? {
    walls.first { $0.id == wallId }
  }

  /// Corner `i` is the start of wall `i`; the corner at the end of wall `i` is `i + 1`.
  public func corner(atEndOfWall index: Int) -> Int {
    (index + 1) % max(walls.count, 1)
  }

  /// The corners (by index) the operator marked unsquare, each needing a diagonal across it:
  /// from the corner before it to the corner after it.
  public var unsquareCorners: [Int] {
    guard !allCornersSquare else { return [] }
    return walls.indices.filter { walls[$0].turn == .unsquare }.map(corner(atEndOfWall:))
  }

  /// The two corners of the diagonal across `corner`: its neighbours. Nil for a triangle, whose
  /// neighbours are neighbours of each other.
  public func diagonalCorners(across corner: Int) -> (from: Int, to: Int)? {
    let count = walls.count
    guard count >= 4 else { return nil }
    return ((corner + count - 1) % count, (corner + 1) % count)
  }

  public func diagonal(from: Int, to: Int) -> SketchDiagonalDraft? {
    diagonals.first { ($0.from == from && $0.to == to) || ($0.from == to && $0.to == from) }
  }

  /// The squareness check of a four-cornered room: corner 0 to corner 2.
  public var checkDiagonalCorners: (from: Int, to: Int)? {
    walls.count >= 4 ? (0, 2) : nil
  }

  /// The axis (0 or 1) of each wall from the turns around the room, starting along axis 0;
  /// an unsquare corner is counted as a left turn, the way a sketch draws it (spec 1.2).
  public var wallAxes: [Int] {
    var direction = 0
    return walls.map { wall in
      let axis = direction % 2
      switch wall.turn {
      case .left, .unsquare: direction = (direction + 1) % 4
      case .right: direction = (direction + 3) % 4
      }
      return axis
    }
  }

  /// Walls the required set still needs (spec 1.3): on each axis at most one wall may be
  /// unmeasured (closure fills it); every further unmeasured wall on that axis is listed, in
  /// wall order.
  public var wallsStillRequired: [SketchWallDraft] {
    let axes = wallAxes
    var required: [SketchWallDraft] = []
    for axis in [0, 1] {
      let unmeasured = walls.indices.filter { axes[$0] == axis && !walls[$0].length.isEntered }
      if unmeasured.count > 1 {
        required.append(contentsOf: unmeasured.dropFirst().map { walls[$0] })
      }
    }
    return required.sorted { a, b in
      (walls.firstIndex { $0.id == a.id } ?? 0) < (walls.firstIndex { $0.id == b.id } ?? 0)
    }
  }
}

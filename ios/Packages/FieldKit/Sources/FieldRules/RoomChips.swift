import Foundation

/// Which Room chips the labeling screen shows before `More`.
public enum RoomChips {
  /// How many rooms are shown before `More` (artboard 2d-1: Kitchen, Living, Bath 1, Bedroom 1).
  public static let shownBeforeMore = 4

  /// The first `shownBeforeMore` rooms, then `target` when it is further down the list: pass the
  /// selected room (it stays selected for the next photo) or the room the operator came for
  /// ("Take photo" on "Closet has no photo"), so its chip is on screen, not behind `More`. The
  /// order of the list is kept.
  public static func primary(_ rooms: [String], target: String?) -> [String] {
    var shown = Array(rooms.prefix(shownBeforeMore))
    if let target,
      let room = rooms.first(where: { PhotoCoverage.key($0) == PhotoCoverage.key(target) }),
      !shown.contains(room)
    {
      shown.append(room)
    }
    return shown
  }

  /// The rooms behind `More`: every room not in `primary(_:target:)`, in order.
  public static func more(_ rooms: [String], target: String?) -> [String] {
    let shown = primary(rooms, target: target)
    return rooms.filter { !shown.contains($0) }
  }
}

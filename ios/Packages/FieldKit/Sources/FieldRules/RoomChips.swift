import Foundation

/// Which Room chips the labeling screen shows before "More…".
public enum RoomChips {
  /// How many rooms are shown before "More…".
  public static let shownBeforeMore = 3

  /// The first `shownBeforeMore` rooms, and the room the operator came for (`target`: "Take
  /// photo" on "Closet has no photo") after them when it is further down the list, so that
  /// room's chip is on screen and chosen, not behind "More…". The order of the list is kept.
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

  /// The rooms behind "More…": every room not in `primary(_:target:)`, in order.
  public static func more(_ rooms: [String], target: String?) -> [String] {
    let shown = primary(rooms, target: target)
    return rooms.filter { !shown.contains($0) }
  }
}

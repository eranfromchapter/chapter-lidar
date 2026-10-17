import CaptureContract
import Foundation

/// Room measurement CSV: UTF-8 without BOM, header row, one row per room, LF line endings.
///
/// Lengths are whole millimetres plus the same lengths in feet-inches. Width is the room's
/// extent along the plan x axis and length the extent along the plan y axis (for a rotated
/// outline: along its longest edge and the edge normal, width being the one nearer to x).
/// The last line is a `#` comment saying that reported area is not a verified construction
/// quantity.
public enum CSVWriter {
  public static let fileName = "rooms.csv"
  public static let header = [
    "floor", "room_id", "room_label", "width_mm", "length_mm", "height_mm", "floor_area_m2",
    "perimeter_mm", "door_count", "window_count", "width_ftin", "length_ftin", "height_ftin",
  ]
  public static let note = "Reported floor area is not a verified construction quantity."

  public static func write(model: CaptureModel) throws -> ExportedFile {
    let geometry = try PlanGeometry(model: model)
    var rows = [header.joined(separator: ",")]
    for room in geometry.rooms {
      let width = room.widthM * 1000
      let length = room.lengthM * 1000
      let height = room.heightM * 1000
      let cells = [
        cell(model.label, text: true),
        cell(room.id, text: true),
        cell(room.label, text: true),
        String(Format.millimetres(room.widthM)),
        String(Format.millimetres(room.lengthM)),
        String(Format.millimetres(room.heightM)),
        Format.fixed(room.areaM2, 3),
        String(Format.millimetres(room.perimeterM)),
        String(room.doorCount),
        String(room.windowCount),
        cell(Format.feetInches(millimetres: width), text: false),
        cell(Format.feetInches(millimetres: length), text: false),
        cell(Format.feetInches(millimetres: height), text: false),
      ]
      rows.append(cells.joined(separator: ","))
    }
    rows.append("# \(note)")
    let text = rows.joined(separator: "\n") + "\n"
    return ExportedFile(
      fileName: fileName, role: .roomsCSV, mime: "text/csv", data: Data(text.utf8))
  }

  /// RFC 4180 quoting. Free text that a spreadsheet would read as a formula gets a leading
  /// apostrophe.
  static func cell(_ value: String, text: Bool) -> String {
    var value = Format.singleLine(value)
    if text, let first = value.unicodeScalars.first, "=+-@".unicodeScalars.contains(first) {
      value = "'" + value
    }
    if value.contains(",") || value.contains("\"") {
      return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    return value
  }
}

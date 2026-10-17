import CaptureContract
import Foundation
import XCTest

@testable import PlanExport

final class CSVWriterTests: XCTestCase {
  /// Parses RFC 4180 rows (quoted cells with doubled quotes). Comment lines start with `#`.
  private func parse(_ text: String) -> (rows: [[String]], comments: [String]) {
    var rows: [[String]] = []
    var comments: [String] = []
    for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
      if line.hasPrefix("#") {
        comments.append(String(line))
        continue
      }
      var cells: [String] = []
      var current = ""
      var quoted = false
      var iterator = line.makeIterator()
      var pending: Character? = iterator.next()
      while let character = pending {
        pending = iterator.next()
        if quoted {
          if character == "\"" {
            if pending == "\"" {
              current.append("\"")
              pending = iterator.next()
            } else {
              quoted = false
            }
          } else {
            current.append(character)
          }
        } else if character == "\"" {
          quoted = true
        } else if character == "," {
          cells.append(current)
          current = ""
        } else {
          current.append(character)
        }
      }
      cells.append(current)
      rows.append(cells)
    }
    return (rows, comments)
  }

  func testRoomDimensionsAndAreasMatchTruthForAllFourShapes() throws {
    for capture in try Fixtures.all() {
      let file = try CSVWriter.write(model: capture.model)
      try Repo.write(file, folder: capture.outputFolder)
      let (rows, comments) = parse(String(decoding: file.data, as: UTF8.self))
      XCTAssertEqual(rows.first, CSVWriter.header)
      XCTAssertEqual(rows.count - 1, capture.truth.rooms.count)
      XCTAssertEqual(comments, ["# Reported floor area is not a verified construction quantity."])
      for room in capture.truth.rooms {
        let row = try XCTUnwrap(rows.dropFirst().first { $0[1] == room.id }, room.id)
        let name = "\(capture.fixture) \(capture.truth.areaKey) \(room.id)"
        XCTAssertEqual(row[0], capture.truth.label)
        XCTAssertEqual(row[2], room.label)
        XCTAssertEqual(try XCTUnwrap(Double(row[3])), room.widthM * 1000, accuracy: 1, name)
        XCTAssertEqual(try XCTUnwrap(Double(row[4])), room.lengthM * 1000, accuracy: 1, name)
        XCTAssertEqual(try XCTUnwrap(Double(row[5])), room.heightM * 1000, accuracy: 1, name)
        XCTAssertEqual(try XCTUnwrap(Double(row[6])), room.areaM2, accuracy: 0.01, name)
        XCTAssertEqual(try XCTUnwrap(Double(row[7])), room.perimeterM * 1000, accuracy: 1, name)
        // Dimensions are whole millimetres.
        XCTAssertNotNil(Int(row[3]))
        XCTAssertNotNil(Int(row[4]))
        XCTAssertNotNil(Int(row[5]))
        XCTAssertNotNil(Int(row[7]))
      }
    }
  }

  func testFeetInchesColumnsMatchTheMillimetreColumns() throws {
    let capture = try XCTUnwrap(Fixtures.load("two-room-apartment").first)
    let (rows, _) = parse(String(decoding: try CSVWriter.write(model: capture.model).data, as: UTF8.self))
    let living = try XCTUnwrap(rows.first { $0[1] == "room-1" })
    XCTAssertEqual(living[10], "16' 4.85\"")  // 5000 mm
    XCTAssertEqual(living[11], "13' 1.48\"")  // 4000 mm
    XCTAssertEqual(living[12], "8' 10.30\"")  // 2700 mm
  }

  func testDoorAndWindowCountsCountOpeningsOnTheRoomsWalls() throws {
    let capture = try XCTUnwrap(Fixtures.load("two-room-apartment").first)
    let (rows, _) = parse(String(decoding: try CSVWriter.write(model: capture.model).data, as: UTF8.self))
    let living = try XCTUnwrap(rows.first { $0[1] == "room-1" })
    let bedroom = try XCTUnwrap(rows.first { $0[1] == "room-2" })
    // The door is in the partition shared by both rooms, so it counts for both.
    XCTAssertEqual(living[8], "1")
    XCTAssertEqual(bedroom[8], "1")
    XCTAssertEqual(living[9], "1")
    XCTAssertEqual(bedroom[9], "1")
  }

  func testFeetInchesFormatting() {
    XCTAssertEqual(Format.feetInches(millimetres: 0), "0' 0.00\"")
    XCTAssertEqual(Format.feetInches(millimetres: 304.8), "1' 0.00\"")
    XCTAssertEqual(Format.feetInches(millimetres: 4000), "13' 1.48\"")
    XCTAssertEqual(Format.feetInches(millimetres: 2700), "8' 10.30\"")
    // 11.996 in rounds up to a whole foot, never 11' 12.00".
    XCTAssertEqual(Format.feetInches(millimetres: 11.996 * 25.4), "1' 0.00\"")
    XCTAssertEqual(Format.feetInches(millimetres: 304.8 - 0.01 * 25.4), "0' 11.99\"")
  }

  func testQuotingAndFormulaGuard() {
    XCTAssertEqual(CSVWriter.cell("Kitchen, north", text: true), "\"Kitchen, north\"")
    XCTAssertEqual(CSVWriter.cell("The \"Den\"", text: true), "\"The \"\"Den\"\"\"")
    XCTAssertEqual(CSVWriter.cell("=SUM(A1)", text: true), "'=SUM(A1)")
    XCTAssertEqual(CSVWriter.cell("-1 Basement", text: true), "'-1 Basement")
    XCTAssertEqual(CSVWriter.cell("a\nb", text: true), "a b")
    XCTAssertEqual(CSVWriter.cell("-5' 0.00\"", text: false), "\"-5' 0.00\"\"\"")
  }

  func testFileIsUTF8WithoutBOMAndEndsWithNote() throws {
    var model = Synthetic.room(width: 4, length: 3, label: "Caf\u{00E9}")
    model.label = "Etage 1"
    let file = try CSVWriter.write(model: model)
    XCTAssertNotEqual(Array(file.data.prefix(3)), [0xEF, 0xBB, 0xBF])
    let text = try XCTUnwrap(String(data: file.data, encoding: .utf8))
    XCTAssertTrue(text.contains("Caf\u{00E9}"))
    XCTAssertTrue(text.hasSuffix("# Reported floor area is not a verified construction quantity.\n"))
    XCTAssertFalse(text.contains("\r"))
    XCTAssertEqual(file.fileName, "rooms.csv")
    XCTAssertEqual(file.role, .roomsCSV)
  }

  func testRotatedRoomIsMeasuredAlongItsEdges() throws {
    // A 6 x 4 m room turned 30 degrees: width 6 m, length 4 m, not the bounding box.
    let angle = 30.0 * .pi / 180
    let base = [(0.0, 0.0), (0.0, 4.0), (6.0, 4.0), (6.0, 0.0)]
    let polygon = base.map { x, z in
      Vec3(x: x * cos(angle) - z * sin(angle), y: 0, z: x * sin(angle) + z * cos(angle))
    }
    var model = Synthetic.room(width: 6, length: 4)
    model.rooms[0].polygon = polygon
    let (rows, _) = parse(String(decoding: try CSVWriter.write(model: model).data, as: UTF8.self))
    let row = try XCTUnwrap(rows.dropFirst().first)
    XCTAssertEqual(Double(row[3])!, 6000, accuracy: 1)
    XCTAssertEqual(Double(row[4])!, 4000, accuracy: 1)
    XCTAssertEqual(Double(row[6])!, 24, accuracy: 0.01)
  }

  func testRoomWithoutPolygonPointsThrows() {
    var model = Synthetic.room(width: 4, length: 3)
    model.rooms[0].polygon = Array(model.rooms[0].polygon.prefix(2))
    XCTAssertThrowsError(try CSVWriter.write(model: model))
  }
}

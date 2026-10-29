import CaptureContract
import CaptureTestSupport
import Foundation
import SketchEntry
import SketchSolver
import XCTest

#if canImport(Observation)
  /// The guided entry (spec F14 2.1): the required set of 1.6 is asked in order and nothing
  /// else is required; a rectangle with two walls, a ceiling, a door and a window is complete;
  /// ids are unique across the capture; the document round-trips and validates against
  /// `sketch-measurements.schema.json`.
  @MainActor
  final class EntryTests: XCTestCase {
    func model() -> SketchEntryModel {
      let model = SketchEntryModel(
        visitId: LowercaseUUID(rawValue: "7c4e1b9a-2d3f-4a68-9b5c-e0f1a2b3c4d5")!,
        captureId: LowercaseUUID(rawValue: "a81d5f03-6c2e-4b97-8d14-2f9e7b3c5a60")!,
        floorLabel: "Floor 1", mode: .floor)
      model.continueToRooms()
      return model
    }

    func field(_ text: String, unit: EnteredUnit, measured: Bool = true) -> SketchLengthField {
      SketchLengthField(text: text, unit: unit, measured: measured)
    }

    /// The bedroom of `contract/examples/sketch-measurements/valid/two-rooms.json`: walls 1 and
    /// 2 measured, the ceiling 8', a door in wall 3 and a window in wall 1.
    func bedroom(_ model: SketchEntryModel) -> String {
      let room = model.rooms[0].id
      model.update(room) { draft in
        draft.label = "Bedroom"
        draft.type = .bedroom
        draft.walls[0].length = self.field("13' 1.5\"", unit: .ftIn)
        draft.walls[0].isExterior = true
        draft.walls[1].length = self.field("9' 10.5\"", unit: .ftIn)
      }
      model.ceilingHeight = field("8' 0\"", unit: .ftIn)
      let door = model.addOpening(room, kind: .door, wallId: model.rooms[0].walls[2].id)
      model.updateOpening(room, door) { opening in
        opening.width = self.field("32", unit: .inches)
        opening.fromCorner = .start
        opening.fromCornerDistance = self.field("12", unit: .inches)
      }
      let window = model.addOpening(room, kind: .window, wallId: model.rooms[0].walls[0].id)
      model.updateOpening(room, window) { opening in
        opening.width = self.field("36", unit: .inches)
        opening.sill = self.field("36", unit: .inches)
        opening.height = self.field("48", unit: .inches)
        opening.fromCorner = .end
        opening.fromCornerDistance = self.field("48", unit: .inches)
      }
      return room
    }

    // MARK: The required set

    func testTheRequiredSetIsAskedInOrderAndNothingElse() {
      let model = model()
      XCTAssertEqual(model.step, .rooms)
      XCTAssertEqual(model.rooms.count, 1, "Continue adds the first room")
      let room = model.rooms[0].id
      XCTAssertEqual(
        model.missingRequired,
        ["Ceiling height", "Room 1: name", "Room 1: 2 more wall lengths (Wall 3, Wall 4)"])

      model.ceilingHeight = field("8' 0\"", unit: .ftIn)
      model.update(room) { $0.label = "Bedroom" }
      XCTAssertEqual(
        model.missingRequired, ["Bedroom: 2 more wall lengths (Wall 3, Wall 4)"],
        "a rectangle needs two adjacent walls (1.3)")

      // One wall on an axis is filled from closure; the second one is required (1.3).
      model.update(room) { $0.walls[0].length = self.field("13' 1.5\"", unit: .ftIn) }
      XCTAssertEqual(model.missingRequired, ["Bedroom: 1 more wall length (Wall 4)"])
      let door = model.addOpening(room, kind: .door, wallId: model.rooms[0].walls[2].id)
      let window = model.addOpening(room, kind: .window, wallId: model.rooms[0].walls[0].id)
      XCTAssertEqual(
        model.missingRequired,
        [
          "Bedroom: 1 more wall length (Wall 4)",
          "Bedroom: Door 1 width", "Bedroom: Door 1 distance from the corner",
          "Bedroom: Window 1 width", "Bedroom: Window 1 distance from the corner",
          "Bedroom: Window 1 sill height", "Bedroom: Window 1 height",
        ])
      model.updateOpening(room, door) {
        $0.width = self.field("32", unit: .inches)
        $0.fromCornerDistance = self.field("12", unit: .inches)
      }
      model.updateOpening(room, window) {
        $0.width = self.field("36", unit: .inches)
        $0.fromCornerDistance = self.field("48", unit: .inches)
        $0.sill = self.field("36", unit: .inches)
        $0.height = self.field("48", unit: .inches)
      }
      XCTAssertEqual(model.missingRequired, ["Bedroom: 1 more wall length (Wall 4)"])
      model.update(room) { $0.walls[1].length = self.field("9' 10.5\"", unit: .ftIn) }
      XCTAssertEqual(model.missingRequired, [], "the required set of 1.6, nothing more")

      // The recommended items (other walls, the diagonal, the door height) are never required.
      XCTAssertFalse(model.rooms[0].walls[2].length.isEntered)
      XCTAssertFalse(model.rooms[0].walls[3].length.isEntered)
      XCTAssertNil(model.rooms[0].openings[0].height.length)
      XCTAssertEqual(model.rooms[0].diagonals, [])

      // An L-shape with one wall per axis missing is complete; two on one axis are not.
      let hall = model.addRoom()
      model.setShape(hall, .lShape(insideWall: 1))
      model.update(hall) { draft in
        draft.label = "Hall"
        for index in [0, 1, 2, 3] { draft.walls[index].length = self.field("3 m", unit: .m) }
      }
      XCTAssertEqual(model.rooms[1].walls.map(\.turn), [.left, .right, .left, .left, .left, .left])
      XCTAssertEqual(model.rooms[1].wallAxes, [0, 1, 0, 1, 0, 1])
      XCTAssertEqual(model.missingRequired, [])
      model.update(hall) { $0.walls[2].length = self.field("", unit: .m) }
      XCTAssertEqual(model.missingRequired, ["Hall: 1 more wall length (Wall 5)"])

      // An unsquare corner needs the diagonal across it.
      model.setAllCornersSquare(hall, false)
      model.setTurn(hall, wallIndex: 0, .unsquare)
      XCTAssertEqual(model.rooms[1].unsquareCorners, [1])
      XCTAssertTrue(model.missingRequired.contains("Hall: diagonal across corner 2"))
      model.setDiagonal(hall, from: 0, to: 2, field("4.2", unit: .m))
      XCTAssertFalse(model.missingRequired.contains("Hall: diagonal across corner 2"))
      model.setAllCornersSquare(hall, true)
      XCTAssertEqual(model.rooms[1].walls[0].turn, .left, "square again: the shape's turn")
    }

    func testARectangleWithTwoWallsACeilingADoorAndAWindowIsComplete() throws {
      let model = model()
      _ = bedroom(model)
      XCTAssertEqual(model.missingRequired, [])
      let document = model.measurements
      XCTAssertEqual(document.rooms.count, 1)
      XCTAssertEqual(document.rooms[0].label, "Bedroom")
      XCTAssertEqual(document.rooms[0].walls.compactMap(\.length?.valueMm), [4000.5, 3009.9])
      XCTAssertEqual(document.rooms[0].walls[0].exterior, true)
      XCTAssertNil(document.rooms[0].walls[1].exterior)
      XCTAssertNil(document.rooms[0].walls[0].turn, "left is the default and is not written")
      XCTAssertEqual(document.ceilingHeight?.valueMm, 2438.4)
      XCTAssertEqual(document.rooms[0].openings.map(\.id), ["door-1", "window-1"])
      XCTAssertEqual(document.rooms[0].openings[0].wallId, "wall-3")
      XCTAssertEqual(document.rooms[0].openings[0].width?.valueMm, 812.8)
      XCTAssertNil(document.rooms[0].openings[0].sill, "a door has no sill")
      XCTAssertEqual(document.rooms[0].openings[1].sill?.valueMm, 914.4)
      XCTAssertEqual(document.rooms[0].openings[1].fromCorner, .end)
      XCTAssertEqual(document.source.kind, .none)
      XCTAssertNil(document.source.path)

      // The solver: once it is built, the capture is complete; until then the error is kept.
      if let result = model.solve() {
        XCTAssertEqual(result.summary.measurements, .complete)
        XCTAssertEqual(model.completenessWord, "Complete")
        XCTAssertTrue(model.canFinish)
      } else {
        XCTAssertEqual(model.solveError, SketchSolverError.notImplemented.description)
        XCTAssertEqual(model.completenessWord, "Not solved")
      }
    }

    // MARK: Ids

    func testIdsAreUniqueAcrossTheCapture() {
      let model = model()
      let first = model.rooms[0].id
      let door = model.addOpening(first, kind: .door, wallId: model.rooms[0].walls[0].id)
      let second = model.addRoom()
      model.setShape(second, .other(corners: 7))
      let window = model.addOpening(second, kind: .window, wallId: model.rooms[1].walls[6].id)
      model.removeOpening(first, door)
      let door2 = model.addOpening(first, kind: .door, wallId: model.rooms[0].walls[1].id)
      let passage = model.addOpening(first, kind: .opening, wallId: model.rooms[0].walls[1].id)
      XCTAssertEqual([first, second], ["room-1", "room-2"])
      XCTAssertEqual(door, "door-1")
      XCTAssertEqual(door2, "door-2", "a removed opening's id is never reused")
      XCTAssertEqual(window, "window-1")
      XCTAssertEqual(passage, "opening-1")
      XCTAssertEqual(model.rooms[0].walls.map(\.id), ["wall-1", "wall-2", "wall-3", "wall-4"])
      XCTAssertEqual(model.rooms[1].walls.count, 7)
      XCTAssertEqual(model.rooms[1].walls.first?.id, "wall-5")
      XCTAssertEqual(model.rooms[1].walls.last?.id, "wall-11")

      var ids: [String] = []
      for room in model.rooms {
        ids.append(room.id)
        ids.append(contentsOf: room.walls.map(\.id))
        ids.append(contentsOf: room.openings.map(\.id))
      }
      XCTAssertEqual(Set(ids).count, ids.count, "every id is unique: \(ids)")

      // Shrinking a room keeps its first walls and drops openings of walls that went away.
      model.setShape(second, .rectangle)
      XCTAssertEqual(model.rooms[1].walls.map(\.id), ["wall-5", "wall-6", "wall-7", "wall-8"])
      XCTAssertEqual(model.rooms[1].openings, [])
      model.setShape(second, .lShape(insideWall: 3))
      XCTAssertEqual(model.rooms[1].walls.count, 6)
      XCTAssertEqual(model.rooms[1].walls[3].turn, .right)
      XCTAssertEqual(model.rooms[1].walls.last?.id, "wall-13", "new walls get new ids")

      // A removed room is no longer shared with.
      let third = model.addRoom()
      model.setSharedWall(third, wallId: model.rooms[2].walls[0].id, .init(roomId: second, wallId: "wall-5"))
      XCTAssertEqual(model.sharedWallChoices(for: third).count, 10)
      model.removeRoom(second)
      XCTAssertNil(model.rooms[1].walls[0].sharedWith)
      XCTAssertEqual(model.sharedWallChoices(for: third).map(\.title).first, "Room 1 · Wall 1")
    }

    // MARK: The document

    func testTheDocumentRoundTripsAndValidatesAgainstTheSchema() throws {
      let model = model()
      let room = bedroom(model)
      let jpegBytes: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0] + [UInt8](repeating: 0, count: 16)
      model.setImage(SketchImageSelection(data: Data(jpegBytes)), kind: .existingPlan)
      XCTAssertEqual(model.image?.format, .jpeg)
      // A squareness diagonal and the second room of the example, with "about" lengths.
      model.setDiagonal(room, from: 0, to: 2, field("16' 5\"", unit: .ftIn))
      let closet = model.addRoom()
      model.update(closet) { draft in
        draft.label = "Closet"
        draft.type = .closet
        draft.walls[0].length = self.field("4' 11\"", unit: .ftIn)
        draft.walls[1].length = self.field("27.5", unit: .inches, measured: false)
        draft.walls[3].length = self.field("27.5", unit: .inches, measured: false)
      }
      model.setSharedWall(closet, wallId: model.rooms[1].walls[0].id, .init(roomId: room, wallId: "wall-4"))
      model.addOpening(closet, kind: .door, wallId: model.rooms[1].walls[0].id)

      let document = model.measurements
      XCTAssertEqual(
        document.source,
        SketchMeasurements.Source(
          kind: .existingPlan,
          path: "Original Exports/floor-1/a81d5f03-6c2e-4b97-8d14-2f9e7b3c5a60/sketch.jpg"))
      XCTAssertEqual(document.rooms[1].walls[1].length?.measured, false)
      XCTAssertEqual(document.rooms[1].openings[0].width, nil)

      let encoder = CaptureContractJSON.makeEncoder(prettyPrinted: true)
      let data = try encoder.encode(document)
      let decoded = try CaptureContractJSON.makeDecoder().decode(SketchMeasurements.self, from: data)
      XCTAssertEqual(decoded, document)

      let validator = try SchemaValidator(
        schemaURL: Fixtures.schemaURL("sketch-measurements.schema.json"))
      XCTAssertEqual(try validator.validate(jsonData: data), [])

      // Without an image the source has no path, as the schema wants it.
      model.setImage(nil)
      let plain = try encoder.encode(model.measurements)
      XCTAssertEqual(try validator.validate(jsonData: plain), [])
      XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("\"path\""))
    }

    func testFinishFloorWritesTheOriginalsOnce() throws {
      let model = model()
      _ = bedroom(model)
      model.setImage(SketchImageSelection(data: Data("%PDF-1.4 sketch".utf8)))
      XCTAssertEqual(model.image?.format, .pdf)
      XCTAssertEqual(model.sourceKind, .handSketch)
      let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SketchEntryTests-\(UUID().uuidString)", isDirectory: true)
      addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
      let written = try SketchFloorWriter.write(
        measurements: model.measurements, image: model.image, to: directory)
      XCTAssertEqual(written.map(\.fileName), ["sketch.pdf", "sketch-measurements.json"])
      XCTAssertEqual(
        try Data(contentsOf: directory.appendingPathComponent("sketch.pdf")), model.image?.data)
      XCTAssertEqual(
        SketchImageFormat.existingImage(in: directory)?.format, .pdf)
      XCTAssertThrowsError(
        try SketchFloorWriter.write(measurements: model.measurements, image: nil, to: directory))
    }

    // MARK: Fields and units

    func testLengthFieldsFollowTheFieldControlsRules() {
      XCTAssertEqual(field("13' 1.5\"", unit: .ftIn).length?.valueMm, 4000.5)
      XCTAssertEqual(field("13 1.5", unit: .ftIn).length?.valueMm, 4000.5)
      XCTAssertEqual(field("36", unit: .inches).length?.valueMm, 914.4)
      XCTAssertEqual(field("2,69", unit: .m).length?.valueMm, 2690, "a comma is a decimal point")
      XCTAssertNil(field("", unit: .mm).result)
      XCTAssertNil(field("13'", unit: .ftIn).errorMessage, "half typed: no message yet")
      XCTAssertNotNil(field("13'", unit: .ftIn).length, "but 13 feet is a value")
      XCTAssertEqual(field("abc", unit: .mm).errorMessage, "Enter a number such as 2690 or 2.69.")
      XCTAssertEqual(field("7518.4", unit: .mm).storedText, "7,518 mm · 24' 8\"")
      XCTAssertEqual(SketchUnits(display: .imperial), SketchUnits(long: .ftIn, short: .inches))
      XCTAssertEqual(SketchUnits(display: .metric), SketchUnits(long: .mm, short: .mm))

      let model = model()
      let room = model.rooms[0].id
      model.update(room) { $0.walls[0].length = self.field("4 m", unit: .ftIn) }
      model.setDisplayUnits(.metric)
      XCTAssertEqual(model.rooms[0].walls[1].length.unit, .mm, "empty fields take the new unit")
      XCTAssertEqual(model.rooms[0].walls[0].length.unit, .ftIn, "a typed field keeps its unit")
      XCTAssertEqual(model.ceilingHeight.unit, .mm)
      let door = model.addOpening(room, kind: .door, wallId: "wall-1")
      XCTAssertEqual(model.rooms[0].openings[0].width.unit, .mm)
      XCTAssertEqual(door, "door-1")
    }

    func testTheSourceScreenBlocksLikeStepTwoOfAScan() {
      let model = SketchEntryModel(floorLabel: "", existingAreaKeys: ["floor-1"])
      XCTAssertEqual(model.sourceContinueTitle, "Enter the floor or area")
      model.floorLabel = "???"
      XCTAssertEqual(model.sourceBlocker, "Use letters or numbers in the name")
      model.floorLabel = "Floor 1"
      XCTAssertEqual(model.sourceBlocker, "Floor 1 is already captured. Use another name")
      model.floorLabel = "Floor 2"
      XCTAssertEqual(model.sourceBlocker, "Choose what you are drawing")
      model.mode = .room
      XCTAssertNil(model.sourceBlocker)
      XCTAssertEqual(model.areaKey, "floor-2")
      XCTAssertEqual(model.sourceContinueTitle, "Continue")
      model.continueToRooms()
      XCTAssertEqual(model.step, .rooms)
      model.continueToCheck()
      XCTAssertEqual(model.step, .check)
      model.backToRooms()
      model.backToSource()
      XCTAssertEqual(model.step, .source)
    }

    func testImageFormatsAreReadFromTheBytes() {
      let pngBytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47] + [UInt8](repeating: 0, count: 8)
      XCTAssertEqual(SketchImageFormat.detect(Data(pngBytes)), .png)
      var heic = [UInt8](repeating: 0, count: 4) + Array("ftypheic".utf8)
      heic.append(contentsOf: [0, 0, 0, 0])
      XCTAssertEqual(SketchImageFormat.detect(Data(heic)), .heic)
      XCTAssertNil(SketchImageFormat.detect(Data("not an image at all".utf8)))
      XCTAssertEqual(SketchImageFormat(fileExtension: "JPEG"), .jpeg)
      XCTAssertNil(SketchImageFormat(fileExtension: "gif"))
      XCTAssertEqual(SketchImageFormat.pdf.mime, "application/pdf")
    }
  }
#endif

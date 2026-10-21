import CaptureContract
import FieldRules
import Foundation
import XCTest

/// Review of 2026-10-20: a control measured in "Closet" kept that room after the room was
/// renamed "Shower", while the field-controls schema says the room is the capture model's room
/// label, and the station's scale check finds a distance's rooms from the label that starts its
/// From and To. The controls follow the rename.
final class ControlsRoomRenameTests: XCTestCase {
  /// Room Mexico (floor 1: Bedroom, Bathroom, Closet) and a second floor with its own Closet.
  private func controls() throws -> FieldControlsEditor {
    var editor = FieldControlsEditor(visitId: Fixtures.visitId)
    try editor.setDistance(
      capture: Fixtures.floor1, axis: .a, from: "Closet west wall", to: "Bedroom east wall",
      measurement: Fixtures.measurement("4.2", .m))
    try editor.setDistance(
      capture: Fixtures.floor1, axis: .b, from: "  closet   back wall", to: "Bathroom door",
      measurement: Fixtures.measurement("3.1", .m))
    try editor.setCeilingHeight(
      capture: Fixtures.floor1, room: "Closet", measurement: Fixtures.measurement("2400", .mm))
    try editor.setCeilingHeight(
      capture: Fixtures.floor1, room: "CLOSET", location: "Under the beam",
      measurement: Fixtures.measurement("2100", .mm))
    try editor.setCeilingHeight(
      capture: Fixtures.floor1, room: "Bedroom", measurement: Fixtures.measurement("2500", .mm))
    try editor.setOpening(
      capture: Fixtures.floor1, room: "Closet", label: "Door",
      width: Fixtures.measurement("30", .inches))
    try editor.setCeilingHeight(
      capture: Fixtures.floor2, room: "Closet", measurement: Fixtures.measurement("2300", .mm))
    try editor.setDistance(
      capture: Fixtures.floor2, axis: .a, from: "Closet west wall", to: "Hall",
      measurement: Fixtures.measurement("5", .m))
    return editor
  }

  func testControlsOfTheRenamedRoomTakeTheNewName() throws {
    var editor = try controls()
    let before = editor.controls
    XCTAssertTrue(
      editor.renameRooms(
        captureId: Fixtures.floor1Id, labels: ["Bedroom", "Bathroom", "Closet"],
        renames: [(from: "Closet", to: "Shower")]))
    let after = editor.controls

    XCTAssertEqual(after.distances.map(\.from), ["Shower west wall", "Shower back wall", "Closet west wall"])
    XCTAssertEqual(after.distances.map(\.to), ["Bedroom east wall", "Bathroom door", "Hall"])
    XCTAssertEqual(after.ceilingHeights.map(\.room), ["Shower", "Shower", "Bedroom", "Closet"])
    XCTAssertEqual(
      after.ceilingHeights.map(\.id),
      ["floor-1-ceiling-shower", "floor-1-ceiling-shower-under-the-beam", "floor-1-ceiling-bedroom",
       "floor-2-ceiling-closet"],
      "the id a new measurement of the Shower would replace")
    XCTAssertEqual(after.openings.map(\.room), ["Shower"])
    XCTAssertEqual(after.openings.map(\.id), ["floor-1-opening-shower-door"])
    // Measurements, captures and the other lists are as they were.
    XCTAssertEqual(after.distances.map(\.measurement), before.distances.map(\.measurement))
    XCTAssertEqual(after.ceilingHeights.map(\.measurement), before.ceilingHeights.map(\.measurement))
    XCTAssertEqual(after.ceilingHeights.map(\.capture), before.ceilingHeights.map(\.capture))
    XCTAssertEqual(after.floorToFloor, before.floorToFloor)
    XCTAssertEqual(after.landmarks, before.landmarks)
    XCTAssertEqual(FieldControlsValidator.issues(for: after), [])

    // Measuring the Shower's ceiling again replaces the renamed control.
    try editor.setCeilingHeight(
      capture: Fixtures.floor1, room: "Shower", measurement: Fixtures.measurement("2410", .mm))
    XCTAssertEqual(editor.controls.ceilingHeights.count, 4)
    XCTAssertEqual(editor.controls.ceilingHeights.first?.measurement.valueMm, 2410)
  }

  /// The station reads the longest room label that starts the text: renaming "Bedroom" leaves
  /// "Bedroom 2 east wall" to Bedroom 2.
  func testTheLongestRoomLabelDecides() throws {
    var editor = FieldControlsEditor(visitId: Fixtures.visitId)
    try editor.setDistance(
      capture: Fixtures.floor1, axis: .a, from: "Bedroom 2 east wall", to: "Bedroom",
      measurement: Fixtures.measurement("4", .m))
    try editor.setDistance(
      capture: Fixtures.floor1, axis: .b, from: "Bedrooms wing", to: "Bedroom north wall",
      measurement: Fixtures.measurement("3", .m))
    editor.renameRooms(
      captureId: Fixtures.floor1Id, labels: ["Bedroom", "Bedroom 2"], renames: [(from: "Bedroom", to: "Primary")])
    XCTAssertEqual(editor.controls.distances.map(\.from), ["Bedroom 2 east wall", "Bedrooms wing"])
    XCTAssertEqual(editor.controls.distances.map(\.to), ["Primary", "Primary north wall"])
  }

  func testTwoRoomsCanSwapNamesAndIdsStayUnique() throws {
    var editor = FieldControlsEditor(visitId: Fixtures.visitId)
    try editor.setCeilingHeight(
      capture: Fixtures.floor1, room: "Bathroom", measurement: Fixtures.measurement("2400", .mm))
    try editor.setCeilingHeight(
      capture: Fixtures.floor1, room: "Closet", measurement: Fixtures.measurement("2200", .mm))
    editor.renameRooms(
      captureId: Fixtures.floor1Id, labels: ["Bathroom", "Closet"],
      renames: [(from: "Bathroom", to: "Closet"), (from: "Closet", to: "Bathroom")])
    XCTAssertEqual(editor.controls.ceilingHeights.map(\.room), ["Closet", "Bathroom"])
    XCTAssertEqual(editor.controls.ceilingHeights.map(\.measurement.valueMm), [2400, 2200])
    XCTAssertEqual(Set(editor.controls.ceilingHeights.map(\.id)).count, 2)
    XCTAssertEqual(FieldControlsValidator.issues(for: editor.controls), [])
  }

  func testNothingChangesWithoutAMatchOrWhenTheTextWouldBeTooLong() throws {
    var editor = try controls()
    let before = editor.controls
    XCTAssertFalse(
      editor.renameRooms(captureId: Fixtures.floor1Id, labels: ["Laundry"], renames: [(from: "Laundry", to: "Utility")]))
    XCTAssertFalse(editor.renameRooms(captureId: Fixtures.floor1Id, labels: ["Closet"], renames: []))
    XCTAssertEqual(editor.controls, before)

    var long = FieldControlsEditor(visitId: Fixtures.visitId)
    let wall = " " + String(repeating: "w", count: 190)
    try long.setDistance(
      capture: Fixtures.floor1, axis: .a, from: "Closet" + wall, to: "Bedroom",
      measurement: Fixtures.measurement("4", .m))
    long.renameRooms(
      captureId: Fixtures.floor1Id, labels: ["Closet", "Bedroom"],
      renames: [(from: "Closet", to: "Walk-in shower"), (from: "Bedroom", to: "Guest room")])
    XCTAssertEqual(long.controls.distances.map(\.from), ["Closet" + wall], "would pass 200 characters")
    XCTAssertEqual(long.controls.distances.map(\.to), ["Guest room"])
    XCTAssertEqual(FieldControlsValidator.issues(for: long.controls), [])
  }

  func testLabelsAreComparedAsTheStationComparesThem() {
    XCTAssertEqual(FieldControlsEditor.labelKey("  Walk-in\u{00A0} SHOWER  "), "walk-in shower")
    XCTAssertEqual(FieldControlsEditor.labelKey("\u{FB01}tting room"), "fitting room", "NFKC")
  }
}

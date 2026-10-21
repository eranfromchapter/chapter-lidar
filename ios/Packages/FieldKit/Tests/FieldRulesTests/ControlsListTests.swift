import CaptureContract
import FieldRules
import Foundation
import XCTest

/// AC3 (phone-field §4): Field controls rows, values, statuses and the "N of M required" counter
/// match the artboard scenario (2d-2) in both policies.
final class ControlsListTests: XCTestCase {
  private let f1 = Fixtures.floor1
  private let f2 = Fixtures.floor2

  private func floor(
    _ ref: FieldControls.CaptureRef, _ label: String, at time: UTCTimestamp,
    mode: CaptureMode = .floor, rooms: [String] = [], scan: ScanMeasurements? = nil
  ) -> ControlsFloor {
    ControlsFloor(ref: ref, label: label, mode: mode, capturedAt: time, rooms: rooms, scan: scan)
  }

  private var twoFloors: [ControlsFloor] {
    [
      floor(f1, "Floor 1", at: Fixtures.t0, rooms: ["Kitchen", "Living", "Bath 1", "Bedroom 1"]),
      floor(f2, "Floor 2", at: Fixtures.t1),
    ]
  }

  /// The artboard: Floor 1 A 7,520 / B 11,240 / 3 ceiling heights 2,690–2,740 / 2 openings; one
  /// shared landmark; nothing on Floor 2.
  private func artboardControls() throws -> FieldControls {
    var editor = FieldControlsEditor(visitId: Fixtures.visitId)
    try editor.setDistance(
      capture: f1, axis: .a, from: "Kitchen east wall", to: "living west wall",
      measurement: Fixtures.measurement("7520", .mm))
    try editor.setDistance(
      capture: f1, axis: .b, from: "Entry", to: "rear wall",
      measurement: Fixtures.measurement("11240", .mm))
    for (room, height) in [("Kitchen", "2690"), ("Living", "2740"), ("Bath 1", "2700")] {
      try editor.setCeilingHeight(
        capture: f1, room: room, measurement: Fixtures.measurement(height, .mm))
    }
    try editor.setOpening(
      capture: f1, room: "Kitchen", label: "Entry door",
      width: Fixtures.measurement("36", .inches))
    try editor.setOpening(
      capture: f1, room: "Living", label: "Patio door",
      width: Fixtures.measurement("72", .inches))
    try editor.setLandmark(label: "Stair newel post", captures: [f1, f2])
    return editor.controls
  }

  /// Compact text of a row for whole-list comparisons.
  private func describe(_ row: ControlRow) -> String {
    let glyph = ["done": "●", "missing": "■", "optional": "○"][row.status.rawValue]!
    let values = [row.valuePrimary, row.valueSecondary, row.extraLine].compactMap { $0 }
    return ([glyph, row.title, row.subtitle ?? "-"] + values).joined(separator: " | ")
      + (row.isCompact ? " (compact)" : "")
  }

  // MARK: Manual policy (as drawn)

  func testTheArtboardScenarioUnderTheManualPolicy() throws {
    let sections = ControlsList.sections(
      floors: twoFloors, controls: try artboardControls(), policy: .manualControls)
    XCTAssertEqual(
      sections.map(\.header),
      ["Floor 1 \u{00B7} minimum set", "Between Floor 1 and Floor 2", "Floor 2 \u{00B7} minimum set"])
    XCTAssertEqual(sections.map(\.id), ["floor-1", "floor-1~floor-2", "floor-2"])
    XCTAssertEqual(
      sections.map { $0.rows.map(describe) },
      [
        [
          "● | Long distance A | Kitchen east wall to living west wall | 7,520 mm | 24' 8.1\"",
          "● | Long distance B \u{00B7} at a right angle to A | Entry to rear wall | 11,240 mm | 36' 10.5\"",
          "● | Ceiling height | 3 rooms \u{00B7} at least 1 required | 2,690\u{2013}2,740 mm",
          "● | Openings \u{00B7} optional | - | 2 recorded (compact)",
        ],
        [
          "■ | Floor to floor | Level difference, measured at the stair | Missing",
          "■ | Shared landmarks | Visible from both floors \u{00B7} 2 required | 1 of 2",
        ],
        [
          "■ | Long distance A | - | Missing (compact)",
          "■ | Long distance B | - | Missing (compact)",
          "■ | Ceiling height | - | Missing (compact)",
          "○ | Openings \u{00B7} optional | - | None (compact)",
        ],
      ])
    XCTAssertEqual(
      sections[1].rows.map(\.valueTone), [.blocked, .blocked], "Missing and 1 of 2 are red")
    XCTAssertEqual(sections[2].rows.last?.valueTone, .muted)
    XCTAssertEqual(
      ControlsList.progress(floors: twoFloors, controls: try artboardControls(), policy: .manualControls)
        .text,
      "4 of 9 required")
  }

  func testRowIdentifiersAndAccessibility() throws {
    let sections = ControlsList.sections(
      floors: twoFloors, controls: try artboardControls(), policy: .manualControls)
    XCTAssertEqual(
      sections.flatMap(\.rows).map(\.accessibilityIdentifier),
      [
        "controls.row.floor-1.distanceA", "controls.row.floor-1.distanceB",
        "controls.row.floor-1.ceilingHeight", "controls.row.floor-1.openings",
        "controls.row.floor-1~floor-2.floorToFloor", "controls.row.floor-1~floor-2.landmarks",
        "controls.row.floor-2.distanceA", "controls.row.floor-2.distanceB",
        "controls.row.floor-2.ceilingHeight", "controls.row.floor-2.openings",
      ])
    XCTAssertEqual(
      sections[0].rows[0].accessibilityLabel,
      "Long distance A, Kitchen east wall to living west wall, 7,520 millimetres, "
        + "24 feet 8.1 inches, Done")
    XCTAssertEqual(
      sections[0].rows[2].accessibilityLabel,
      "Ceiling height, 3 rooms \u{00B7} at least 1 required, 2,690 to 2,740 millimetres, Done")
    XCTAssertEqual(sections[2].rows[0].accessibilityLabel, "Long distance A, Missing")
    XCTAssertEqual(sections[1].rows[1].accessibilityLabel,
      "Shared landmarks, Visible from both floors \u{00B7} 2 required, 1 of 2, Missing")
  }

  func testOneCeilingHeightShowsBothUnitsAndOneRoom() throws {
    var editor = FieldControlsEditor(visitId: Fixtures.visitId)
    try editor.setCeilingHeight(
      capture: f1, room: "Kitchen", measurement: Fixtures.measurement("2690", .mm))
    try editor.setCeilingHeight(
      capture: f1, room: "kitchen", location: "By the window",
      measurement: Fixtures.measurement("2690.2", .mm))
    let row = ControlsList.sections(
      floors: [twoFloors[0]], controls: editor.controls, policy: .manualControls)[0].rows[2]
    XCTAssertEqual(row.subtitle, "1 room \u{00B7} at least 1 required")
    XCTAssertEqual(row.valuePrimary, "2,690 mm")
    XCTAssertEqual(row.valueSecondary, "8' 9.9\"")
  }

  func testOneFloorHasNoBetweenSectionAndCountsThree() throws {
    var editor = FieldControlsEditor(controls: try artboardControls())
    editor.remove(id: "landmark-stair-newel-post")
    let floors = [twoFloors[0]]
    let sections = ControlsList.sections(
      floors: floors, controls: editor.controls, policy: .manualControls)
    XCTAssertEqual(sections.map(\.id), ["floor-1"])
    let progress = ControlsList.progress(
      floors: floors, controls: editor.controls, policy: .manualControls)
    XCTAssertEqual(progress.text, "3 of 3 required")
    XCTAssertTrue(progress.isComplete)
  }

  func testThreeFloorsInterleaveTheirBetweenSectionsByCaptureTime() {
    let f3 = FieldControls.CaptureRef(captureId: LowercaseUUID(), areaKey: "floor-3")
    let later = UTCTimestamp(rawValue: "2026-10-17T16:00:00Z")!
    // Given out of order: sorted by capture time.
    let floors = [
      floor(f3, "Floor 3", at: later), floor(f1, "Floor 1", at: Fixtures.t0),
      floor(f2, "Floor 2", at: Fixtures.t1),
    ]
    let sections = ControlsList.sections(
      floors: floors, controls: FieldControls(visitId: Fixtures.visitId), policy: .manualControls)
    XCTAssertEqual(
      sections.map(\.header),
      [
        "Floor 1 \u{00B7} minimum set", "Between Floor 1 and Floor 2",
        "Floor 2 \u{00B7} minimum set", "Between Floor 2 and Floor 3",
        "Floor 3 \u{00B7} minimum set",
      ])
    XCTAssertEqual(
      ControlsList.progress(
        floors: floors, controls: FieldControls(visitId: Fixtures.visitId), policy: .manualControls
      ).text, "0 of 15 required")
  }

  func testExteriorCapturesAreLeftOut() throws {
    let exterior = FieldControls.CaptureRef(captureId: LowercaseUUID(), areaKey: "exterior")
    var floors = twoFloors
    floors.insert(floor(exterior, "Exterior", at: Fixtures.t0, mode: .exterior), at: 1)
    let sections = ControlsList.sections(
      floors: floors, controls: try artboardControls(), policy: .manualControls)
    XCTAssertEqual(sections.map(\.id), ["floor-1", "floor-1~floor-2", "floor-2"])
    XCTAssertEqual(
      ControlsList.emptyMessage([floor(exterior, "Exterior", at: Fixtures.t0, mode: .exterior)]),
      "Exterior captures need no field controls.")
    XCTAssertEqual(ControlsList.emptyMessage([]), "No floor or area has been scanned yet.")
    XCTAssertNil(ControlsList.emptyMessage(floors))
  }

  func testLandmarksAndFloorToFloorWhenRecorded() throws {
    var editor = FieldControlsEditor(controls: try artboardControls())
    try editor.setLandmark(label: "Chimney chase", captures: [f1, f2])
    try editor.setFloorToFloor(
      lower: f1, upper: f2, location: "At the stair, Floor 1 landing to Floor 2 landing",
      measurement: Fixtures.measurement("10' 0.5\"", .ftIn))
    let between = ControlsList.sections(
      floors: twoFloors, controls: editor.controls, policy: .manualControls)[1].rows
    XCTAssertEqual(
      between.map(describe),
      [
        "● | Floor to floor | At the stair, Floor 1 landing to Floor 2 landing | 3,061 mm | 10' 0.5\"",
        "● | Shared landmarks | Visible from both floors \u{00B7} 2 required | 2 recorded",
      ])
    XCTAssertEqual(
      ControlsList.progress(floors: twoFloors, controls: editor.controls, policy: .manualControls)
        .text, "6 of 9 required")
  }

  // MARK: Standard policy (shipping)

  private var scan: ScanMeasurements {
    ScanMeasurements(
      distanceAMm: 7512, distanceBMm: 11236,
      ceilingHeights: [
        .init(room: "Kitchen", heightMm: 2700), .init(room: "Living", heightMm: 2745),
      ], doors: 3, windows: 4, openings: 1)
  }

  func testStandardPolicyNeverShowsMissing() throws {
    let floors = [
      floor(f1, "Floor 1", at: Fixtures.t0, scan: scan), floor(f2, "Floor 2", at: Fixtures.t1),
    ]
    let sections = ControlsList.sections(
      floors: floors, controls: try artboardControls(), policy: .standard)
    XCTAssertFalse(sections.flatMap(\.rows).contains { $0.status == .missing })
    XCTAssertEqual(
      sections.map { $0.rows.map(describe) },
      [
        [
          "● | Long distance A | Kitchen east wall to living west wall | 7,520 mm | 24' 8.1\" | Scan 7,512 mm",
          "● | Long distance B \u{00B7} at a right angle to A | Entry to rear wall | 11,240 mm | 36' 10.5\" | Scan 11,236 mm",
          "● | Ceiling height | 3 rooms | 2,690\u{2013}2,740 mm | Scan 2,700\u{2013}2,745 mm",
          "● | Openings \u{00B7} optional | - | 2 recorded (compact)",
        ],
        [
          "○ | Floor to floor | Level difference, measured at the stair | Optional",
          "● | Shared landmarks | Visible from both floors | 1 recorded",
        ],
        [
          "○ | Long distance A | - | Optional (compact)",
          "○ | Long distance B | - | Optional (compact)",
          "○ | Ceiling height | - | Optional (compact)",
          "○ | Openings \u{00B7} optional | - | None (compact)",
        ],
      ])
  }

  func testStandardPolicyShowsTheScanValuesWithoutTape() {
    let floors = [floor(f1, "Floor 1", at: Fixtures.t0, scan: scan)]
    let rows = ControlsList.sections(
      floors: floors, controls: FieldControls(visitId: Fixtures.visitId), policy: .standard)[0]
      .rows
    XCTAssertEqual(
      rows.map(describe),
      [
        "● | Long distance A | From the LiDAR scan \u{00B7} tap to check with tape | 7,512 mm | 24' 7.7\"",
        "● | Long distance B \u{00B7} at a right angle to A | From the LiDAR scan \u{00B7} tap to check with tape | 11,236 mm | 36' 10.4\"",
        "● | Ceiling height | From the LiDAR scan \u{00B7} 2 rooms | 2,700\u{2013}2,745 mm",
        "● | Openings \u{00B7} optional | - | 8 from the scan (compact)",
      ])
    XCTAssertEqual(rows.map(\.valueTone), [.ink, .ink, .ink, .ink])
  }

  // MARK: Overview word and Before you leave's Add

  func testFloorStateForTheOverview() throws {
    let manual = ControlsList.sections(
      floors: twoFloors, controls: try artboardControls(), policy: .manualControls)
    XCTAssertEqual(ControlsList.floorState(manual[0], policy: .manualControls), .complete)
    XCTAssertEqual(ControlsList.floorState(manual[2], policy: .manualControls), .missing)
    XCTAssertEqual(FloorControlsState.missing.text, "controls missing")

    var editor = FieldControlsEditor(controls: try artboardControls())
    editor.remove(id: "floor-1-distance-b")
    let partly = ControlsList.sections(
      floors: twoFloors, controls: editor.controls, policy: .manualControls)
    XCTAssertEqual(ControlsList.floorState(partly[0], policy: .manualControls), .incomplete)

    let floors = [
      floor(f1, "Floor 1", at: Fixtures.t0, scan: scan), floor(f2, "Floor 2", at: Fixtures.t1),
    ]
    let standard = ControlsList.sections(
      floors: floors, controls: FieldControls(visitId: Fixtures.visitId), policy: .standard)
    XCTAssertEqual(ControlsList.floorState(standard[0], policy: .standard), .fromScan)
    XCTAssertEqual(ControlsList.floorState(standard[2], policy: .standard), .optional)
    XCTAssertEqual(FloorControlsState.fromScan.text, "controls from the scan")
  }

  func testEveryGapMapsToItsRow() {
    let floors = twoFloors
    XCTAssertEqual(
      ControlsList.rowId(for: .missingDistance(capture: "Floor 2", axis: .b), floors: floors),
      "floor-2.distanceB")
    XCTAssertEqual(
      ControlsList.rowId(for: .missingCeilingHeight(capture: "Floor 1"), floors: floors),
      "floor-1.ceilingHeight")
    XCTAssertEqual(
      ControlsList.rowId(
        for: .missingFloorToFloor(lower: "Floor 1", upper: "Floor 2"), floors: floors),
      "floor-1~floor-2.floorToFloor")
    XCTAssertEqual(
      ControlsList.rowId(
        for: .missingLandmarks(lower: "Floor 1", upper: "Floor 2", have: 1, need: 2),
        floors: floors),
      "floor-1~floor-2.landmarks")
    XCTAssertNil(ControlsList.rowId(for: .skippedRoomsNotRecorded, floors: floors))
    XCTAssertNil(
      ControlsList.rowId(for: .missingCeilingHeight(capture: "Basement"), floors: floors))
  }

  func testGapsComeInListOrder() throws {
    let gaps = ControlsList.gaps(
      floors: twoFloors, controls: try artboardControls(), policy: .manualControls)
    XCTAssertEqual(
      gaps,
      [
        .missingFloorToFloor(lower: "Floor 1", upper: "Floor 2"),
        .missingLandmarks(lower: "Floor 1", upper: "Floor 2", have: 1, need: 2),
        .missingDistance(capture: "Floor 2", axis: .a),
        .missingDistance(capture: "Floor 2", axis: .b),
        .missingCeilingHeight(capture: "Floor 2"),
      ])
  }

  func testARenamedRoomFlowsIntoTheCeilingRow() throws {
    var editor = FieldControlsEditor(visitId: Fixtures.visitId)
    try editor.setCeilingHeight(
      capture: f1, room: "Closet", measurement: Fixtures.measurement("2400", .mm))
    try editor.setCeilingHeight(
      capture: f1, room: "Kitchen", measurement: Fixtures.measurement("2690", .mm))
    // Closet → Kitchen: both heights are now in one room.
    editor.renameRooms(
      captureId: f1.captureId, labels: ["Closet", "Kitchen"],
      renames: [(from: "Closet", to: "Kitchen")])
    let row = ControlsList.sections(
      floors: [twoFloors[0]], controls: editor.controls, policy: .manualControls)[0].rows[2]
    XCTAssertEqual(row.subtitle, "1 room \u{00B7} at least 1 required")
    XCTAssertEqual(row.valuePrimary, "2,400\u{2013}2,690 mm")
  }
}

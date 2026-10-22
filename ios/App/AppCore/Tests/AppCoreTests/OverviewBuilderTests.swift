import CaptureContract
import CaptureCore
import FieldRules
import Foundation
import XCTest

@testable import AppCore

/// The Capture overview (phone-capture §10.1 T-O1, critique R-21, R-25, R-37, R-38, G-2).
///
/// The drawn 618 Valley Street state (artboard 2b-4) cannot hold together under the checklist's
/// own rules: Floor 2 "no photos yet" with 9 rooms makes nine room gaps, so the Photos row
/// cannot read "Bath 2 has no photo" at the same time. The fixture below keeps every other drawn
/// string; the one-gap wording is tested on its own (`testPhotosRowWording`).
final class OverviewBuilderTests: XCTestCase {
  private let utc = TimeZone(identifier: "UTC")!
  private let now = UTCTimestamp(rawValue: "2026-05-16T15:00:00Z")!.date

  private let floor1Rooms = [
    "Kitchen", "Living", "Bath 1", "Bedroom 1", "Bedroom 2", "Bath 2", "Hall", "Dining",
    "Laundry", "Office", "Pantry", "Foyer",
  ]
  private let floor2Rooms = [
    "Bedroom 3", "Bedroom 4", "Bath 3", "Hall 2", "Closet", "Study", "Den", "Loft", "Storage",
  ]

  private func measurement(_ mm: Double) -> FieldControls.Measurement {
    .init(
      valueMm: mm, enteredUnit: .mm, enteredText: "\(Int(mm))", method: .tape,
      recordedAt: Make.t1402)
  }

  private func photo(_ capture: CaptureRecord.Capture, _ room: String, _ sequence: Int)
    -> PhotoRecord
  {
    PhotoRecord(
      captureId: capture.captureId, areaKey: capture.areaKey, sequence: sequence,
      path: "Site Photos/\(capture.areaKey)/\(capture.captureId.rawValue)/photo-\(sequence).jpg",
      format: .jpeg, sha256: String(repeating: "0", count: 64), bytes: 10,
      labels: .init(room: room, direction: .north, subject: .general, takenAt: Make.t1402))
  }

  /// The drawn visit: two whole floors, Floor 1 verified, controls complete on Floor 1 only,
  /// one landmark of two, "Primary closet · locked" recorded.
  private struct Visit {
    var record: CaptureRecord
    var photos: [PhotoRecord]
    var controls: FieldControls
  }

  private func valleyStreet() throws -> Visit {
    var floor1 = Make.capture("Floor 1", compass: Make.reading())
    floor1.omittedRooms = [CaptureRecord.RoomNote(name: "Primary closet", reason: "locked")]
    let floor2 = Make.capture("Floor 2")
    let record = Make.record([floor1, floor2])
    var photos: [PhotoRecord] = []
    for index in 0..<42 {
      photos.append(photo(floor1, floor1Rooms[index % floor1Rooms.count], index + 1))
    }
    var editor = FieldControlsEditor(visitId: record.visitId)
    let ref1 = FieldControls.CaptureRef(captureId: floor1.captureId, areaKey: floor1.areaKey)
    let ref2 = FieldControls.CaptureRef(captureId: floor2.captureId, areaKey: floor2.areaKey)
    try editor.setDistance(capture: ref1, axis: .a, from: "a", to: "b", measurement: measurement(7520))
    try editor.setDistance(capture: ref1, axis: .b, from: "c", to: "d", measurement: measurement(11240))
    try editor.setCeilingHeight(capture: ref1, room: "Kitchen", measurement: measurement(2690))
    try editor.setLandmark(label: "Stair newel", captures: [ref1, ref2])
    return Visit(record: record, photos: photos, controls: editor.controls)
  }

  private func input(
    _ visit: Visit, policy: ChecklistPolicy = .manualControls, flow: VisitFlow? = nil,
    scans: [LowercaseUUID: OverviewBuilder.FloorScan]? = nil, hasVerdict: Bool = false
  ) -> OverviewBuilder.Input {
    let rooms = [
      visit.record.captures[0].captureId: floor1Rooms,
      visit.record.captures.count > 1 ? visit.record.captures[1].captureId : LowercaseUUID():
        floor2Rooms,
    ]
    let checklist = ChecklistRules.evaluate(
      ChecklistInput(
        record: visit.record, capturedRooms: rooms, photos: visit.photos,
        controls: visit.controls), policy: policy)
    var mapped: [LowercaseUUID: OverviewBuilder.FloorScan] = [:]
    for capture in visit.record.captures { mapped[capture.captureId] = .mapped(nil) }
    return OverviewBuilder.Input(
      record: visit.record, rooms: rooms, scans: scans ?? mapped, photos: visit.photos,
      controls: visit.controls, checklist: checklist, policy: policy,
      flow: flow ?? VisitFlow(resuming: visit.record, isSealed: false),
      newestPackageHasVerdict: hasVerdict, now: now, timeZone: utc)
  }

  // MARK: T-O1

  func testTheDrawnState() throws {
    let state = OverviewBuilder.make(input(try valleyStreet()))
    XCTAssertEqual(state.title, "618 Valley Street")
    XCTAssertEqual(state.dealCaption, "Deal 4821")
    XCTAssertEqual(state.subtitle, "Captured today by Dana Ruiz · not sealed yet")
    XCTAssertTrue(state.canAddFloor)

    XCTAssertEqual(state.floors.map(\.id), ["floor-1", "floor-2"])
    XCTAssertEqual(state.floors[0].title, "Floor 1")
    XCTAssertEqual(
      state.floors[0].subtitle, "Whole floor · 12 rooms · 42 photos · controls complete")
    XCTAssertEqual(state.floors[0].status, RowStatusValue(.done, "Done"))
    XCTAssertEqual(
      state.floors[1].subtitle, "Whole floor · 9 rooms · no photos yet · controls missing")
    XCTAssertEqual(state.floors[1].status, RowStatusValue(.missing, "Open"))

    let checks = Dictionary(uniqueKeysWithValues: state.checks.map { ($0.id, $0) })
    XCTAssertEqual(state.checks.map(\.id), [.photos, .controls, .compass, .skippedRooms])
    XCTAssertEqual(checks[.photos]?.subtitle, "Bedroom 3 and 8 more rooms have no photo")
    XCTAssertEqual(checks[.photos]?.status, RowStatusValue(.missing, "Missing"))
    XCTAssertEqual(checks[.controls]?.subtitle, "Floor to floor and 1 landmark missing")
    XCTAssertEqual(checks[.controls]?.status, RowStatusValue(.missing, "Missing"))
    XCTAssertEqual(checks[.compass]?.subtitle, "Floor 1 verified · Floor 2 not read")
    XCTAssertEqual(checks[.compass]?.status, RowStatusValue(.partly, "Partly"))
    XCTAssertEqual(checks[.skippedRooms]?.subtitle, "Primary closet · locked")
    XCTAssertEqual(checks[.skippedRooms]?.status, RowStatusValue(.done, "Recorded"))

    XCTAssertEqual(state.button, .fix(items: 2), "photos and controls; the compass never counts")
    XCTAssertEqual(state.button.title, "Fix 2 items to review the package")
    XCTAssertFalse(state.button.isEnabled)
  }

  func testPhotosRowWording() {
    XCTAssertEqual(
      OverviewBuilder.photoGapText([.roomWithoutPhoto(capture: "Floor 1", room: "Bath 2")]),
      "Bath 2 has no photo")
    XCTAssertEqual(
      OverviewBuilder.photoGapText([.captureWithoutPhoto(capture: "Floor 2")]),
      "Floor 2 has no photo")
    XCTAssertEqual(
      OverviewBuilder.photoGapText([
        .roomWithoutPhoto(capture: "Floor 1", room: "Bath 2"),
        .roomWithoutPhoto(capture: "Floor 1", room: "Hall"),
      ]), "Bath 2 and 1 more room have no photo")
    XCTAssertEqual(
      OverviewBuilder.photoGapText([
        .captureWithoutPhoto(capture: "Floor 2"),
        .roomWithoutPhoto(capture: "Floor 1", room: "Hall"),
      ]), "Floor 2 and 1 more have no photo")
  }

  func testOnePhotoGapAndItsTarget() throws {
    var visit = try valleyStreet()
    visit.record.captures.removeLast()
    visit.photos.removeAll { $0.room == "Bath 2" }
    let input = input(visit)
    let state = OverviewBuilder.make(input)
    XCTAssertEqual(state.checks[0].subtitle, "Bath 2 has no photo")
    XCTAssertEqual(state.floors[0].status, RowStatusValue(.missing, "Open"), "a photo gap opens it")
    let target = try XCTUnwrap(
      OverviewBuilder.photoTarget(record: visit.record, checklist: input.checklist))
    XCTAssertEqual(target.captureId, visit.record.captures[0].captureId)
    XCTAssertEqual(target.room, "Bath 2")
  }

  func testPhotoTargetWithoutGapsIsTheLastCapture() throws {
    let visit = try valleyStreet()
    let checklist = ChecklistReport(items: [
      ChecklistItem(id: .photoPerRoom, passed: true, detail: "", gaps: [])
    ])
    let target = try XCTUnwrap(
      OverviewBuilder.photoTarget(record: visit.record, checklist: checklist))
    XCTAssertEqual(target.captureId, visit.record.captures[1].captureId)
    XCTAssertNil(target.room)
  }

  func testAllPassingLeadsToReviewThePackage() throws {
    var visit = try valleyStreet()
    let floor2 = visit.record.captures[1]
    for (index, room) in floor2Rooms.enumerated() {
      visit.photos.append(photo(floor2, room, index + 1))
    }
    var editor = FieldControlsEditor(controls: visit.controls)
    let ref1 = FieldControls.CaptureRef(
      captureId: visit.record.captures[0].captureId, areaKey: "floor-1")
    let ref2 = FieldControls.CaptureRef(captureId: floor2.captureId, areaKey: "floor-2")
    try editor.setDistance(capture: ref2, axis: .a, from: "a", to: "b", measurement: measurement(5000))
    try editor.setDistance(capture: ref2, axis: .b, from: "a", to: "b", measurement: measurement(6000))
    try editor.setCeilingHeight(capture: ref2, room: "Den", measurement: measurement(2400))
    try editor.setFloorToFloor(lower: ref1, upper: ref2, location: "Stair", measurement: measurement(3061))
    try editor.setLandmark(label: "Chimney", captures: [ref1, ref2])
    visit.controls = editor.controls
    visit.record.captures[1].setCompass(Make.reading())

    let state = OverviewBuilder.make(input(visit))
    XCTAssertEqual(state.checks.map(\.status.word), ["Done", "Done", "Verified", "Recorded"])
    XCTAssertEqual(state.checks[0].subtitle, "Every room has a photo")
    XCTAssertEqual(state.checks[1].subtitle, "Minimum set complete")
    XCTAssertEqual(state.checks[2].subtitle, "Every floor verified")
    XCTAssertEqual(state.floors.map(\.status), [RowStatusValue(.done, "Done"), RowStatusValue(.done, "Done")])
    XCTAssertEqual(state.button, .reviewPackage)
    XCTAssertTrue(state.button.isEnabled)
  }

  // MARK: Field controls (R-37, G-2)

  func testControlsSubtitleJoinRules() {
    XCTAssertEqual(
      OverviewBuilder.controlsGapText(
        [.missingFloorToFloor(lower: "Floor 1", upper: "Floor 2")], floorCount: 2),
      "Floor to floor missing")
    XCTAssertEqual(
      OverviewBuilder.controlsGapText(
        [.missingLandmarks(lower: "Floor 1", upper: "Floor 2", have: 0, need: 2)], floorCount: 2),
      "2 landmarks missing")
    // Per-floor gaps only.
    XCTAssertEqual(
      OverviewBuilder.controlsGapText(
        [.missingDistance(capture: "Floor 2", axis: .a), .missingCeilingHeight(capture: "Floor 2")],
        floorCount: 2), "Missing on Floor 2")
    XCTAssertEqual(
      OverviewBuilder.controlsGapText(
        [.missingCeilingHeight(capture: "Floor 1"), .missingCeilingHeight(capture: "Floor 2")],
        floorCount: 2), "Missing on Floor 1 and Floor 2")
    XCTAssertEqual(
      OverviewBuilder.controlsGapText(
        [
          .missingCeilingHeight(capture: "Floor 1"), .missingCeilingHeight(capture: "Floor 2"),
          .missingCeilingHeight(capture: "Floor 3"),
        ], floorCount: 3), "Missing on Floor 1, Floor 2 and Floor 3")
    // Between-floor gaps win over per-floor ones; three floors name the pair.
    XCTAssertEqual(
      OverviewBuilder.controlsGapText(
        [
          .missingCeilingHeight(capture: "Floor 1"),
          .missingFloorToFloor(lower: "Floor 1", upper: "Floor 2"),
          .missingLandmarks(lower: "Floor 1", upper: "Floor 2", have: 1, need: 2),
          .missingFloorToFloor(lower: "Floor 2", upper: "Floor 3"),
        ], floorCount: 3),
      "Floor to floor between Floor 1 and Floor 2, 1 landmark between Floor 1 and Floor 2 and "
        + "Floor to floor between Floor 2 and Floor 3 missing")
    XCTAssertEqual(OverviewBuilder.join(["A", "B", "C", "D"], limit: 3), "A, B and 2 more")
    XCTAssertEqual(OverviewBuilder.join(["A", "B", "C"], limit: 3), "A, B and C")
  }

  func testStandardPolicyWordsTheControlsFromTheScan() throws {
    let visit = try valleyStreet()
    let scan = ScanMeasurements(
      distanceAMm: 7000, distanceBMm: 9000, ceilingHeights: [.init(room: "Kitchen", heightMm: 2600)],
      doors: 1, windows: 1, openings: 0)
    let scans: [LowercaseUUID: OverviewBuilder.FloorScan] = [
      visit.record.captures[0].captureId: .mapped(scan),
      visit.record.captures[1].captureId: .mapped(nil),
    ]
    let state = OverviewBuilder.make(input(visit, policy: .standard, scans: scans))
    XCTAssertEqual(state.floors[0].subtitle, "Whole floor · 12 rooms · 42 photos · controls from the scan")
    XCTAssertEqual(state.floors[1].subtitle, "Whole floor · 9 rooms · no photos yet · controls optional")
    // The standard policy never blocks on controls; the row says what Before you leave says.
    XCTAssertEqual(state.checks[1].status, RowStatusValue(.done, "Done"))
    XCTAssertTrue(state.checks[1].subtitle.hasPrefix("Measured by the LiDAR scan"))
    XCTAssertEqual(state.button, .fix(items: 1), "only the photos block")
  }

  // MARK: Compass (R-21)

  func testCompassWords() throws {
    var visit = try valleyStreet()
    func compassRow() -> CaptureOverviewState.CheckRow {
      OverviewBuilder.make(input(visit)).checks[2]
    }
    visit.record.captures[1].setCompass(Make.reading(accuracy: 20))
    XCTAssertEqual(compassRow().status, RowStatusValue(.partly, "Approx."))
    XCTAssertEqual(compassRow().subtitle, "Floor 1 verified · Floor 2 approximate")
    visit.record.captures[1].setCompass(Make.reading(accuracy: 40))
    XCTAssertEqual(compassRow().status, RowStatusValue(.partly, "Partly"))
    XCTAssertEqual(compassRow().subtitle, "Floor 1 verified · Floor 2 not verified")
    visit.record.captures[0].setCompass(.none(issue: .notCalibrated))
    XCTAssertEqual(compassRow().status, RowStatusValue(.partly, "Not verified"))
    XCTAssertEqual(compassRow().subtitle, "Floor 1 not read · Floor 2 not verified")
    XCTAssertNotEqual(compassRow().status.kind, .missing, "never ■")
  }

  // MARK: Rooms not scanned (R-38)

  func testSkippedRoomsRow() throws {
    var visit = try valleyStreet()
    visit.record.captures[0].omittedRooms = []
    var state = OverviewBuilder.make(input(visit))
    XCTAssertEqual(state.checks[3].subtitle, "Record skipped rooms, or confirm none were skipped")
    XCTAssertEqual(state.checks[3].status, RowStatusValue(.missing, "Missing"))
    XCTAssertEqual(state.button, .fix(items: 3))

    var confirmation = NoRoomsSkippedConfirmation()
    confirmation.confirm(for: visit.record)
    let flow = VisitFlow(resuming: visit.record, noRoomsSkipped: confirmation, isSealed: false)
    let rooms = [
      visit.record.captures[0].captureId: floor1Rooms, visit.record.captures[1].captureId: floor2Rooms,
    ]
    let checklist = ChecklistRules.evaluate(
      ChecklistInput(
        record: visit.record, capturedRooms: rooms, photos: visit.photos, controls: visit.controls,
        noRoomsSkippedConfirmed: flow.noRoomsSkippedConfirmed), policy: .manualControls)
    var confirmed = input(visit, flow: flow)
    confirmed.checklist = checklist
    state = OverviewBuilder.make(confirmed)
    XCTAssertEqual(state.checks[3].subtitle, "All rooms scanned", "not \"No rooms skipped\"")
    XCTAssertEqual(state.checks[3].status, RowStatusValue(.done, "Recorded"))

    visit.record.captures[0].omittedRooms = [
      .init(name: "Primary closet", reason: "locked"), .init(name: "Attic", reason: "no access"),
      .init(name: "Boiler room", reason: "locked"),
    ]
    state = OverviewBuilder.make(input(visit))
    XCTAssertEqual(state.checks[3].subtitle, "Primary closet · locked, +2 more")
  }

  // MARK: Floors while loading and failing (§3.5.2)

  func testLoadingAndUnreadableFloors() throws {
    let visit = try valleyStreet()
    let scans: [LowercaseUUID: OverviewBuilder.FloorScan] = [
      visit.record.captures[0].captureId: .loading, visit.record.captures[1].captureId: .failed,
    ]
    let state = OverviewBuilder.make(input(visit, scans: scans))
    XCTAssertEqual(state.floors[0].subtitle, "Loading…")
    XCTAssertNil(state.floors[0].status)
    XCTAssertEqual(state.floors[1].subtitle, "Whole floor · the scan could not be read")
    XCTAssertEqual(state.floors[1].status, RowStatusValue(.missing, "Open"))
  }

  func testExteriorNeedsNoControls() throws {
    let exterior = Make.capture("Exterior", mode: .exterior)
    let visit = Visit(
      record: Make.record([exterior]), photos: [photo(exterior, "Front", 1)],
      controls: FieldControls(visitId: LowercaseUUID()))
    let checklist = ChecklistRules.evaluate(
      ChecklistInput(
        record: visit.record, capturedRooms: [exterior.captureId: ["Front"]], photos: visit.photos,
        controls: visit.controls), policy: .manualControls)
    let state = OverviewBuilder.make(
      OverviewBuilder.Input(
        record: visit.record, rooms: [exterior.captureId: ["Front"]],
        scans: [exterior.captureId: .mapped(nil)], photos: visit.photos, controls: visit.controls,
        checklist: checklist, policy: .manualControls,
        flow: VisitFlow(resuming: visit.record, isSealed: false), now: now, timeZone: utc))
    XCTAssertEqual(state.floors[0].subtitle, "Exterior · 1 room · 1 photo · controls not needed")
  }

  // MARK: Seal states and the button (A4)

  func testSealedRevisionAndRevisionModeButtons() throws {
    let visit = try valleyStreet()
    var sealed = VisitFlow(resuming: visit.record, isSealed: true, revision: 1)
    var state = OverviewBuilder.make(input(visit, flow: sealed))
    XCTAssertEqual(state.subtitle, "Captured today by Dana Ruiz · revision 1 sealed")
    XCTAssertEqual(state.button, .uploadStatus)
    XCTAssertEqual(state.button.title, "Upload status")
    XCTAssertFalse(state.canAddFloor, "no new floor after sealing")
    state = OverviewBuilder.make(input(visit, flow: sealed, hasVerdict: true))
    XCTAssertEqual(state.button, .openVerdict)
    XCTAssertEqual(state.button.title, "Open the verdict")
    _ = try? sealed.addFloor()

    let revision = VisitFlow(revisionOf: visit.record, base: LowercaseUUID(), baseRevision: 1)
    state = OverviewBuilder.make(input(visit, flow: revision))
    XCTAssertEqual(state.subtitle, "Captured today by Dana Ruiz · revision 2 not sealed yet")
    XCTAssertEqual(state.button, .fix(items: 2), "the gate holds in revision mode")
    XCTAssertTrue(state.canAddFloor)
  }

  func testRevisionModeButtonWhenPassing() throws {
    let single = Make.capture("Floor 1", compass: Make.reading())
    let record = Make.record([single])
    let photos = [photo(single, "Kitchen", 1)]
    var editor = FieldControlsEditor(visitId: record.visitId)
    let ref = FieldControls.CaptureRef(captureId: single.captureId, areaKey: single.areaKey)
    try editor.setDistance(capture: ref, axis: .a, from: "a", to: "b", measurement: measurement(1))
    try editor.setDistance(capture: ref, axis: .b, from: "a", to: "b", measurement: measurement(1))
    try editor.setCeilingHeight(capture: ref, room: "Kitchen", measurement: measurement(1))
    var confirmation = NoRoomsSkippedConfirmation()
    confirmation.confirm(for: record)
    let flow = VisitFlow(
      resuming: record, noRoomsSkipped: confirmation, isSealed: false, revision: 3,
      basePackageId: LowercaseUUID(), isRevisionMode: true)
    let checklist = ChecklistRules.evaluate(
      ChecklistInput(
        record: record, capturedRooms: [single.captureId: ["Kitchen"]], photos: photos,
        controls: editor.controls, noRoomsSkippedConfirmed: true), policy: .manualControls)
    let state = OverviewBuilder.make(
      .init(
        record: record, rooms: [single.captureId: ["Kitchen"]], scans: [single.captureId: .mapped(nil)],
        photos: photos, controls: editor.controls, checklist: checklist, policy: .manualControls,
        flow: flow, now: now, timeZone: utc))
    XCTAssertEqual(state.button, .reviewRevision(3))
    XCTAssertEqual(state.button.title, "Review revision 3")
    XCTAssertEqual(state.floors[0].subtitle, "Whole floor · 1 room · 1 photo · controls complete")
  }
}

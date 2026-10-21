import CaptureContract
import FieldRules
import Foundation
import XCTest

/// AC1: the checklist blocks finishing when any required item is missing and lists exactly which.
final class ChecklistRulesTests: XCTestCase {
  private let f1 = Fixtures.floor1
  private let f2 = Fixtures.floor2

  /// Two floors, every rule satisfied.
  private func completeInput() throws -> ChecklistInput {
    var editor = FieldControlsEditor(visitId: Fixtures.visitId)
    for floor in [f1, f2] {
      try editor.setDistance(
        capture: floor, axis: .a, from: "West wall", to: "East wall",
        measurement: Fixtures.measurement("24' 8\"", .ftIn))
      try editor.setDistance(
        capture: floor, axis: .b, from: "Front wall", to: "Rear wall",
        measurement: Fixtures.measurement("11.24", .m))
      try editor.setCeilingHeight(
        capture: floor, room: "Kitchen", measurement: Fixtures.measurement("2690", .mm))
    }
    try editor.setFloorToFloor(
      lower: f1, upper: f2, location: "At stair", measurement: Fixtures.measurement("3.05", .m))
    try editor.setLandmark(label: "Newel post", captures: [f1, f2])
    try editor.setLandmark(label: "Chimney chase", captures: [f1, f2])

    let record = Fixtures.record(captures: [
      Fixtures.capture(
        f1.captureId, areaKey: "floor-1", label: "Floor 1",
        inaccessible: [CaptureRecord.RoomNote(name: "Primary closet", reason: "locked")]),
      Fixtures.capture(f2.captureId, areaKey: "floor-2", label: "Floor 2", at: Fixtures.t1),
    ])
    return ChecklistInput(
      record: record,
      capturedRooms: [
        f1.captureId: ["Kitchen", "Living"],
        f2.captureId: ["Bath 2"],
      ],
      photos: [
        Fixtures.photo(capture: f1, room: "Kitchen", sequence: 1),
        Fixtures.photo(capture: f1, room: "living ", sequence: 2),
        Fixtures.photo(capture: f2, room: "Bath 2", sequence: 1),
      ],
      controls: editor.controls)
  }

  func testCompleteChecklistAllowsFinishing() throws {
    let report = ChecklistRules.evaluate(try completeInput(), policy: .manualControls)
    XCTAssertTrue(report.canFinish)
    XCTAssertEqual(report.gaps, [])
    XCTAssertEqual(report.finishButtonTitle, "Finish capture")
    XCTAssertEqual(report.items.map(\.id), ChecklistItemID.allCases)
    XCTAssertEqual(report.item(.floorsLabeled).detail, "Floor 1, Floor 2")
    XCTAssertEqual(report.item(.skippedRoomsRecorded).detail, "Primary closet \u{00B7} locked")
    XCTAssertEqual(report.item(.visitDetails).detail, "Filled automatically")
    XCTAssertNoThrow(try report.requireCanFinish())
  }

  func testMissingPhotoAndMissingControlsListExactlyThoseGaps() throws {
    // The scenario of the frozen design: Bath 2 has no photo; floor to floor and a landmark
    // are missing.
    var input = try completeInput()
    input.photos.removeAll { $0.room == "Bath 2" }
    var editor = FieldControlsEditor(controls: input.controls)
    XCTAssertTrue(editor.remove(id: "floor-to-floor-floor-1-floor-2-at-stair"))
    XCTAssertTrue(editor.remove(id: "landmark-chimney-chase"))
    input.controls = editor.controls

    let report = ChecklistRules.evaluate(input, policy: .manualControls)
    XCTAssertFalse(report.canFinish)
    XCTAssertEqual(
      report.gaps,
      [
        .roomWithoutPhoto(capture: "Floor 2", room: "Bath 2"),
        .missingFloorToFloor(lower: "Floor 1", upper: "Floor 2"),
        .missingLandmarks(lower: "Floor 1", upper: "Floor 2", have: 1, need: 2),
      ])
    XCTAssertEqual(report.blockingItems.map(\.id), [.photoPerRoom, .minimumControls])
    XCTAssertEqual(report.item(.photoPerRoom).detail, "Bath 2 has no photo")
    XCTAssertEqual(
      report.item(.minimumControls).detail, "Floor to floor \u{00B7} 1 of 2 landmarks")
    XCTAssertEqual(report.finishButtonTitle, "Fix 2 items to finish")
    XCTAssertTrue(report.item(.floorsLabeled).passed)
    XCTAssertTrue(report.item(.skippedRoomsRecorded).passed)
    XCTAssertTrue(report.item(.visitDetails).passed)

    XCTAssertThrowsError(try report.requireCanFinish()) {
      XCTAssertEqual(($0 as? ChecklistBlockedError)?.gaps, report.gaps)
    }
  }

  func testEveryFloorMustBeLabeled() throws {
    var input = try completeInput()
    input.record.captures[1].label = "  "
    let report = ChecklistRules.evaluate(input, policy: .manualControls)
    XCTAssertEqual(report.gaps, [.unlabeledCapture(areaKey: "floor-2")])
    XCTAssertEqual(report.blockingItems.map(\.id), [.floorsLabeled])

    input.record.captures = []
    XCTAssertTrue(ChecklistRules.evaluate(input, policy: .manualControls).gaps.contains(.noCaptures))
  }

  func testSkippedRoomsMustBeRecordedOrConfirmedNone() throws {
    var input = try completeInput()
    input.record.captures[0].inaccessibleRooms = []
    XCTAssertEqual(ChecklistRules.evaluate(input, policy: .manualControls).gaps, [.skippedRoomsNotRecorded])

    input.noRoomsSkippedConfirmed = true
    let confirmed = ChecklistRules.evaluate(input, policy: .manualControls)
    XCTAssertTrue(confirmed.canFinish)
    XCTAssertEqual(confirmed.item(.skippedRoomsRecorded).detail, "All rooms scanned")

    input.noRoomsSkippedConfirmed = false
    input.record.captures[0].omittedRooms = [CaptureRecord.RoomNote(name: "Attic")]
    input.record.captures[1].inaccessibleRooms = [
      CaptureRecord.RoomNote(name: " ", reason: "locked")
    ]
    XCTAssertEqual(
      ChecklistRules.evaluate(input, policy: .manualControls).gaps,
      [.skippedRoomWithoutReason(room: "Attic"), .skippedRoomWithoutName(.inaccessible)])
  }

  func testNoRoomsSkippedConfirmationDecidesTheRowOnlyWhenNoNoteExists() throws {
    var input = try completeInput()
    input.record.captures[0].inaccessibleRooms = []

    // No notes, confirmed: the row passes.
    input.noRoomsSkippedConfirmed = true
    let confirmed = ChecklistRules.evaluate(input, policy: .manualControls).item(.skippedRoomsRecorded)
    XCTAssertTrue(confirmed.passed)
    XCTAssertEqual(confirmed.gaps, [])
    XCTAssertEqual(confirmed.detail, "All rooms scanned")

    // No notes, not confirmed: the row fails with exactly that gap.
    input.noRoomsSkippedConfirmed = false
    let unconfirmed = ChecklistRules.evaluate(input, policy: .manualControls).item(.skippedRoomsRecorded)
    XCTAssertFalse(unconfirmed.passed)
    XCTAssertEqual(unconfirmed.gaps, [.skippedRoomsNotRecorded])
    XCTAssertEqual(unconfirmed.detail, "Record rooms not scanned, or confirm there are none")

    // A note without a reason still fails, even when confirmed.
    input.noRoomsSkippedConfirmed = true
    input.record.captures[1].omittedRooms = [CaptureRecord.RoomNote(name: "Attic")]
    let incompleteNote = ChecklistRules.evaluate(input, policy: .manualControls)
    XCTAssertFalse(incompleteNote.canFinish)
    XCTAssertEqual(
      incompleteNote.item(.skippedRoomsRecorded).gaps, [.skippedRoomWithoutReason(room: "Attic")])
  }

  func testNoRoomsSkippedConfirmationStartsUnconfirmedAndNeedsAnExplicitTap() throws {
    let record = try completeInput().record
    var withoutNotes = record
    withoutNotes.captures[0].inaccessibleRooms = []

    let confirmation = NoRoomsSkippedConfirmation()
    XCTAssertFalse(confirmation.isConfirmed(for: withoutNotes))
    XCTAssertNil(confirmation.confirmedCaptureIds)

    var tapped = confirmation
    tapped.confirm(for: withoutNotes)
    XCTAssertTrue(tapped.isConfirmed(for: withoutNotes))
    XCTAssertEqual(tapped.confirmedCaptureIds, [f1.captureId, f2.captureId])

    // Feeding the model into the rules turns the row green.
    var input = try completeInput()
    input.record = withoutNotes
    input.noRoomsSkippedConfirmed = tapped.isConfirmed(for: withoutNotes)
    XCTAssertTrue(ChecklistRules.evaluate(input, policy: .manualControls).canFinish)

    tapped.clear()
    XCTAssertFalse(tapped.isConfirmed(for: withoutNotes))
  }

  func testNoRoomsSkippedConfirmationIsInvalidatedByANoteOrAChangedCaptureSet() throws {
    var record = try completeInput().record
    record.captures[0].inaccessibleRooms = []
    var confirmation = NoRoomsSkippedConfirmation()
    confirmation.confirm(for: record)
    XCTAssertTrue(confirmation.isConfirmed(for: record))

    // A skipped-room note added later: the confirmation no longer counts.
    var withNote = record
    withNote.captures[1].omittedRooms = [CaptureRecord.RoomNote(name: "Attic", reason: "owner")]
    XCTAssertFalse(confirmation.isConfirmed(for: withNote))

    // A new capture ("Add more rooms"): the new scan was never confirmed.
    var withNewCapture = record
    withNewCapture.captures.append(
      Fixtures.capture(LowercaseUUID(), areaKey: "basement", label: "Basement", at: Fixtures.t1))
    XCTAssertFalse(confirmation.isConfirmed(for: withNewCapture))

    // A capture replaced by a re-scan (new capture id) also needs a new tap.
    var rescanned = record
    rescanned.captures[1].captureId = LowercaseUUID()
    XCTAssertFalse(confirmation.isConfirmed(for: rescanned))

    // Label or order changes do not touch skipped rooms: still confirmed.
    var relabeled = record
    relabeled.captures[1].label = "Upstairs"
    relabeled.captures.reverse()
    XCTAssertTrue(confirmation.isConfirmed(for: relabeled))

    // Confirming while a note exists records nothing that can pass.
    var early = NoRoomsSkippedConfirmation()
    early.confirm(for: withNote)
    XCTAssertFalse(early.isConfirmed(for: withNote))
  }

  func testEveryCapturedRoomNeedsAtLeastOnePhoto() throws {
    var input = try completeInput()
    input.photos = []
    XCTAssertEqual(
      ChecklistRules.evaluate(input, policy: .manualControls).gaps,
      [
        .roomWithoutPhoto(capture: "Floor 1", room: "Kitchen"),
        .roomWithoutPhoto(capture: "Floor 1", room: "Living"),
        .roomWithoutPhoto(capture: "Floor 2", room: "Bath 2"),
      ])

    // A photo of the right room but on the other floor does not count.
    input.photos = [
      Fixtures.photo(capture: f2, room: "Kitchen"), Fixtures.photo(capture: f1, room: "Living"),
      Fixtures.photo(capture: f2, room: "Bath 2"),
    ]
    XCTAssertEqual(
      ChecklistRules.evaluate(input, policy: .manualControls).gaps,
      [.roomWithoutPhoto(capture: "Floor 1", room: "Kitchen")])

    // No room list for a capture: at least one photo of that capture is needed.
    input.capturedRooms = [:]
    input.photos = [Fixtures.photo(capture: f1, room: "Anything")]
    XCTAssertEqual(
      ChecklistRules.evaluate(input, policy: .manualControls).gaps, [.captureWithoutPhoto(capture: "Floor 2")])
  }

  func testEachMinimumControlIsCheckedPerFloor() throws {
    let base = try completeInput()
    func gaps(removing ids: [String]) -> [ChecklistGap] {
      var input = base
      var editor = FieldControlsEditor(controls: input.controls)
      for id in ids { XCTAssertTrue(editor.remove(id: id), id) }
      input.controls = editor.controls
      return ChecklistRules.evaluate(input, policy: .manualControls).gaps
    }
    XCTAssertEqual(
      gaps(removing: ["floor-2-distance-a"]), [.missingDistance(capture: "Floor 2", axis: .a)])
    XCTAssertEqual(
      gaps(removing: ["floor-1-distance-b"]), [.missingDistance(capture: "Floor 1", axis: .b)])
    XCTAssertEqual(
      gaps(removing: ["floor-1-ceiling-kitchen"]), [.missingCeilingHeight(capture: "Floor 1")])
    XCTAssertEqual(
      gaps(removing: ["landmark-newel-post", "landmark-chimney-chase"]),
      [.missingLandmarks(lower: "Floor 1", upper: "Floor 2", have: 0, need: 2)])
    XCTAssertEqual(
      gaps(removing: ["floor-to-floor-floor-1-floor-2-at-stair"]),
      [.missingFloorToFloor(lower: "Floor 1", upper: "Floor 2")])
  }

  func testFloorToFloorAcceptsEitherOrderAndExteriorNeedsNoFloorControls() throws {
    var input = try completeInput()
    var editor = FieldControlsEditor(controls: input.controls)
    editor.remove(id: "floor-to-floor-floor-1-floor-2-at-stair")
    try editor.setFloorToFloor(
      lower: f2, upper: f1, location: "At stair", measurement: Fixtures.measurement("3.05", .m))
    input.controls = editor.controls
    XCTAssertTrue(ChecklistRules.evaluate(input, policy: .manualControls).canFinish)

    let exteriorId = LowercaseUUID()
    input.record.captures.append(
      Fixtures.capture(
        exteriorId, areaKey: "exterior", label: "Exterior", mode: .exterior, at: Fixtures.t1))
    input.photos.append(
      Fixtures.photo(
        capture: FieldControls.CaptureRef(captureId: exteriorId, areaKey: "exterior"),
        room: "Front"))
    XCTAssertTrue(ChecklistRules.evaluate(input, policy: .manualControls).canFinish)
  }

  func testDeviceOperatorAndDatesMustBePresent() throws {
    var input = try completeInput()
    input.record.operator.name = ""
    input.record.device.model = " "
    input.record.device.osVersion = ""
    input.record.visitedAt = UTCTimestamp(secondsSince1970: 0)
    input.record.captures[1].capturedAt = UTCTimestamp(secondsSince1970: 0)
    XCTAssertEqual(
      ChecklistRules.evaluate(input, policy: .manualControls).gaps,
      [
        .missingDetail(.device), .missingDetail(.operatingSystem),
        .missingDetail(.operatorName), .missingDetail(.visitDate),
        .missingDetail(.captureDate(capture: "Floor 2")),
      ])
  }

  func testNothingDoneListsEveryGapAndSingularButtonWording() throws {
    var input = try completeInput()
    input.photos = []
    input.controls = FieldControls(visitId: Fixtures.visitId)
    input.record.captures[0].inaccessibleRooms = []
    let report = ChecklistRules.evaluate(input, policy: .manualControls)
    XCTAssertEqual(
      report.blockingItems.map(\.id), [.skippedRoomsRecorded, .photoPerRoom, .minimumControls])
    // In the order of the Field controls list: Floor 1, between, Floor 2.
    XCTAssertEqual(
      report.item(.minimumControls).gaps,
      [
        .missingDistance(capture: "Floor 1", axis: .a),
        .missingDistance(capture: "Floor 1", axis: .b),
        .missingCeilingHeight(capture: "Floor 1"),
        .missingFloorToFloor(lower: "Floor 1", upper: "Floor 2"),
        .missingLandmarks(lower: "Floor 1", upper: "Floor 2", have: 0, need: 2),
        .missingDistance(capture: "Floor 2", axis: .a),
        .missingDistance(capture: "Floor 2", axis: .b),
        .missingCeilingHeight(capture: "Floor 2"),
      ])
    XCTAssertEqual(
      report.item(.minimumControls).detail,
      "Floor 1 set \u{00B7} Floor to floor \u{00B7} 0 of 2 landmarks \u{00B7} Floor 2 set")
    XCTAssertEqual(report.finishButtonTitle, "Fix 3 items to finish")

    input.record.captures[0].inaccessibleRooms = [
      CaptureRecord.RoomNote(name: "Closet", reason: "locked")
    ]
    input.photos = try completeInput().photos
    XCTAssertEqual(ChecklistRules.evaluate(input, policy: .manualControls).finishButtonTitle, "Fix 1 item to finish")
  }

  func testPolicyCanChangeTheLandmarkMinimum() throws {
    var input = try completeInput()
    var editor = FieldControlsEditor(controls: input.controls)
    editor.remove(id: "landmark-chimney-chase")
    input.controls = editor.controls
    XCTAssertFalse(ChecklistRules.evaluate(input, policy: .manualControls).canFinish)
    XCTAssertTrue(
      ChecklistRules.evaluate(input, policy: ChecklistPolicy(minimumLandmarksPerFloorPair: 1, manualControlsRequired: true))
        .canFinish)
  }

  func testPhotoLabelDraftRequiresRoomDirectionAndSubject() {
    var draft = PhotoLabelDraft()
    XCTAssertEqual(draft.missing, [.room, .direction, .subject])
    XCTAssertNil(draft.labels(takenAt: Fixtures.t0))
    draft.room = "  Kitchen "
    draft.chooseDirection(.east)
    XCTAssertEqual(draft.missing, [.subject])
    draft.subject = .cabinetry
    XCTAssertTrue(draft.isComplete)
    XCTAssertEqual(
      draft.labels(takenAt: Fixtures.t0),
      PackageManifest.PhotoLabels(
        room: "Kitchen", direction: .east, subject: .cabinetry, takenAt: Fixtures.t0,
        directionSource: .manual))
    let next = draft.forNextPhoto()
    XCTAssertEqual(next.room, "  Kitchen ")
    XCTAssertEqual(next.missing, [.direction, .subject])
    // All seven subjects as chips (design v2: no More), together every contract subject.
    XCTAssertEqual(Set(PhotoSubject.primaryChoices), Set(PhotoSubject.allCases))
  }

  // MARK: LiDAR-filled controls (standard policy)

  func testStandardPolicyPassesControlsFromTheScanWithoutTapeOrLaser() throws {
    var input = try completeInput()
    input.controls = FieldControls(visitId: Fixtures.visitId)
    let item = ChecklistRules.evaluate(input).item(.minimumControls)
    XCTAssertTrue(item.passed)
    XCTAssertEqual(item.gaps, [])
    XCTAssertEqual(item.detail, "Measured by the LiDAR scan")
  }

  func testStandardPolicyCountsOptionalTapeOrLaserChecks() throws {
    let input = try completeInput()
    let item = ChecklistRules.evaluate(input).item(.minimumControls)
    XCTAssertTrue(item.passed)
    XCTAssertTrue(item.detail.hasPrefix("Measured by the LiDAR scan \u{00B7} "))
    XCTAssertTrue(item.detail.hasSuffix("tape or laser checks"))
  }
}

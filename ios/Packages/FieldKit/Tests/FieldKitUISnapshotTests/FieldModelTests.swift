#if canImport(UIKit) && os(iOS)
  import CaptureContract
  @testable import FieldKitUI
  import FieldRules
  import Foundation
  import PhotoStore
  import SwiftUI
  import XCTest

  /// The screen models behind the snapshots: photo labeling (room kept, compass pre-fill, saving),
  /// the Field controls entry sheet (prefill, saving, editing, read-only, word fields) and
  /// Before you leave's focus flash.
  @MainActor
  final class FieldModelTests: XCTestCase {
    private typealias F = SnapshotFixtures

    // MARK: Photo labeling

    func testTheRoomOfTheLastPhotoIsSelectedAndTitlesFollowV2() throws {
      let model = PhotoLabelingModel(
        capture: F.capture(F.floor1, "Floor 1", at: F.t0, rooms: F.floor1Rooms),
        store: try F.photoStore(), capturePhoto: { F.heic() })
      XCTAssertEqual(model.draft.room, "Kitchen", "the last saved photo was of the Kitchen")
      XCTAssertEqual(model.title, "Photo 14 \u{00B7} Floor 1")
      XCTAssertEqual(model.headerTitle, "Photo 14 \u{00B7} Floor 1")
      XCTAssertEqual(model.primaryRooms, ["Kitchen", "Living", "Bath 1", "Bedroom 1"])

      let target = PhotoLabelingModel(
        capture: F.capture(F.floor1, "Floor 1", at: F.t0, rooms: F.floor1Rooms),
        store: try F.photoStore(), initialRoom: " Primary closet ", capturePhoto: { F.heic() })
      XCTAssertEqual(target.draft.room, "Primary closet")
      XCTAssertEqual(target.headerTitle, "Primary closet \u{00B7} Photo 14 \u{00B7} Floor 1")
      XCTAssertEqual(target.primaryRooms.last, "Primary closet", "kept on screen, not behind More")
    }

    func testTheShutterPrefillsTheDirectionFromTheCompass() async throws {
      let model = try await F.labelingModel(compass: true, subject: false)
      XCTAssertEqual(model.pendingFormat, .heic)
      XCTAssertEqual(model.takenAtText, "12:41")
      XCTAssertEqual(model.draft.direction, .east)
      XCTAssertEqual(model.draft.directionCaptionSuffix, "\u{00B7} from the compass, change if wrong")
      XCTAssertEqual(model.missingHint, "Choose Subject to save.")
      XCTAssertFalse(model.canSave)
      model.chooseSubject(.cabinetry)
      XCTAssertTrue(model.canSave)
    }

    func testTheHeadingRunsWithTheViewfinder() {
      let heading = FixedPhotoHeading(azimuthDegrees: 85)
      let model = PhotoLabelingModel(
        capture: F.capture(F.floor1, "Floor 1", at: F.t0, rooms: F.floor1Rooms),
        store: try! F.photoStore(), heading: heading, capturePhoto: { F.heic() })
      model.startHeading()
      XCTAssertTrue(heading.isRunning)
      model.stopHeading()
      XCTAssertFalse(heading.isRunning)
    }

    func testSaveAndTakeNextKeepsTheRoomAndRecordsTheSource() async throws {
      let model = try await F.labelingModel(compass: true, subject: true)
      model.saveAndTakeNext()
      XCTAssertNil(model.pendingOriginal)
      XCTAssertNil(model.errorMessage)
      let saved = try XCTUnwrap(model.store.records.last)
      XCTAssertEqual(saved.room, "Kitchen")
      XCTAssertEqual(saved.direction, .east)
      XCTAssertEqual(saved.labels.directionSource, .compass)
      XCTAssertEqual(saved.labels.takenAt, F.shutter)
      // The next photo: same room, direction and subject to choose again.
      XCTAssertEqual(model.draft.room, "Kitchen")
      XCTAssertNil(model.draft.direction)
      XCTAssertNil(model.draft.subject)
      XCTAssertEqual(model.title, "Photo 15 \u{00B7} Floor 1")
      XCTAssertEqual(model.strip.count, 6)
    }

    func testDoneWithPhotosSavesAndReportsSuccess() async throws {
      let model = try await F.labelingModel(compass: false, subject: true)
      XCTAssertFalse(model.saveAndFinish(), "no direction yet")
      model.chooseDirection(.north)
      XCTAssertTrue(model.saveAndFinish())
      XCTAssertEqual(model.store.records.last?.labels.directionSource, .manual)
      XCTAssertFalse(model.saveAndFinish(), "nothing pending any more")
    }

    func testDiscardThrowsThePhotoAwayAndKeepsTheRoom() async throws {
      let model = try await F.labelingModel(compass: true, subject: true)
      let count = model.store.records.count
      model.discardPending()
      XCTAssertNil(model.pendingOriginal)
      XCTAssertEqual(model.store.records.count, count)
      XCTAssertEqual(model.draft.room, "Kitchen")
      XCTAssertNil(model.draft.subject)
    }

    func testARoomNotInTheListBecomesAChip() async throws {
      let model = try await F.labelingModel(compass: true, subject: true)
      model.otherRoom = "  "
      XCTAssertFalse(model.useOtherRoom())
      model.otherRoom = " Garage "
      XCTAssertTrue(model.useOtherRoom())
      XCTAssertEqual(model.draft.room, "Garage")
      XCTAssertEqual(model.otherRoom, "")
      XCTAssertEqual(model.primaryRooms.last, "Garage")
      XCTAssertTrue(model.isSelected("garage"))
      XCTAssertEqual(
        model.strip.text, "1 photo in Garage \u{00B7} keep people and personal items out of the frame")
    }

    func testRenamedRoomsFollowTheSelection() async throws {
      let model = try await F.labelingModel(compass: true, subject: true)
      var rooms = F.floor1Rooms
      rooms[0] = "Kitchenette"
      model.roomsRenamed(rooms: rooms, renames: [(from: "Kitchen", to: "Kitchenette")])
      XCTAssertEqual(model.draft.room, "Kitchenette")
      XCTAssertEqual(model.primaryRooms.first, "Kitchenette")
      XCTAssertNotNil(model.pendingOriginal, "the photo being labeled is kept")
    }

    // MARK: Field controls

    private func controls(
      policy: ChecklistPolicy = .manualControls, persist: @escaping @MainActor (FieldControls) throws -> Void = { _ in }
    ) throws -> FieldControlsModel {
      FieldControlsModel(
        captures: F.captures(withScan: false), controls: try F.artboardControls(), policy: policy,
        persist: persist, now: { F.t1 })
    }

    func testARecordedDistanceOpensPrefilled() throws {
      let model = try controls()
      model.open(try XCTUnwrap(model.row("floor-1.distanceA")))
      let entry = try XCTUnwrap(model.entry)
      XCTAssertEqual(entry.title, "Long distance A")
      XCTAssertEqual(entry.editingId, "floor-1-distance-a")
      XCTAssertEqual(entry.from, "Kitchen east wall")
      XCTAssertEqual(entry.to, "living west wall")
      XCTAssertEqual(entry.value, MeasurementEntryDraft(unit: .mm, value: "7520"))
      XCTAssertEqual(entry.initialFocus, .firstValue)
      XCTAssertTrue(entry.canSave)
    }

    func testANewFloorToFloorStartsAtTheStairInTheLastUnit() throws {
      let model = try controls()
      model.focus(rowId: "floor-1~floor-2.floorToFloor")
      XCTAssertEqual(model.scrollTarget, "floor-1~floor-2.floorToFloor")
      let entry = try XCTUnwrap(model.entry)
      XCTAssertNil(entry.editingId)
      XCTAssertEqual(entry.location, "At the stair")
      // The artboard's controls were entered in mm, the last one in inches (not offered): mm.
      XCTAssertEqual(entry.value.unit, .mm)
      XCTAssertEqual(entry.initialFocus, .firstValue)
      XCTAssertFalse(entry.canSave)
      XCTAssertEqual(
        entry.footnote.text, "Stored in mm. Shown in both units everywhere. Tape or laser only.")
    }

    func testWithoutMeasurementsTheUnitFollowsTheCapture() throws {
      var metric = F.captures(withScan: false)
      metric[0].displayUnits = .metric
      let model = FieldControlsModel(
        captures: metric, controls: FieldControls(visitId: F.visitId), persist: { _ in })
      model.focus(rowId: "floor-1.distanceA")
      XCTAssertEqual(model.entry?.value.unit, .mm)
      XCTAssertEqual(model.entry?.initialFocus, .from)
      model.focus(rowId: "floor-2.distanceB")
      XCTAssertEqual(model.entry?.value.unit, .ftIn)
      XCTAssertEqual(
        model.entry?.footnote.text,
        "At a right angle to A. Stored in mm. Shown in both units everywhere. Tape or laser only.")
    }

    func testSavingPersistsTheWholeDocumentAndClosesTheSheet() throws {
      var written: [FieldControls] = []
      let model = try controls(persist: { written.append($0) })
      model.focus(rowId: "floor-1~floor-2.floorToFloor")
      let entry = try XCTUnwrap(model.entry)
      entry.chooseUnit(.ftIn)
      entry.value.feet = "10"
      entry.value.inches = "0,5"
      XCTAssertEqual(
        entry.footnote.text,
        "Stored as 3,061 mm. Shown in both units everywhere. Tape or laser only.")
      model.saveEntry()
      XCTAssertNil(model.entry)
      XCTAssertEqual(written.count, 1)
      let level = try XCTUnwrap(model.controls.floorToFloor.first)
      XCTAssertEqual(level.location, "At the stair")
      XCTAssertEqual(level.measurement.enteredText, "10' 0.5\"")
      XCTAssertEqual(level.measurement.valueMm, 3060.7, accuracy: 0)
      XCTAssertEqual(level.measurement.recordedAt, F.t1)
      XCTAssertEqual(model.progress?.text, "5 of 9 required")
      XCTAssertEqual(written.last, model.controls)
    }

    func testEditingAListEntryReplacesItWhenItsIdChanges() throws {
      let model = try controls()
      model.focus(rowId: "floor-1.ceilingHeight")
      let entry = try XCTUnwrap(model.entry)
      XCTAssertEqual(entry.recorded.map(\.title), ["Kitchen", "Living", "Bath 1"])
      XCTAssertNil(entry.initialFocus, "the next step is a room chip")
      model.edit(recordedId: "floor-1-ceiling-living")
      XCTAssertEqual(entry.title, "Ceiling height \u{00B7} Living")
      XCTAssertEqual(entry.room, "Living")
      entry.room = "Bedroom 1"
      entry.value.value = "2750"
      model.saveEntry()
      XCTAssertNil(model.entry)
      let ids = model.controls.ceilingHeights.map(\.id)
      XCTAssertFalse(ids.contains("floor-1-ceiling-living"), "the old entry is gone")
      XCTAssertTrue(ids.contains("floor-1-ceiling-bedroom-1"))
      XCTAssertEqual(ids.count, 3)
    }

    func testEditingInPlaceKeepsTheOrder() throws {
      let model = try controls()
      model.open(try XCTUnwrap(model.row("floor-1.distanceB")))
      model.entry?.value.value = "11250"
      model.saveEntry()
      XCTAssertEqual(model.controls.distances.map(\.id), ["floor-1-distance-a", "floor-1-distance-b"])
      XCTAssertEqual(model.controls.distances[1].measurement.valueMm, 11250, accuracy: 0)
    }

    func testALandmarkNeedsTwoFloorsAndKeepsItsDescription() throws {
      let model = try controls()
      model.focus(rowId: "floor-1~floor-2.landmarks")
      let entry = try XCTUnwrap(model.entry)
      XCTAssertEqual(entry.landmarkFloors, [F.floor1.captureId, F.floor2.captureId])
      XCTAssertEqual(entry.recordedCaption, "Recorded between Floor 1 and Floor 2")
      XCTAssertEqual(entry.recorded.map(\.subtitle), ["Floor 1, Floor 2"])
      entry.label = "Chimney chase"
      entry.toggleLandmarkFloor(F.floor2.captureId)
      XCTAssertFalse(entry.canSave)
      entry.toggleLandmarkFloor(F.floor2.captureId)
      XCTAssertTrue(entry.canSave)
      model.saveEntry()
      XCTAssertEqual(model.progress?.text, "5 of 9 required")
    }

    func testAPersistFailureKeepsNothing() throws {
      struct DiskFull: Error {}
      let model = try controls(persist: { _ in throw DiskFull() })
      let before = model.controls
      model.focus(rowId: "floor-2.distanceA")
      let entry = try XCTUnwrap(model.entry)
      entry.from = "Stair"
      entry.to = "Rear wall"
      entry.value.value = "6100"
      model.saveEntry()
      XCTAssertNotNil(model.entry, "the sheet stays")
      XCTAssertEqual(model.controls, before)
      XCTAssertTrue(entry.footnote.isError)
      XCTAssertTrue(entry.footnote.text.hasPrefix("The measurement could not be saved: "))
    }

    func testReadOnlyOpensWithoutSave() throws {
      let model = FieldControlsModel(
        captures: F.captures(withScan: false), controls: try F.artboardControls(),
        isReadOnly: true, sealedRevision: 2, persist: { _ in XCTFail("nothing is written") })
      XCTAssertEqual(
        model.footnote,
        "Revision 2 is sealed. To change it, use Add to this capture on the verdict screen.")
      model.focus(rowId: "floor-1.distanceA")
      let entry = try XCTUnwrap(model.entry)
      XCTAssertTrue(entry.isReadOnly)
      XCTAssertFalse(entry.canSave)
      XCTAssertNil(entry.initialFocus)
      model.saveEntry()
      XCTAssertNotNil(model.entry)
    }

    func testAddOnBeforeYouLeaveOpensTheFirstGap() throws {
      let model = try controls()
      let report = try F.failingReport()
      model.focusFirstGap(of: report.item(.minimumControls))
      XCTAssertEqual(model.entry?.rowId, "floor-1~floor-2.floorToFloor")
      XCTAssertEqual(model.scrollTarget, "floor-1~floor-2.floorToFloor")
    }

    func testTheProgressShowsOnlyUnderTheManualPolicy() throws {
      XCTAssertEqual(try controls().progress?.text, "4 of 9 required")
      XCTAssertNil(try controls(policy: .standard).progress)
      XCTAssertEqual(
        try controls(policy: .standard).subtitle,
        "Measured by the LiDAR scan. Tap a row to add an optional tape or laser check.")
    }

    /// The word fields wrap (`axis: .vertical`), so Return would type a line break: it moves on
    /// instead, From → To → the value, a typed room → the next words, a landmark's label → the
    /// floor chips (no field).
    func testReturnInAWordFieldMovesOn() throws {
      let model = try controls()
      model.focus(rowId: "floor-2.distanceA")
      XCTAssertEqual(model.entry?.focus(after: .from), .to)
      XCTAssertEqual(model.entry?.focus(after: .to), .firstValue)
      model.focus(rowId: "floor-1.ceilingHeight")
      XCTAssertEqual(model.entry?.focus(after: .room), .location)
      XCTAssertEqual(model.entry?.focus(after: .location), .firstValue)
      model.focus(rowId: "floor-1.openings")
      XCTAssertEqual(model.entry?.focus(after: .room), .label)
      XCTAssertEqual(model.entry?.focus(after: .label), .firstValue)
      model.focus(rowId: "floor-1~floor-2.floorToFloor")
      XCTAssertEqual(model.entry?.focus(after: .location), .firstValue)
      model.focus(rowId: "floor-1~floor-2.landmarks")
      XCTAssertNil(model.entry?.focus(after: .label))
    }

    /// What a word field keeps of a line break: nothing at the ends, one space between words.
    func testWordsStayOnOneLine() {
      typealias Entry = ControlEntryModel
      XCTAssertEqual(Entry.oneLine("At the stair"), "At the stair")
      XCTAssertEqual(Entry.oneLine("  Kitchen  "), "  Kitchen  ", "no line break: as typed")
      XCTAssertEqual(Entry.oneLine("Kitchen east wall\n"), "Kitchen east wall")
      XCTAssertEqual(Entry.oneLine("Kitchen east\n wall"), "Kitchen east wall")
      XCTAssertEqual(
        Entry.oneLine("\nAt the stair,\r\n\nFloor 1 landing \n"), "At the stair, Floor 1 landing")
      XCTAssertEqual(Entry.oneLine("\n"), "")
    }

    // MARK: Before you leave

    /// Addendum B3: the row Before you leave was opened for stays nude for 0.6 s, then fades
    /// out; with Reduce Motion it clears at once. (The scroll and the fill are in the
    /// `before-you-leave-focus-ax3` snapshot.)
    func testTheFocusedRowFlashesForSixTenthsOfASecond() {
      XCTAssertEqual(FocusFlash.hold, 0.6)
      XCTAssertEqual(FocusFlash.fade(reduceMotion: false), .easeOut(duration: 0.3))
      XCTAssertNil(FocusFlash.fade(reduceMotion: true))
    }
  }
#endif

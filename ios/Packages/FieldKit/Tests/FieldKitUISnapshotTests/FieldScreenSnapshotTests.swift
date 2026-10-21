#if canImport(UIKit) && os(iOS)
  import CaptureContract
  import ChapterUI
  import ChapterUISnapshotTesting
  @testable import FieldKitUI
  import FieldRules
  import SwiftUI
  import XCTest

  /// AC9 (phone-field §15.2, addendum B6): the four v2 screens and the three sheets of artboard
  /// 2d in the states it draws (and the ones it does not), each a full iPhone 17 Pro screen
  /// (402 × 874 pt @3x, iOS 26.0) drawn by ChapterUISnapshotTesting, at the default text size
  /// and at AX3. References were recorded once and reviewed side by side with the artboard.
  /// Record again with RECORD_SNAPSHOTS=1 (`TEST_RUNNER_RECORD_SNAPSHOTS=1 xcodebuild test …`).
  @MainActor
  final class FieldScreenSnapshotTests: ChapterSnapshotTestCase {
    private typealias F = SnapshotFixtures

    private func both<V: View>(_ view: @autoclosure () -> V, named name: String) {
      assertChapterSnapshot(of: view(), named: name)
      assertChapterSnapshot(of: view(), named: "\(name)-ax3", contentSize: .accessibilityExtraLarge)
    }

    // MARK: 1–2 Label a photo

    func testLabelAPhotoWithTheCompass() async throws {
      let model = try await F.labelingModel(compass: true, subject: true)
      XCTAssertEqual(model.draft.direction, .east)
      XCTAssertEqual(model.strip.text, "5 photos in Kitchen \u{00B7} keep people and personal items out of the frame")
      both(Pushed { PhotoLabelingView(model: model, onDone: {}, onRenameRooms: {}) }, named: "label-photo")
    }

    func testLabelAPhotoWithoutACompassReading() async throws {
      let model = try await F.labelingModel(compass: false, subject: false)
      XCTAssertNil(model.draft.direction)
      XCTAssertEqual(model.missingHint, "Choose Looking toward and Subject to save.")
      both(Pushed { PhotoLabelingView(model: model, onDone: {}, onRenameRooms: {}) }, named: "label-photo-no-compass")
    }

    // MARK: 3–4 Field controls

    func testFieldControlsManualPolicy() throws {
      let model = try F.controlsModel(policy: .manualControls, withScan: false)
      XCTAssertEqual(model.progress?.text, "4 of 9 required")
      both(Pushed { FieldControlsView(model: model) }, named: "field-controls-manual")
    }

    func testFieldControlsStandardPolicy() throws {
      let model = try F.controlsModel(policy: .standard, withScan: true)
      both(Pushed { FieldControlsView(model: model) }, named: "field-controls-standard")
    }

    func testFieldControlsReadOnly() throws {
      let model = try F.controlsModel(policy: .standard, withScan: true, isReadOnly: true)
      assertChapterSnapshot(of: Pushed { FieldControlsView(model: model) }, named: "field-controls-sealed")
    }

    // MARK: 5–6 Entry sheet

    /// Floor to floor, ft-in, 10 / 0.5, tape, over the list it was opened from.
    private func floorToFloorEntry(feet: String, inches: String) throws -> FieldControlsModel {
      let model = try F.controlsModel(policy: .manualControls, withScan: false)
      model.focus(rowId: "floor-1~floor-2.floorToFloor")
      let entry = try XCTUnwrap(model.entry)
      entry.location = "At the stair, Floor 1 landing to Floor 2 landing"
      entry.chooseUnit(.ftIn)
      entry.value.feet = feet
      entry.value.inches = inches
      return model
    }

    /// The sheet of `model` over the list. (The harness draws a sheet presented from the root of
    /// the window; one presented from a pushed screen is not up within its settle time, so the
    /// list behind is a second model without an open sheet.)
    private func entrySheet(_ model: FieldControlsModel) throws -> some View {
      let entry = try XCTUnwrap(model.entry)
      let list = try F.controlsModel(policy: model.policy, withScan: false)
      return Pushed { FieldControlsView(model: list) }
        .sheet(isPresented: .constant(true)) {
          ControlEntrySheet(entry: entry, onCancel: {}, onSave: {}, onEditRecorded: { _ in })
        }
    }

    func testEntrySheetFeetAndInches() throws {
      let model = try floorToFloorEntry(feet: "10", inches: "0.5")
      XCTAssertEqual(model.entry?.footnote.text, "Stored as 3,061 mm. Shown in both units everywhere. Tape or laser only.")
      XCTAssertEqual(model.entry?.canSave, true)
      let view = try entrySheet(model)
      both(view, named: "entry-sheet")
    }

    func testEntrySheetError() throws {
      let model = try floorToFloorEntry(feet: "10", inches: "12")
      XCTAssertEqual(model.entry?.footnote.text, "Inches must be less than 12 when feet are given.")
      XCTAssertEqual(model.entry?.canSave, false)
      let view = try entrySheet(model)
      both(view, named: "entry-sheet-error")
    }

    func testEntrySheetCeilingHeightWithTheRecordedList() throws {
      let model = try F.controlsModel(policy: .manualControls, withScan: false)
      model.focus(rowId: "floor-1.ceilingHeight")
      XCTAssertEqual(model.entry?.recordedCaption, "Recorded on Floor 1")
      let view = try entrySheet(model)
      assertChapterSnapshot(of: view, named: "entry-sheet-ceiling")
    }

    func testEntrySheetLandmark() throws {
      let model = try F.controlsModel(policy: .manualControls, withScan: false)
      model.focus(rowId: "floor-1~floor-2.landmarks")
      XCTAssertEqual(model.entry?.title, "Shared landmark")
      let view = try entrySheet(model)
      assertChapterSnapshot(of: view, named: "entry-sheet-landmark")
    }

    func testEntrySheetReadOnly() throws {
      let model = try F.controlsModel(policy: .standard, withScan: true, isReadOnly: true)
      model.focus(rowId: "floor-1.distanceA")
      XCTAssertEqual(model.entry?.canSave, false)
      let view = try entrySheet(model)
      assertChapterSnapshot(of: view, named: "entry-sheet-sealed")
    }

    // MARK: 7–8 Before you leave

    func testBeforeYouLeaveFailing() throws {
      let report = try F.failingReport()
      XCTAssertEqual(report.finishButtonTitle, "Fix 2 items to finish")
      both(
        Pushed {
          BeforeYouLeaveView(
            report: report, headerCaption: "618 Valley Street", onTakePhoto: { _ in },
            onAddControls: { _ in }, onReadCompass: nil, onConfirmNoRoomsSkipped: {},
            onRenameRooms: nil, onFinish: {})
        }, named: "before-you-leave")
    }

    func testBeforeYouLeavePassing() throws {
      let report = try F.passingReport()
      XCTAssertTrue(report.canFinish)
      XCTAssertTrue(report.item(.compass).passed)
      both(
        Pushed {
          BeforeYouLeaveView(
            report: report, headerCaption: "618 Valley Street", onTakePhoto: { _ in },
            onAddControls: { _ in }, onConfirmNoRoomsSkipped: {}, onRenameRooms: {}, onFinish: {})
        }, named: "before-you-leave-passed")
    }

    func testBeforeYouLeaveSealed() throws {
      let report = try F.failingReport()
      assertChapterSnapshot(
        of: Pushed {
          BeforeYouLeaveView(
            report: report, headerCaption: "618 Valley Street", isReadOnly: true,
            sealedRevision: 1, onTakePhoto: { _ in }, onAddControls: { _ in },
            onConfirmNoRoomsSkipped: {}, onRenameRooms: {}, onFinish: {})
        }, named: "before-you-leave-sealed")
    }

    // MARK: 9–10 Sheets

    /// Opened from Before you leave's "Rename rooms".
    func testRenameRoomsSheet() throws {
      let report = try F.failingReport()
      both(
        Pushed {
          BeforeYouLeaveView(
            report: report, headerCaption: "618 Valley Street", onTakePhoto: { _ in },
            onAddControls: { _ in }, onRenameRooms: {}, onFinish: {})
        }
        .sheet(isPresented: .constant(true)) {
          RoomNamesSheet(draft: F.roomNamingDraft()) { _ in nil }
        }, named: "rename-rooms")
    }

    func testRoomPickerSheet() async throws {
      let model = try await F.labelingModel(compass: true, subject: true)
      both(
        Pushed { PhotoLabelingView(model: model, onDone: {}, onRenameRooms: {}) }
          .sheet(isPresented: .constant(true)) {
            RoomPickerSheet(model: model, onRenameRooms: {})
          }, named: "room-picker")
    }

    // MARK: Viewfinder

    func testViewfinder() throws {
      let model = PhotoLabelingModel(
        capture: F.capture(F.floor1, "Floor 1", at: F.t0, rooms: F.floor1Rooms),
        store: try F.photoStore(), initialRoom: "Bath 2", capturePhoto: { F.heic() })
      XCTAssertEqual(model.headerTitle, "Bath 2 \u{00B7} Photo 14 \u{00B7} Floor 1")
      assertChapterSnapshot(
        of: Pushed {
          PhotoViewfinder(model: model, onDone: {}, onRenameRooms: {}) {
            LinearGradient(
              colors: [Color(white: 0.30), Color(white: 0.16)], startPoint: .top,
              endPoint: .bottom)
          }
        }, named: "viewfinder")
    }
  }
#endif

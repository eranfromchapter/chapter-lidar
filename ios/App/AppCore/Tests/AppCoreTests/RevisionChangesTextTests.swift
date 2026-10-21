import CaptureContract
import FieldRules
import Foundation
import XCTest

@testable import AppCore

/// Revision n (phone-package §6.1, §6.2, §10.4): every row string, the Unchanged title, the
/// footnote variants and the next-revision notice, from two hand-made revisions.
final class RevisionChangesTextTests: XCTestCase {
  private typealias File = RevisionChanges.Side.File

  private let floor1 = Make.capture("Floor 1", inaccessible: ["Primary closet"])
  private let floor2 = Make.capture("Floor 2")
  private let closet = Make.capture("Primary closet", mode: .room)
  private let actions = [
    "Scan or measure Primary closet on the next visit if it is in scope.",
    "Tape-measure the Room 4 ceiling height.",
  ]

  private func measurement(_ mm: Double, _ method: MeasurementMethod = .tape) -> FieldControls.Measurement {
    .init(valueMm: mm, enteredUnit: .mm, enteredText: "\(mm)", method: method, recordedAt: Make.t1402)
  }

  private func ref(_ capture: CaptureRecord.Capture) -> FieldControls.CaptureRef {
    .init(captureId: capture.captureId, areaKey: capture.areaKey)
  }

  private func heights(_ count: Int, capture: CaptureRecord.Capture) -> [FieldControls.CeilingHeight] {
    (1...count).map {
      .init(id: "c\($0)", capture: ref(capture), room: "Room \($0)", measurement: measurement(2400))
    }
  }

  private func captureFiles(_ capture: CaptureRecord.Capture, count: Int, sha: String = "a")
    -> [File]
  {
    let roles: [FileRole] = [
      .rawRoomplanJSON, .rawDepth, .captureModel, .planDXF, .roomsCSV, .planPDF, .planPNG,
      .planSVG, .pointCloudLAS,
    ]
    return roles.prefix(count).map {
      File(
        path: "Original Exports/\(capture.areaKey)/\($0.rawValue)", role: $0,
        captureId: capture.captureId, sha256: sha, bytes: 10)
    }
  }

  private func photos(
    _ capture: CaptureRecord.Capture, room: String, subjects: [PhotoSubject], from first: Int = 1
  ) -> [File] {
    subjects.enumerated().map { offset, subject in
      File(
        path: "Site Photos/\(capture.areaKey)/photo-\(first + offset).jpg", role: .photo,
        captureId: capture.captureId, sha256: "p\(first + offset)", bytes: 100,
        photo: .init(room: room, direction: .north, subject: subject, takenAt: Make.t1402))
    }
  }

  private func visitFiles(record: String, controls: String) -> [File] {
    [
      File(path: "Source Register/capture-record.json", role: .captureRecord, sha256: record, bytes: 1),
      File(path: "Field Measurements/field-controls.json", role: .fieldControls, sha256: controls, bytes: 1),
    ]
  }

  /// The drawn Revision 2 (artboard 2f screen 4), with the real counts.
  private func drawn() -> RevisionChanges {
    let baseRecord = Make.record([floor1])
    let base = RevisionChanges.Side(
      revision: 1,
      files: visitFiles(record: "r1", controls: "c1") + captureFiles(floor1, count: 9)
        + photos(floor1, room: "Living room", subjects: Array(repeating: .general, count: 42)),
      record: baseRecord,
      controls: FieldControls(visitId: baseRecord.visitId, ceilingHeights: heights(9, capture: floor1)))
    var draftRecord = baseRecord
    draftRecord.captures.append(closet)
    var controls = base.controls!
    controls.ceilingHeights.append(
      .init(id: "c10", capture: ref(floor1), room: "Room 4", measurement: measurement(2490)))
    let draft = RevisionChanges.Side(
      revision: 2,
      files: visitFiles(record: "r2", controls: "c2") + captureFiles(floor1, count: 9)
        + photos(floor1, room: "Living room", subjects: Array(repeating: .general, count: 42))
        + captureFiles(closet, count: 5)
        + photos(closet, room: "Primary closet", subjects: [.general, .ceiling, .general, .opening], from: 1),
      record: draftRecord, controls: controls)
    return RevisionChanges.make(base: base, draft: draft, baseNextActions: actions)
  }

  func testTheDrawnRows() {
    let changes = drawn()
    XCTAssertEqual(changes.rows.map(\.title), ["Primary closet", "Room 4 ceiling height", "4 photos"])
    XCTAssertEqual(
      changes.rows.map(\.detail),
      [
        "Scanned \u{00B7} one room \u{00B7} 5 files",
        "Field control \u{00B7} \(LengthFormatter.both(2490))",
        "Primary closet \u{00B7} general, ceiling, opening",
      ])
    XCTAssertEqual(changes.rows.map(\.kind), [.added, .added, .added])
    XCTAssertEqual(changes.rows.map(\.subject), [.capture, .fieldControl, .photos])
    XCTAssertEqual(changes.rows.map(\.method), [nil, .tape, nil])
    XCTAssertEqual(changes.rows[0].accessibilityLabel, "Added, Primary closet, Scanned \u{00B7} one room \u{00B7} 5 files")
    XCTAssertEqual(changes.manifestDetail, "53 \u{2192} 62 entries")
    XCTAssertEqual(changes.unchangedTitle, "Floor 1 scan, 42 photos, 9 controls")
    XCTAssertEqual(changes.unchangedSubtitle, "Same fingerprints as revision 1 \u{00B7} not uploaded again")
    XCTAssertEqual(changes.uploadCount, 11, "5 + 4 new, record and controls changed")
    XCTAssertEqual(changes.bytesToUpload, 5 * 10 + 4 * 100 + 2)
    XCTAssertEqual(
      changes.footnote,
      "Only the 11 new or changed files are uploaded. The station checks the whole package and "
        + "issues a new verdict and spatial report.")
    XCTAssertEqual(changes.title, "Revision 2")
    XCTAssertEqual(
      changes.subtitle,
      "You changed the capture after sealing revision 1. Sealing again creates revision 2. "
        + "Revision 1 stays as it was; the station checks revision 2 from the start.")
    XCTAssertEqual(changes.sealButtonTitle, "Seal revision 2 and upload")
  }

  /// Addendum C9: the next action is copied byte for byte (no case or punctuation change).
  func testAnswersNextActionIsTheBaseActionVerbatim() {
    let changes = drawn()
    XCTAssertEqual(changes.rows[0].answersNextAction, actions[0])
    XCTAssertEqual(changes.rows[0].answersNextAction?.utf8.elementsEqual(actions[0].utf8), true)
    XCTAssertEqual(changes.rows[1].answersNextAction, actions[1])
    XCTAssertNil(changes.rows[2].answersNextAction)

    let notice = StationNextRevisionNotices.input(changes.notice(updatedAt: Make.t1402))
    XCTAssertEqual(notice.revision, 2)
    XCTAssertEqual(notice.updatedAt, Make.t1402)
    XCTAssertEqual(notice.changes.map(\.title), changes.rows.map(\.title))
    XCTAssertEqual(notice.changes.map(\.detail), changes.rows.map(\.detail))
    XCTAssertEqual(notice.changes.map(\.kind.rawValue), ["added", "added", "added"])
    XCTAssertEqual(notice.changes.map(\.subject.rawValue), ["capture", "field_control", "photos"])
    XCTAssertEqual(notice.changes[0].answersNextAction, actions[0])
    XCTAssertEqual(notice.changes[1].method, .tape)
  }

  func testRoomNamesChangedControlsAndTheRetiredReport() {
    let record = Make.record([floor1, floor2])
    let distance = FieldControls.Distance(
      id: "d1", capture: ref(floor1), axis: .a, from: "west wall", to: "east wall",
      measurement: measurement(7520, .laser))
    let opening = FieldControls.Opening(
      id: "o1", capture: ref(floor1), room: "Kitchen", label: "Door 1", width: measurement(910))
    let level = FieldControls.FloorToFloor(
      id: "f1", lower: ref(floor1), upper: ref(floor2), location: "stair", measurement: measurement(2950))
    let landmark = FieldControls.Landmark(
      id: "l1", label: "Stair newel post", captures: [ref(floor1), ref(floor2)])
    var baseControls = FieldControls(
      visitId: record.visitId, ceilingHeights: heights(1, capture: floor1))
    var floor1Files = captureFiles(floor1, count: 9)
    floor1Files.append(
      File(
        path: "Original Exports/floor-1/spatial-report.pdf", role: .spatialReportPDF,
        captureId: floor1.captureId, sha256: "s", bytes: 5))
    let base = RevisionChanges.Side(
      revision: 1,
      files: visitFiles(record: "r", controls: "c1") + floor1Files + captureFiles(floor2, count: 9)
        + photos(floor2, room: "Hall", subjects: [.general]),
      record: record, controls: baseControls,
      roomLabels: [
        floor1.captureId: [
          "room-1": "Closet", "room-2": "Bedroom", "room-3": "Hall", "room-10": "Den",
        ]
      ])
    // Floor 1: model and four plans redrawn, the plan PDF under a new name, the phone report
    // retired; four new controls and a changed ceiling height.
    var draftFloor1 = captureFiles(floor1, count: 9).filter { $0.role != .planPDF }.map { file -> File in
      var changed = file
      if [.captureModel, .planDXF, .roomsCSV, .planPNG, .planSVG].contains(file.role) {
        changed.sha256 = "b"
      }
      return changed
    }
    draftFloor1.append(
      File(
        path: "Original Exports/floor-1/plan-sheet.pdf", role: .planPDF,
        captureId: floor1.captureId, sha256: "b", bytes: 10))
    baseControls.ceilingHeights[0].measurement = measurement(2410)
    baseControls.distances = [distance]
    baseControls.openings = [opening]
    baseControls.floorToFloor = [level]
    baseControls.landmarks = [landmark]
    let draft = RevisionChanges.Side(
      revision: 2,
      files: visitFiles(record: "r", controls: "c2") + draftFloor1 + captureFiles(floor2, count: 9)
        + photos(floor2, room: "Hall", subjects: [.general]),
      record: record, controls: baseControls,
      roomLabels: [
        floor1.captureId: [
          "room-1": "Shower", "room-2": "Primary bedroom", "room-3": "Hallway", "room-10": "Den",
        ]
      ])
    let changes = RevisionChanges.make(base: base, draft: draft)
    XCTAssertEqual(
      changes.rows.map(\.title),
      [
        "Floor 1 room names", "Floor 1 long distance A", "Room 1 ceiling height",
        "Kitchen Door 1 width", "Floor to floor, Floor 1 to Floor 2", "Landmark Stair newel post",
        "Spatial report PDF from the phone",
      ])
    XCTAssertEqual(
      changes.rows.map(\.detail),
      [
        "Closet \u{2192} Shower, Bedroom \u{2192} Primary bedroom, +1 more \u{00B7} 7 files",
        "Field control \u{00B7} \(LengthFormatter.both(7520))",
        "Field control \u{00B7} changed to \(LengthFormatter.both(2410))",
        "Field control \u{00B7} \(LengthFormatter.both(910))",
        "Field control \u{00B7} \(LengthFormatter.both(2950))",
        "Field control \u{00B7} 2 floors",
        "Retired \u{00B7} the station makes the spatial report \u{00B7} 1 file",
      ])
    XCTAssertEqual(
      changes.rows.map(\.kind), [.changed, .added, .changed, .added, .added, .added, .removed])
    XCTAssertEqual(
      changes.rows.map(\.subject),
      [.roomNames, .fieldControl, .fieldControl, .fieldControl, .fieldControl, .fieldControl, .retiredFile])
    XCTAssertEqual(changes.rows[1].method, .laser)
    XCTAssertEqual(changes.rows[0].accessibilityLabel.prefix(8), "Changed,")
    XCTAssertEqual(changes.rows[6].accessibilityLabel.prefix(8), "Removed,")
    XCTAssertEqual(
      Set(changes.removedPaths),
      ["Original Exports/floor-1/plan_pdf", "Original Exports/floor-1/spatial-report.pdf"])
    XCTAssertEqual(changes.unchangedTitle, "Floor 2 scan, 1 photo", "no control unchanged")
  }

  func testUnchangedJoinsAndFootnotes() {
    func changes(captures: [String], photos: Int, controls: Int, added: Int, changed: Int)
      -> RevisionChanges
    {
      RevisionChanges(
        baseRevision: 1, revision: 2, rows: [], addedPaths: (0..<added).map { "a\($0)" },
        changedPaths: (0..<changed).map { "c\($0)" }, unchangedPaths: [], removedPaths: [],
        bytesToUpload: 0, baseEntries: 1, draftEntries: 1,
        unchanged: .init(captureLabels: captures, photos: photos, controls: controls))
    }
    XCTAssertEqual(
      changes(captures: ["Floor 1", "Floor 2"], photos: 1, controls: 0, added: 8, changed: 0)
        .unchangedTitle, "Floor 1 and Floor 2 scans, 1 photo")
    XCTAssertEqual(
      changes(captures: ["A", "B", "C"], photos: 0, controls: 1, added: 1, changed: 0).unchangedTitle,
      "A, B and C scans, 1 control")
    XCTAssertEqual(
      changes(captures: [], photos: 3, controls: 2, added: 1, changed: 0).unchangedTitle,
      "3 photos, 2 controls")
    XCTAssertNil(changes(captures: [], photos: 0, controls: 0, added: 1, changed: 0).unchangedTitle)

    let tail = " The station checks the whole package and issues a new verdict and spatial report."
    XCTAssertEqual(
      changes(captures: [], photos: 0, controls: 0, added: 8, changed: 0).footnote,
      "Only the 8 new files are uploaded." + tail)
    XCTAssertEqual(
      changes(captures: [], photos: 0, controls: 0, added: 1, changed: 0).footnote,
      "Only the 1 new file is uploaded." + tail)
    XCTAssertEqual(
      changes(captures: [], photos: 0, controls: 0, added: 0, changed: 1).footnote,
      "Only the 1 new or changed file is uploaded." + tail)
    XCTAssertEqual(
      changes(captures: [], photos: 0, controls: 0, added: 6, changed: 2).footnote,
      "Only the 8 new or changed files are uploaded." + tail)
  }

  func testNothingChanged() {
    let record = Make.record([floor1])
    let side = RevisionChanges.Side(
      revision: 1, files: visitFiles(record: "r", controls: "c") + captureFiles(floor1, count: 9),
      record: record, controls: FieldControls(visitId: record.visitId))
    var next = side
    next.revision = 2
    let changes = RevisionChanges.make(base: side, draft: next)
    XCTAssertTrue(changes.rows.isEmpty)
    XCTAssertTrue(changes.hasNoChanges)
    XCTAssertEqual(changes.sealButtonTitle, "No changes to seal")
    XCTAssertEqual(changes.nothingChangedText, "Nothing changed since revision 1.")
    XCTAssertEqual(changes.manifestDetail, "11 \u{2192} 11 entries")
    XCTAssertEqual(changes.unchangedTitle, "Floor 1 scan")
  }
}

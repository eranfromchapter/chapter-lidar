#if canImport(UIKit) && os(iOS)
  import CaptureContract
  import FieldKitUI
  import FieldRules
  import Foundation
  import PhotoStore
  import SwiftUI

  /// The states of artboard 2d (app-field-v2) as data: 618 Valley Street, two floors, Floor 1
  /// with Kitchen, Living, Bath 1, Bedroom 1 and more rooms.
  enum SnapshotFixtures {
    static let visitId = LowercaseUUID(rawValue: "7c4e1b9a-2d3f-4a68-9b5c-e0f1a2b3c4d5")!
    static let floor1 = FieldControls.CaptureRef(
      captureId: LowercaseUUID(rawValue: "3f6c2a9e-8b1d-4c57-9e2a-6d4b1f0c7a35")!, areaKey: "floor-1")
    static let floor2 = FieldControls.CaptureRef(
      captureId: LowercaseUUID(rawValue: "a81d5f03-6c2e-4b97-8d14-2f9e7b3c5a60")!, areaKey: "floor-2")
    static let t0 = UTCTimestamp(rawValue: "2026-10-21T15:02:00Z")!
    static let t1 = UTCTimestamp(rawValue: "2026-10-21T16:10:00Z")!
    /// 12:41 in New York.
    static let shutter = UTCTimestamp(rawValue: "2026-10-21T16:41:00Z")!
    static let newYork = TimeZone(identifier: "America/New_York")!

    static let floor1Rooms = [
      "Kitchen", "Living", "Bath 1", "Bedroom 1", "Bath 2", "Bedroom 2", "Primary closet",
    ]
    static let floor2Rooms = ["Bath 2", "Bedroom 3"]

    // MARK: Photos

    /// A JPEG-shaped file (not a decodable image: the photo shows its placeholder, as drawn).
    static func jpeg(_ seed: UInt8) -> Data {
      var bytes: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE1, 0x00, 0x08] + Array("Exif".utf8) + [0, 0]
      bytes += (0..<64).map { UInt8(truncatingIfNeeded: Int($0) &* 7 &+ Int(seed)) }
      return Data(bytes + [0xFF, 0xD9])
    }

    /// A HEIC-shaped file: `HEIC` in the bar, the placeholder on screen.
    static func heic() -> Data {
      var bytes: [UInt8] = [0x00, 0x00, 0x00, 0x18] + Array("ftypheic".utf8)
      bytes += [0x00, 0x00, 0x00, 0x00] + Array("mif1heic".utf8)
      bytes += (0..<120).map { UInt8(truncatingIfNeeded: Int($0) &* 13 &+ 5) }
      return Data(bytes)
    }

    static func capture(
      _ ref: FieldControls.CaptureRef, _ label: String, at time: UTCTimestamp, rooms: [String],
      scan: ScanMeasurements? = nil
    ) -> FieldCaptureOption {
      FieldCaptureOption(
        ref: ref, label: label, mode: .floor, capturedAt: time, rooms: rooms, scan: scan)
    }

    /// 13 photos of Floor 1, 4 of them of the Kitchen (the last one): the next is Photo 14.
    static func photoStore() throws -> PhotoRecordStore {
      let store = try PhotoRecordStore(files: InMemoryPhotoFileStore())
      let rooms = [
        "Living", "Kitchen", "Bath 1", "Bedroom 1", "Kitchen", "Living", "Bedroom 2", "Bath 1",
        "Kitchen", "Primary closet", "Bedroom 1", "Living", "Kitchen",
      ]
      for (index, room) in rooms.enumerated() {
        _ = try store.save(
          original: jpeg(UInt8(index)), capture: floor1,
          labels: PackageManifest.PhotoLabels(
            room: room, direction: .north, subject: .general, takenAt: t0,
            directionSource: .manual))
      }
      return store
    }

    /// "Label a photo" after the shutter: Photo 14 of Floor 1, HEIC, 12:41, Kitchen kept from the
    /// last photo, the compass's E (85° ±8° true) or no reading, Cabinetry chosen when `subject`.
    @MainActor static func labelingModel(compass: Bool, subject: Bool) async throws -> PhotoLabelingModel {
      let shutterDate = shutter.date
      let model = PhotoLabelingModel(
        capture: capture(floor1, "Floor 1", at: t0, rooms: floor1Rooms),
        store: try photoStore(),
        heading: FixedPhotoHeading(
          azimuthDegrees: compass ? 85 : nil, accuracyDegrees: 8, now: { shutterDate }),
        capturePhoto: { heic() },
        now: { shutter }, date: { shutterDate }, timeZone: newYork)
      await model.takePhoto()
      if subject { model.chooseSubject(.cabinetry) }
      return model
    }

    // MARK: Field controls

    static let scan1 = ScanMeasurements(
      distanceAMm: 7512, distanceBMm: 11236,
      ceilingHeights: [
        .init(room: "Kitchen", heightMm: 2700), .init(room: "Living", heightMm: 2745),
        .init(room: "Bath 1", heightMm: 2690),
      ], doors: 6, windows: 9, openings: 2)
    static let scan2 = ScanMeasurements(
      distanceAMm: 6100, distanceBMm: 8420,
      ceilingHeights: [.init(room: "Bath 2", heightMm: 2440), .init(room: "Bedroom 3", heightMm: 2440)],
      doors: 3, windows: 4, openings: 0)

    static func captures(withScan: Bool) -> [FieldCaptureOption] {
      [
        capture(floor1, "Floor 1", at: t0, rooms: floor1Rooms, scan: withScan ? scan1 : nil),
        capture(floor2, "Floor 2", at: t1, rooms: floor2Rooms, scan: withScan ? scan2 : nil),
      ]
    }

    static func measurement(_ text: String, _ unit: EnteredUnit) throws -> FieldControls.Measurement {
      try FieldMeasurement.make(text: text, unit: unit, method: .tape, recordedAt: t0)
    }

    /// Artboard 2d-2: Floor 1 A 7,520 / B 11,240 / 3 ceiling heights 2,690–2,740 / 2 openings;
    /// one shared landmark; nothing on Floor 2.
    static func artboardControls() throws -> FieldControls {
      var editor = FieldControlsEditor(visitId: visitId)
      try editor.setDistance(
        capture: floor1, axis: .a, from: "Kitchen east wall", to: "living west wall",
        measurement: measurement("7520", .mm))
      try editor.setDistance(
        capture: floor1, axis: .b, from: "Entry", to: "rear wall",
        measurement: measurement("11240", .mm))
      for (room, height) in [("Kitchen", "2690"), ("Living", "2740"), ("Bath 1", "2700")] {
        try editor.setCeilingHeight(capture: floor1, room: room, measurement: measurement(height, .mm))
      }
      try editor.setOpening(
        capture: floor1, room: "Kitchen", label: "Entry door", width: measurement("36", .inches))
      try editor.setOpening(
        capture: floor1, room: "Living", label: "Patio door", width: measurement("72", .inches))
      try editor.setLandmark(label: "Stair newel post", captures: [floor1, floor2])
      return editor.controls
    }

    @MainActor static func controlsModel(
      policy: ChecklistPolicy, withScan: Bool, isReadOnly: Bool = false
    ) throws -> FieldControlsModel {
      FieldControlsModel(
        captures: captures(withScan: withScan), controls: try artboardControls(), policy: policy,
        isReadOnly: isReadOnly, sealedRevision: 1, persist: { _ in },
        now: { t1 })
    }

    // MARK: Before you leave

    static func record(compassOnFloor2: Bool) -> CaptureRecord {
      var floor1Capture = CaptureRecord.Capture(
        captureId: floor1.captureId, areaKey: "floor-1", label: "Floor 1", mode: .floor,
        units: CaptureRecord.Units(display: .imperial), capturedAt: t0,
        inaccessibleRooms: [CaptureRecord.RoomNote(name: "Primary closet", reason: "locked")])
      floor1Capture.setCompass(
        .reading(heading: 212.4, accuracy: 8, source: .trueNorth, recordedAt: t0))
      var floor2Capture = CaptureRecord.Capture(
        captureId: floor2.captureId, areaKey: "floor-2", label: "Floor 2", mode: .floor,
        units: CaptureRecord.Units(display: .imperial), capturedAt: t1)
      if compassOnFloor2 {
        floor2Capture.setCompass(
          .reading(heading: 212.9, accuracy: 6, source: .trueNorth, recordedAt: t1))
      }
      return CaptureRecord(
        visitId: visitId,
        hub: CaptureRecord.HubProject(dealId: "4821", projectName: "618 Valley Street"),
        address: CaptureRecord.Address(
          formatted: "618 Valley Street, Philadelphia, PA 19123", confirmedOnSite: true,
          confirmedAt: t0),
        operator: CaptureRecord.Operator(name: "Dana Ruiz"),
        device: CaptureRecord.Device(
          model: "iPhone18,1", osName: .iOS, osVersion: "27.2", hasLidar: true),
        app: CaptureRecord.AppInfo(version: "2.0.0", build: "1"),
        visitedAt: t0, captures: [floor1Capture, floor2Capture])
    }

    static func photo(_ ref: FieldControls.CaptureRef, _ room: String, _ sequence: Int)
      -> PhotoRecord
    {
      PhotoRecord(
        captureId: ref.captureId, areaKey: ref.areaKey, sequence: sequence,
        path: "Site Photos/\(ref.areaKey)/\(ref.captureId.rawValue)/photo-\(sequence).jpg",
        format: .jpeg, sha256: String(repeating: "0", count: 64), bytes: 10,
        labels: PackageManifest.PhotoLabels(
          room: room, direction: .north, subject: .general, takenAt: t0))
    }

    /// Artboard 2d-4: Bath 2 without a photo, Floor 2's controls missing, Floor 2 not read.
    static func failingReport() throws -> ChecklistReport {
      var photos = floor1Rooms.enumerated().map { photo(floor1, $0.element, $0.offset + 1) }
      photos.append(photo(floor2, "Bedroom 3", 1))
      return ChecklistRules.evaluate(
        ChecklistInput(
          record: record(compassOnFloor2: false),
          capturedRooms: [floor1.captureId: floor1Rooms, floor2.captureId: floor2Rooms],
          photos: photos, controls: try artboardControls()),
        policy: .manualControls)
    }

    /// Everything recorded, both floors verified.
    static func passingReport() throws -> ChecklistReport {
      var editor = FieldControlsEditor(controls: try artboardControls())
      try editor.setDistance(
        capture: floor2, axis: .a, from: "Bedroom 3 north wall", to: "bath south wall",
        measurement: measurement("20' 1\"", .ftIn))
      try editor.setDistance(
        capture: floor2, axis: .b, from: "Stair", to: "rear wall",
        measurement: measurement("27' 7.5\"", .ftIn))
      try editor.setCeilingHeight(
        capture: floor2, room: "Bedroom 3", measurement: measurement("8' 0\"", .ftIn))
      try editor.setFloorToFloor(
        lower: floor1, upper: floor2, location: "At the stair",
        measurement: measurement("10' 0.5\"", .ftIn))
      try editor.setLandmark(label: "Chimney chase", captures: [floor1, floor2])
      var photos = floor1Rooms.enumerated().map { photo(floor1, $0.element, $0.offset + 1) }
      photos += floor2Rooms.enumerated().map { photo(floor2, $0.element, $0.offset + 1) }
      return ChecklistRules.evaluate(
        ChecklistInput(
          record: record(compassOnFloor2: true),
          capturedRooms: [floor1.captureId: floor1Rooms, floor2.captureId: floor2Rooms],
          photos: photos, controls: editor.controls),
        policy: .manualControls)
    }

    // MARK: Rename rooms

    static func roomNamingDraft() -> RoomNamingDraft {
      let rooms = [
        RoomNamingDraft.Room(
          captureId: floor1.captureId, roomId: "room-1", scannedLabel: "Closet",
          currentLabel: "Closet", detail: "1.9 m\u{00B2}", needsPhoto: true),
        RoomNamingDraft.Room(
          captureId: floor1.captureId, roomId: "room-2", scannedLabel: "Kitchen",
          currentLabel: "Kitchen", detail: "14.2 m\u{00B2}"),
        RoomNamingDraft.Room(
          captureId: floor1.captureId, roomId: "room-3", scannedLabel: "Living room",
          currentLabel: "Living", detail: "24.6 m\u{00B2}"),
      ]
      return RoomNamingDraft(
        captures: [RoomNamingDraft.Capture(captureId: floor1.captureId, label: "Floor 1", rooms: rooms)],
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
    }
  }

  /// A screen pushed onto a navigation stack, as the app shows it (system back button).
  struct Pushed<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
      NavigationStack(path: .constant([1])) {
        Color.clear
          .navigationDestination(for: Int.self) { _ in content }
      }
    }
  }
#endif

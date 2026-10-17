#if canImport(RoomPlan) && canImport(ARKit) && os(iOS)
  import CaptureContract
  import CaptureCore
  import CaptureModelMapping
  import Foundation
  import RoomPlan

  /// RoomPlan types into the contract. The only Apple-specific step is encoding the RoomPlan value
  /// with its own Codable; everything after that is `CaptureModelMapping`, which also runs on Linux.
  public enum RoomPlanAdapter {
    /// `CapturedRoom` JSON as RoomPlan encodes it. These bytes are the raw original and are
    /// written unchanged.
    public static func encode(_ room: CapturedRoom) throws -> Data {
      try JSONEncoder().encode(room)
    }

    /// `CapturedStructure` JSON as RoomPlan encodes it.
    public static func encode(_ structure: CapturedStructure) throws -> Data {
      try JSONEncoder().encode(structure)
    }

    public static func document(_ room: CapturedRoom) throws -> RoomPlanDocument {
      try RoomPlanDocument.decode(from: try encode(room))
    }

    public static func document(_ structure: CapturedStructure) throws -> RoomPlanDocument {
      try RoomPlanDocument.decode(from: try encode(structure))
    }

    public static func captureModel(_ room: CapturedRoom, context: MappingContext) throws -> CaptureModel {
      try CaptureModelMapper.map(try document(room), context: context)
    }

    public static func captureModel(_ structure: CapturedStructure, context: MappingContext) throws
      -> CaptureModel
    {
      try CaptureModelMapper.map(try document(structure), context: context)
    }

    /// Live counts of a room that is still being scanned.
    nonisolated static func counts(of room: CapturedRoom) -> ScanCounts {
      ScanCounts(
        walls: room.walls.count, doors: room.doors.count, windows: room.windows.count,
        rooms: room.walls.isEmpty ? 0 : 1, openings: room.openings.count, objects: room.objects.count)
    }
  }
#endif

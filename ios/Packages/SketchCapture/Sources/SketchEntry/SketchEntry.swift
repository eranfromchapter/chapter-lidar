#if canImport(Observation)
  import CaptureContract
  import Foundation
  import Observation
  import SketchSolver

  /// Where the sketch flow stands after step 1 (spec F14 2.4). Step 1, New capture, is the
  /// capture screens' own (`CaptureFlowModel`); the host moves to `.source` when it continues.
  public enum SketchEntryStep: Sendable, Equatable {
    /// Step 2 of 4: What are you drawing from?
    case source
    /// Step 3 of 4: Rooms and measurements.
    case rooms
    /// Step 4 of 4: Check.
    case check
    case finished
  }

  /// A wall of an earlier room the operator can mark the current room's wall as sharing.
  public struct SketchSharedWallChoice: Hashable, Sendable, Identifiable {
    public var roomId: String
    public var roomName: String
    public var wallId: String
    public var wallTitle: String

    public var id: String { "\(roomId)/\(wallId)" }
    public var shared: SketchMeasurements.SharedWall {
      SketchMeasurements.SharedWall(roomId: roomId, wallId: wallId)
    }
    /// "Bedroom · Wall 4".
    public var title: String { "\(roomName) \u{00B7} \(wallTitle)" }
  }

  /// State and actions behind the sketch screens (What are you drawing from?, Rooms and
  /// measurements, Check): the sketch image, the rooms with their walls, diagonals and
  /// openings, the floor's ceiling height, and the solver's result. The screens only read this
  /// and call its methods, so the guided entry runs in tests without a view.
  ///
  /// It asks for exactly the required set of spec F14 1.6 (`missingRequired`, in the order the
  /// screens ask) and offers the recommended items as "Also measured" rows; it never blocks on
  /// a missing number (the solver estimates and marks it). Ids are `room-N`, `wall-N`,
  /// `door-N`, `window-N` and `opening-N`, numbered across the capture, never reused.
  @MainActor
  @Observable
  public final class SketchEntryModel {
    public private(set) var step: SketchEntryStep = .source
    public let visitId: LowercaseUUID
    public let captureId: LowercaseUUID

    /// The floor or area name ("Floor 1") and what is drawn (one room or the whole floor): the
    /// capture record's label and mode, entered on the source screen as step 2 of a scan has
    /// them. The host copies them into its `CaptureRecordDraft` at Finish floor.
    public var floorLabel: String
    public var mode: CaptureMode?
    /// Imperial (feet and inches, inches) or metric (millimetres): the units new fields take
    /// (`setDisplayUnits`).
    public private(set) var displayUnits: DisplayUnitSystem
    public var units: SketchUnits { SketchUnits(display: displayUnits) }
    /// Area keys already captured in this visit: Continue refuses a name whose key is one.
    public var existingAreaKeys: Set<String>

    /// The sketch image, nil for "No sketch" (measurements only); set with `setImage`.
    public private(set) var image: SketchImageSelection?
    /// What the image is; `none` exactly when there is no image.
    public private(set) var sourceKind: SketchSourceKind = .none
    /// The floor's ceiling height, used by every room without its own.
    public var ceilingHeight: SketchLengthField
    public private(set) var rooms: [SketchRoomDraft] = []

    /// The solver's result for the measurements as they are; nil before the first solve, or
    /// when it failed (`solveError`).
    public private(set) var result: SketchSolveResult?
    public private(set) var solveError: String?
    /// Finish floor is writing the originals.
    public var isFinishing = false

    @ObservationIgnored private var nextNumber: [String: Int] = [:]
    @ObservationIgnored private let areaKeyRule: @Sendable (String) -> String?

    /// `areaKey` turns the floor label into its path-safe key (the host passes
    /// `CaptureRecordDraft.areaKey(for:)`, so the key is the capture record's).
    public init(
      visitId: LowercaseUUID = LowercaseUUID(), captureId: LowercaseUUID = LowercaseUUID(),
      floorLabel: String = "Floor 1", mode: CaptureMode? = nil,
      displayUnits: DisplayUnitSystem = .imperial, existingAreaKeys: Set<String> = [],
      areaKey: @escaping @Sendable (String) -> String? = SketchEntryModel.simpleAreaKey
    ) {
      self.visitId = visitId
      self.captureId = captureId
      self.floorLabel = floorLabel
      self.mode = mode
      self.displayUnits = displayUnits
      self.existingAreaKeys = existingAreaKeys
      self.areaKeyRule = areaKey
      self.ceilingHeight = SketchLengthField(unit: SketchUnits(display: displayUnits).long)
    }

    /// Lowercase letters and digits joined by hyphens ("Floor 1" → "floor-1"), the capture
    /// record's rule in its simplest form; the host injects the record's own.
    public static let simpleAreaKey: @Sendable (String) -> String? = { label in
      var key = ""
      var pendingHyphen = false
      for scalar in label.lowercased().unicodeScalars {
        let isDigit = scalar.value >= 0x30 && scalar.value <= 0x39
        let isLetter = scalar.value >= 0x61 && scalar.value <= 0x7A
        if isDigit || isLetter {
          if pendingHyphen && !key.isEmpty { key.append("-") }
          pendingHyphen = false
          key.unicodeScalars.append(scalar)
        } else {
          pendingHyphen = true
        }
      }
      return key.isEmpty ? nil : String(key.prefix(64))
    }

    // MARK: Step 2: source

    /// The sketch image (`kind` says whether it is a hand sketch or an existing plan), or nil
    /// for "No sketch".
    public func setImage(_ selection: SketchImageSelection?, kind: SketchSourceKind = .handSketch) {
      image = selection
      sourceKind = selection == nil ? .none : (kind == .none ? .handSketch : kind)
    }

    /// Hand sketch or existing plan; ignored without an image.
    public func setSourceKind(_ kind: SketchSourceKind) {
      guard image != nil, kind != .none else { return }
      sourceKind = kind
    }

    /// Changes the unit system: fields not typed yet take the new units; a typed field keeps
    /// its unit (nothing is converted silently).
    public func setDisplayUnits(_ display: DisplayUnitSystem) {
      guard display != displayUnits else { return }
      displayUnits = display
      let units = self.units
      if ceilingHeight.isEmpty { ceilingHeight = ceilingHeight.cleared(unit: units.long) }
      for room in rooms.indices {
        if rooms[room].ceilingHeight.isEmpty {
          rooms[room].ceilingHeight = rooms[room].ceilingHeight.cleared(unit: units.long)
        }
        for wall in rooms[room].walls.indices where rooms[room].walls[wall].length.isEmpty {
          rooms[room].walls[wall].length = rooms[room].walls[wall].length.cleared(unit: units.long)
        }
        for diagonal in rooms[room].diagonals.indices
        where rooms[room].diagonals[diagonal].length.isEmpty {
          rooms[room].diagonals[diagonal].length =
            rooms[room].diagonals[diagonal].length.cleared(unit: units.long)
        }
        for opening in rooms[room].openings.indices {
          for path in [\SketchOpeningDraft.width, \.height, \.sill, \.fromCornerDistance]
          where rooms[room].openings[opening][keyPath: path].isEmpty {
            rooms[room].openings[opening][keyPath: path] =
              rooms[room].openings[opening][keyPath: path].cleared(unit: units.short)
          }
        }
      }
    }

    /// The capture's area key from its label; nil when the label has no letters or digits.
    public var areaKey: String? {
      areaKeyRule(floorLabel.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Why Continue is disabled on the source screen, as its label says it; nil when enabled.
    public var sourceBlocker: String? {
      let label = floorLabel.trimmingCharacters(in: .whitespacesAndNewlines)
      if label.isEmpty { return "Enter the floor or area" }
      guard let key = areaKey else { return "Use letters or numbers in the name" }
      if existingAreaKeys.contains(key) { return "\(label) is already captured. Use another name" }
      if mode == nil { return "Choose what you are drawing" }
      return nil
    }

    public var canContinueToRooms: Bool { sourceBlocker == nil }

    /// The source screen's button: the blocker, else "Continue".
    public var sourceContinueTitle: String { sourceBlocker ?? "Continue" }

    public func continueToRooms() {
      guard canContinueToRooms else { return }
      if rooms.isEmpty { _ = addRoom() }
      step = .rooms
    }

    public func backToSource() {
      if step == .rooms { step = .source }
    }

    /// Package path of the sketch image once written: `Original Exports/{areaKey}/{captureId}/
    /// sketch.jpg`; nil without an image.
    public var sourcePath: String? {
      guard let image else { return nil }
      return SketchFloorWriter.packageFolder(areaKey: areaKey ?? "area", captureId: captureId)
        + image.fileName
    }

    // MARK: Step 3: rooms

    /// A new rectangle with four walls, at the end of the list. Returns its id.
    @discardableResult
    public func addRoom() -> String {
      let id = nextId("room")
      let walls = (0..<4).map { _ in newWall(turn: .left) }
      rooms.append(
        SketchRoomDraft(
          id: id, walls: walls, ceilingHeight: SketchLengthField(unit: units.long)))
      return id
    }

    /// Removes the room; later rooms that shared a wall with it no longer do.
    public func removeRoom(_ roomId: String) {
      rooms.removeAll { $0.id == roomId }
      for index in rooms.indices {
        for wall in rooms[index].walls.indices
        where rooms[index].walls[wall].sharedWith?.roomId == roomId {
          rooms[index].walls[wall].sharedWith = nil
        }
      }
    }

    public func room(_ roomId: String) -> SketchRoomDraft? {
      rooms.first { $0.id == roomId }
    }

    /// 1-based position of the room in the list, for "Room N".
    public func position(of roomId: String) -> Int {
      (rooms.firstIndex { $0.id == roomId } ?? 0) + 1
    }

    public func displayName(of roomId: String) -> String {
      room(roomId)?.displayName(position: position(of: roomId)) ?? roomId
    }

    /// Changes one room in place (the screens' bindings go through here).
    public func update(_ roomId: String, _ change: (inout SketchRoomDraft) -> Void) {
      guard let index = rooms.firstIndex(where: { $0.id == roomId }) else { return }
      change(&rooms[index])
    }

    /// Sets the shape: the walls are rebuilt to its count (the first ones keep what was entered,
    /// new ones get new ids) and the turns the shape fixes are applied. Openings in a wall that
    /// went away are dropped, as are diagonals past the new corners.
    public func setShape(_ roomId: String, _ shape: SketchRoomShape) {
      guard let index = rooms.firstIndex(where: { $0.id == roomId }) else { return }
      var room = rooms[index]
      room.shape = shape
      let count = shape.wallCount
      if room.walls.count > count {
        room.walls.removeLast(room.walls.count - count)
      }
      while room.walls.count < count {
        room.walls.append(newWall(turn: .left))
      }
      for wall in room.walls.indices {
        if let fixed = shape.fixedTurn(atEndOfWall: wall) {
          room.walls[wall].turn = fixed
        } else if room.walls[wall].turn == .unsquare, room.allCornersSquare {
          room.walls[wall].turn = .left
        }
      }
      let wallIds = Set(room.walls.map(\.id))
      room.openings.removeAll { !wallIds.contains($0.wallId) }
      room.diagonals.removeAll { $0.from >= count || $0.to >= count }
      rooms[index] = room
    }

    /// "Are all corners square?" Yes puts every corner back to the turn its shape fixes.
    public func setAllCornersSquare(_ roomId: String, _ square: Bool) {
      update(roomId) { room in
        room.allCornersSquare = square
        guard square else { return }
        for wall in room.walls.indices where room.walls[wall].turn == .unsquare {
          room.walls[wall].turn = room.shape.fixedTurn(atEndOfWall: wall) ?? .left
        }
      }
    }

    /// The turn at the end of a wall (corners not all square, or the "other" shape).
    public func setTurn(_ roomId: String, wallIndex: Int, _ turn: SketchTurn) {
      update(roomId) { room in
        guard room.walls.indices.contains(wallIndex) else { return }
        room.walls[wallIndex].turn = turn
      }
    }

    /// The walls of the rooms before `roomId` this room's wall can share.
    public func sharedWallChoices(for roomId: String) -> [SketchSharedWallChoice] {
      guard let index = rooms.firstIndex(where: { $0.id == roomId }) else { return [] }
      return rooms[..<index].enumerated().flatMap { position, room in
        room.walls.enumerated().map { wallIndex, wall in
          SketchSharedWallChoice(
            roomId: room.id, roomName: room.displayName(position: position + 1),
            wallId: wall.id, wallTitle: SketchText.wallTitle(index: wallIndex))
        }
      }
    }

    public func setSharedWall(
      _ roomId: String, wallId: String, _ shared: SketchMeasurements.SharedWall?
    ) {
      update(roomId) { room in
        guard let wall = room.walls.firstIndex(where: { $0.id == wallId }) else { return }
        room.walls[wall].sharedWith = shared
      }
    }

    /// The diagonal between two corners, empty when none was entered yet.
    public func diagonal(_ roomId: String, from: Int, to: Int) -> SketchLengthField {
      room(roomId)?.diagonal(from: from, to: to)?.length ?? SketchLengthField(unit: units.long)
    }

    public func setDiagonal(_ roomId: String, from: Int, to: Int, _ field: SketchLengthField) {
      update(roomId) { room in
        if let index = room.diagonals.firstIndex(where: {
          ($0.from == from && $0.to == to) || ($0.from == to && $0.to == from)
        }) {
          room.diagonals[index].length = field
        } else {
          room.diagonals.append(SketchDiagonalDraft(from: from, to: to, length: field))
        }
      }
    }

    /// A new opening in `wallId` of the room, measured from the wall's start. Returns its id.
    @discardableResult
    public func addOpening(_ roomId: String, kind: SketchOpeningKind, wallId: String) -> String {
      let id = nextId(kind.rawValue)
      update(roomId) { room in
        room.openings.append(SketchOpeningDraft(id: id, kind: kind, wallId: wallId, units: units))
      }
      return id
    }

    public func removeOpening(_ roomId: String, _ openingId: String) {
      update(roomId) { room in room.openings.removeAll { $0.id == openingId } }
    }

    public func updateOpening(
      _ roomId: String, _ openingId: String, _ change: (inout SketchOpeningDraft) -> Void
    ) {
      update(roomId) { room in
        guard let index = room.openings.firstIndex(where: { $0.id == openingId }) else { return }
        change(&room.openings[index])
      }
    }

    /// The rooms screen's button leads to Check once there is a room; the check never blocks
    /// on a missing number.
    public var canContinueToCheck: Bool { !rooms.isEmpty }

    public func continueToCheck() {
      guard canContinueToCheck else { return }
      step = .check
      _ = solve()
    }

    public func backToRooms() {
      if step == .check { step = .rooms }
    }

    // MARK: Required set (spec F14 1.6)

    /// What the required set still lacks, in the order the screens ask: the ceiling height,
    /// then per room its name, the walls (at most one unmeasured per axis), the diagonal of
    /// each unsquare corner, and per opening its width, its distance from the corner and, for a
    /// window, its sill and height. Empty when the model will be complete.
    public var missingRequired: [String] {
      var missing: [String] = []
      if !ceilingHeight.isEntered, rooms.contains(where: { !$0.ceilingHeight.isEntered }) {
        missing.append("Ceiling height")
      }
      if rooms.isEmpty { missing.append("At least one room") }
      for (index, room) in rooms.enumerated() {
        let name = room.displayName(position: index + 1)
        if room.cleanedLabel.isEmpty { missing.append("\(name): name") }
        let walls = room.wallsStillRequired
        if !walls.isEmpty {
          let titles = walls.compactMap { wall in
            room.walls.firstIndex { $0.id == wall.id }.map { SketchText.wallTitle(index: $0) }
          }
          missing.append(
            "\(name): \(walls.count) more wall \(walls.count == 1 ? "length" : "lengths")"
              + " (\(titles.joined(separator: ", ")))")
        }
        for corner in room.unsquareCorners {
          guard let pair = room.diagonalCorners(across: corner) else { continue }
          if !(room.diagonal(from: pair.from, to: pair.to)?.length.isEntered ?? false) {
            missing.append(
              "\(name): diagonal across \(SketchText.cornerTitle(index: corner).lowercased())")
          }
        }
        for opening in room.openings {
          if !opening.width.isEntered { missing.append("\(name): \(opening.title) width") }
          if !opening.fromCornerDistance.isEntered {
            missing.append("\(name): \(opening.title) distance from the corner")
          }
          if opening.kind == .window {
            if !opening.sill.isEntered { missing.append("\(name): \(opening.title) sill height") }
            if !opening.height.isEntered { missing.append("\(name): \(opening.title) height") }
          }
        }
      }
      return missing
    }

    // MARK: The document and the solver

    /// What the operator entered, as `sketch-measurements.json` carries it: lengths that parse,
    /// turns other than left, exterior walls, shared walls, the diagonals and openings that have
    /// a value. Unchanged by the solver.
    public var measurements: SketchMeasurements {
      SketchMeasurements(
        visitId: visitId, captureId: captureId, areaKey: areaKey ?? "area",
        displayUnits: displayUnits,
        source: SketchMeasurements.Source(kind: image == nil ? .none : sourceKind, path: sourcePath),
        ceilingHeight: ceilingHeight.length,
        rooms: rooms.enumerated().map { index, room in
          SketchMeasurements.Room(
            id: room.id, label: room.displayName(position: index + 1), type: room.type,
            walls: room.walls.map { wall in
              SketchMeasurements.Wall(
                id: wall.id, length: wall.length.length,
                turn: wall.turn == .left ? nil : wall.turn,
                exterior: wall.isExterior ? true : nil, sharedWith: wall.sharedWith)
            },
            diagonals: room.diagonals.compactMap { diagonal in
              diagonal.length.length.map {
                SketchMeasurements.Diagonal(from: diagonal.from, to: diagonal.to, length: $0)
              }
            },
            openings: room.openings.map { opening in
              SketchMeasurements.Opening(
                id: opening.id, kind: opening.kind, wallId: opening.wallId,
                width: opening.width.length, height: opening.height.length,
                sill: opening.kind == .window ? opening.sill.length : nil,
                fromCorner: opening.fromCorner,
                fromCornerDistance: opening.fromCornerDistance.length)
            },
            ceilingHeight: room.ceilingHeight.length)
        })
    }

    /// Runs the solver on the measurements as they are. Nil (and `solveError` set) when it
    /// refuses them or is not built yet; the result is kept for the Check screen either way.
    @discardableResult
    public func solve() -> SketchSolveResult? {
      let label = floorLabel.trimmingCharacters(in: .whitespacesAndNewlines)
      do {
        let solved = try SketchSolver.solve(
          measurements, context: SketchSolveContext(label: label.isEmpty ? "Floor" : label))
        result = solved
        solveError = nil
        return solved
      } catch {
        result = nil
        solveError = (error as? SketchSolverError)?.description ?? String(describing: error)
        return nil
      }
    }

    /// The Check screen's status row: "Complete" when the solver had every required value,
    /// "Limited" when it estimated something, "Not solved" without a result.
    public var completenessWord: String {
      guard let result else { return "Not solved" }
      return result.isLimited ? "Limited" : "Complete"
    }

    /// Finish floor is offered once the solver gave a model.
    public var canFinish: Bool { result != nil && !isFinishing }

    public func markFinished() {
      step = .finished
    }

    // MARK: Private

    private func newWall(turn: SketchTurn) -> SketchWallDraft {
      SketchWallDraft(id: nextId("wall"), length: SketchLengthField(unit: units.long), turn: turn)
    }

    /// `prefix-N`, N counting up across the capture: an id is never used twice, also after a
    /// room, wall or opening was removed.
    private func nextId(_ prefix: String) -> String {
      let number = (nextNumber[prefix] ?? 0) + 1
      nextNumber[prefix] = number
      return "\(prefix)-\(number)"
    }
  }
#endif

#if canImport(Observation)
  import CaptureContract
  import FieldRules
  import Foundation
  import Observation
  import SketchEntry
  import SketchSolver
  import Walkthrough

  /// Where the walkthrough stands (spec F15 2): walking the rooms (step 3, the AR screen), Check
  /// the scale (step 4), Check (step 5), finished.
  public enum WalkthroughPhase: Sendable, Equatable {
    case walking
    case scale
    case check
    case finished
  }

  /// The four taps of an opening, in the order they are asked: left jamb, right jamb, the sill
  /// (windows only), the head.
  public enum WalkthroughOpeningPart: String, Sendable, Equatable {
    case leftJamb
    case rightJamb
    case sill
    case head
  }

  /// The guided step of one room on the AR screen (spec F15 2).
  public enum WalkthroughStep: Sendable, Equatable {
    /// The room card: name, type, corners or walls.
    case roomName
    /// One tap per floor corner, in order; the room closes on the first corner.
    case corners
    /// "Tap each wall": two taps along the base of each wall; Close the room after three.
    case walls
    /// One tap where a wall meets the ceiling.
    case ceiling
    /// Add a door, window or opening; Next room; Done.
    case openings
    /// The taps of one opening.
    case opening(SketchOpeningKind, WalkthroughOpeningPart)
  }

  /// One walked wall the scale check offers: "Bedroom · wall 1 · 13' 1.6" walked".
  public struct WalkthroughScaleWall: Identifiable, Hashable, Sendable {
    public var roomId: String
    public var roomLabel: String
    public var wallIndex: Int
    /// The walked length (drift distributed), millimetres.
    public var walkedMm: Double

    public var id: String { "\(roomId).\(wallIndex)" }

    public func title(units: DisplayUnitSystem) -> String {
      "\(roomLabel) \u{00B7} wall \(wallIndex + 1) \u{00B7} "
        + "\(WalkthroughText.length(walkedMm, units: units)) walked"
    }
  }

  /// One room of the live 2D outline: its corners so far (x and z matter), closed or not.
  public struct WalkthroughOutlineRoom: Identifiable, Sendable, Equatable {
    public var id: String
    public var label: String
    public var corners: [Vec3]
    public var isClosed: Bool
    public var isCurrent: Bool
  }

  /// A drawn point of the AR overlay: a tapped corner, jamb, sill, head or ceiling point.
  public struct WalkthroughMarker: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
      case corner
      case wallTap
      case opening
      case ceiling
    }

    public var point: Vec3
    public var kind: Kind
  }

  /// Words of the walkthrough screens, so the screens and the tests agree on them.
  public enum WalkthroughText {
    public static let firstCorner = "Point at a floor corner and tap +"
    public static let nextCorner = "Point at the next corner and tap +"
    public static let closeOrNext = "Tap the next corner, or the first one to close the room"
    public static let closeOnFirst = "Tap + on the first corner to close the room"
    public static let ceiling = "Point where a wall meets the ceiling and tap +"
    public static let openings = "Add the doors, windows and openings, then the next room"
    public static let roomName = "Name the room you are standing in"
    public static let moveSlower = "Move slower"
    public static let moreLight = "More light"
    public static let pointAtFloor = "Point at the floor"
    public static let pointAtWall = "Point at a wall of this room"
    public static let starting = "Starting the camera\u{2026}"

    /// "3 points tapped".
    public static func pointCount(_ count: Int) -> String {
      "\(SketchText.plural(count, "point", "points")) tapped"
    }

    /// A length in the capture's units: `13' 1.6"` or `4,008 mm`.
    public static func length(_ mm: Double, units: DisplayUnitSystem) -> String {
      units == .imperial ? LengthFormatter.feetInches(mm) : LengthFormatter.millimetres(mm)
    }

    static func wallInstruction(wall: Int, taps: Int, canClose: Bool) -> String {
      if taps == 0 {
        return canClose
          ? "Wall \(wall): tap + at its base, or Close the room"
          : "Wall \(wall): point at its base, near one end, and tap +"
      }
      return "Wall \(wall): point at its base, near the other end, and tap +"
    }

    static func openingInstruction(_ kind: SketchOpeningKind, _ part: WalkthroughOpeningPart)
      -> String
    {
      let name = SketchText.kindTitle(kind)
      switch (kind, part) {
      case (.window, .leftJamb): return "\(name): point at its left side and tap +"
      case (.window, .rightJamb): return "\(name): point at its right side and tap +"
      case (_, .leftJamb): return "\(name): tap + where its left side meets the floor"
      case (_, .rightJamb): return "\(name): tap + where its right side meets the floor"
      case (_, .sill): return "\(name): point at the sill and tap +"
      case (_, .head): return "\(name): point at the top of it and tap +"
      }
    }
  }

  /// State and actions behind the AR walkthrough (spec F15 2): the guided steps of each room
  /// (name, the floor corners or "Tap each wall", the closing tap, the ceiling, the openings),
  /// the tap button (enabled only with normal tracking and a point to tap), Undo, and the
  /// walkthrough log (`walkthrough-log.json`) built from every tap; then Check the scale and
  /// the check, solved by the F14 solver from the converter's measurements. The screens only
  /// read this and call its methods, so the walk runs in tests with a replay session.
  ///
  /// Floor points come from the session's reticle; points on a wall (window jambs, sills,
  /// heads, the ceiling line) are where the centre ray meets the vertical plane of the wall it
  /// reaches first, between that wall's two floor corners.
  @MainActor
  @Observable
  public final class WalkthroughModel {
    public let visitId: LowercaseUUID
    public let captureId: LowercaseUUID
    /// The floor or area label and its key, chosen on How do you want to measure?.
    public let floorLabel: String
    public let areaKey: String
    public let mode: CaptureMode
    public let displayUnits: DisplayUnitSystem
    public let session: any WalkthroughSession

    public private(set) var phase: WalkthroughPhase = .walking
    /// The newest camera frame; nil before the first, and right after a tap until the next.
    public private(set) var latest: WalkthroughFrameUpdate?
    /// The room card's fields.
    public var roomName = ""
    public var roomType: RoomType?
    public var roomMethod: WalkthroughMethod = .corners

    /// Check the scale: the chosen wall and the tape length typed for it.
    public var scaleWallId: String?
    public var tape: SketchLengthField
    public private(set) var scaleWalls: [WalkthroughScaleWall] = []
    /// The converter's result for the walk with the scale check, and the solver's.
    public private(set) var conversion: WalkthroughConversion?
    public private(set) var result: SketchSolveResult?
    public private(set) var solveError: String?
    /// Finish floor is stopping the recording and writing the originals.
    public var isFinishing = false

    private var state = WalkState()
    private var history: [WalkState] = []
    @ObservationIgnored private var floorY: Double?
    @ObservationIgnored private var clockZero: TimeInterval = 0
    @ObservationIgnored private var startedAt = UTCTimestamp.now()
    @ObservationIgnored private var scaleCheck: WalkthroughLog.ScaleCheck?
    @ObservationIgnored private var reader: Task<Void, Never>?
    @ObservationIgnored private let videoURL: URL?
    @ObservationIgnored private let clock: () -> TimeInterval
    @ObservationIgnored private var hasStarted = false
    /// The session's recording once stopped, kept so a failed Finish floor can try again
    /// without losing the video.
    @ObservationIgnored private var recording: WalkthroughRecording?

    /// `videoURL`: where the session records `walkthrough.mp4` (moved into the originals at
    /// Finish floor); nil records nothing.
    public init(
      visitId: LowercaseUUID, captureId: LowercaseUUID = LowercaseUUID(), floorLabel: String,
      areaKey: String, mode: CaptureMode = .floor, displayUnits: DisplayUnitSystem,
      session: any WalkthroughSession, videoURL: URL? = nil,
      clock: @escaping () -> TimeInterval = WalkthroughClock.now
    ) {
      self.visitId = visitId
      self.captureId = captureId
      self.floorLabel = floorLabel
      self.areaKey = areaKey
      self.mode = mode
      self.displayUnits = displayUnits
      self.session = session
      self.videoURL = videoURL
      self.clock = clock
      self.tape = SketchLengthField(unit: SketchUnits(display: displayUnits).long)
    }

    // MARK: Session

    /// Starts the AR session (and the recording) and reads its frames. Once.
    public func start() {
      guard !hasStarted else { return }
      hasStarted = true
      clockZero = clock()
      startedAt = .now()
      session.start(recordingTo: videoURL, clockZero: clockZero)
      let updates = session.updates
      reader = Task { [weak self] in
        for await update in updates {
          guard let self else { return }
          self.receive(update)
        }
      }
    }

    /// A camera frame (the session's stream; tests call it directly).
    public func receive(_ update: WalkthroughFrameUpdate) {
      latest = update
      if let y = update.floorY { floorY = y }
    }

    /// Leaves the walkthrough without a floor: the session stops, the recording is dropped.
    public func cancel() async {
      reader?.cancel()
      var recording = self.recording
      if recording == nil { recording = await session.stop() }
      if let url = recording?.videoURL { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: Steps

    public var step: WalkthroughStep { state.step }
    public var rooms: [WalkthroughLog.Room] { state.rooms }
    public var currentRoom: WalkthroughLog.Room? {
      state.step == .roomName ? nil : state.rooms.last
    }

    /// "Room 2" for the room card's prompt.
    public var nextRoomPlaceholder: String { "Room \(state.rooms.count + 1)" }

    /// The room card's Start: a new room with the name (or "Room N"), type and method.
    public func startRoom() {
      guard phase == .walking, state.step == .roomName else { return }
      remember()
      let label = roomName.trimmingCharacters(in: .whitespacesAndNewlines)
      let id = state.nextId("room")
      state.rooms.append(
        WalkthroughLog.Room(
          id: id, label: label.isEmpty ? nextRoomPlaceholder : label, type: roomType,
          method: roomMethod, corners: roomMethod == .corners ? [] : nil,
          walls: roomMethod == .walls ? [] : nil))
      state.step = roomMethod == .corners ? .corners : .walls
    }

    /// Switches the current room between one tap per corner and "Tap each wall" (furniture in
    /// a corner) while nothing of it is tapped.
    public func setMethod(_ method: WalkthroughMethod) {
      guard var room = currentRoom, room.method != method, !hasFloorTaps(room) else { return }
      room.method = method
      room.corners = method == .corners ? [] : nil
      room.walls = method == .walls ? [] : nil
      state.rooms[state.rooms.count - 1] = room
      state.step = method == .corners ? .corners : .walls
      roomMethod = method
    }

    public var canSwitchMethod: Bool {
      guard let room = currentRoom else { return false }
      return (state.step == .corners || state.step == .walls) && !hasFloorTaps(room)
    }

    /// "Close the room" of "Tap each wall": three walls or more, each with two taps.
    public var canCloseWalls: Bool {
      guard state.step == .walls, let walls = currentRoom?.walls else { return false }
      return walls.count >= 3 && walls.allSatisfy { $0.count >= 2 }
    }

    public func closeWalls() {
      guard canCloseWalls, let room = currentRoom else { return }
      remember()
      state.closed.insert(room.id)
      state.step = .ceiling
    }

    /// An earlier room whose ceiling the current room can use instead of a tap: the converter
    /// gives a room without ceiling taps the ceiling of the room before it.
    public var sameCeilingRoom: String? {
      guard state.step == .ceiling else { return nil }
      return state.rooms.dropLast().last { !$0.ceiling.isEmpty }?.label
    }

    public func useSameCeiling() {
      guard sameCeilingRoom != nil else { return }
      remember()
      state.step = .openings
    }

    /// Door, window or opening: its taps follow.
    public func addOpening(_ kind: SketchOpeningKind) {
      guard state.step == .openings else { return }
      remember()
      state.opening = PendingOpening(id: state.nextId(kind.rawValue), kind: kind)
      state.step = .opening(kind, .leftJamb)
    }

    /// Next room: the room card for a new room.
    public func nextRoom() {
      guard state.step == .openings else { return }
      remember()
      state.step = .roomName
      roomName = ""
      roomType = nil
      roomMethod = .corners
    }

    /// Done is offered when every room so far is closed (on the openings step, or on the card
    /// of a room not started).
    public var canFinishWalking: Bool {
      guard phase == .walking, !state.rooms.isEmpty else { return false }
      return state.step == .openings || state.step == .roomName
    }

    /// Done: the session pauses and Check the scale opens.
    public func finishWalking() {
      guard canFinishWalking else { return }
      session.pause()
      latest = nil
      scaleWalls = makeScaleWalls()
      if let id = scaleWallId, !scaleWalls.contains(where: { $0.id == id }) { scaleWallId = nil }
      phase = .scale
    }

    /// Back from Check the scale to the AR screen.
    public func backToWalking() {
      guard phase == .scale else { return }
      phase = .walking
      session.resume()
    }

    // MARK: Tapping

    /// The point + would add now: the reticle on the floor, or where the centre ray meets a
    /// wall; nil when there is none or the step takes no tap.
    public var target: Vec3? { targetHit?.point.vec3 }

    /// The tap button is enabled: walking, normal tracking and a point to tap.
    public var canTap: Bool {
      phase == .walking && latest?.tracking == .normal && target != nil
    }

    /// The step's instruction at the top of the AR screen.
    public var instruction: String {
      switch state.step {
      case .roomName:
        return WalkthroughText.roomName
      case .corners:
        let corners = currentRoom?.corners?.count ?? 0
        if corners == 0 { return WalkthroughText.firstCorner }
        if corners < 3 { return WalkthroughText.nextCorner }
        return isNearFirstCorner ? WalkthroughText.closeOnFirst : WalkthroughText.closeOrNext
      case .walls:
        let walls = currentRoom?.walls ?? []
        let open = walls.last.map { $0.count < 2 } ?? false
        let number = open ? walls.count : walls.count + 1
        return WalkthroughText.wallInstruction(
          wall: number, taps: open ? (walls.last?.count ?? 0) : 0, canClose: canCloseWalls)
      case .ceiling:
        return WalkthroughText.ceiling
      case .openings:
        return WalkthroughText.openings
      case .opening(let kind, let part):
        return WalkthroughText.openingInstruction(kind, part)
      }
    }

    /// Why + is disabled while walking ("Move slower", "More light", "Point at the floor"); nil
    /// when it is enabled or the step takes no tap.
    public var trackingMessage: String? {
      guard phase == .walking, takesTap else { return nil }
      guard let latest else { return WalkthroughText.starting }
      switch latest.tracking {
      case .notAvailable:
        return WalkthroughText.starting
      case .limited:
        switch latest.trackingReason {
        case .excessiveMotion?: return WalkthroughText.moveSlower
        case .insufficientFeatures?: return WalkthroughText.moreLight
        case .relocalizing?: return "Go back to where you started"
        case .initializing?, nil: return "Move the phone slowly"
        }
      case .normal:
        guard target == nil else { return nil }
        return needsWall ? WalkthroughText.pointAtWall : WalkthroughText.pointAtFloor
      }
    }

    /// +: adds the target point to the step (a corner, the closing tap, a wall tap, the
    /// ceiling, a jamb, sill or head) and moves the step on.
    public func tap() {
      guard canTap, let hit = targetHit, let latest else { return }
      // The time of the tap itself (the frame may be older, as a replay's is), which the
      // converter spreads the loop drift by.
      let tap = WalkthroughLog.Tap(
        p: hit.point.vec3, t: max(0, clock() - clockZero), tracking: latest.tracking)
      remember()
      apply(tap, wallIndex: hit.wallIndex)
      self.latest = nil
      session.advance()
    }

    public var canUndo: Bool { phase == .walking && !history.isEmpty }

    /// Undo: back to before the last tap or step.
    public func undo() {
      guard canUndo, let previous = history.popLast() else { return }
      state = previous
      if state.step == .roomName { roomMethod = .corners }
    }

    // MARK: Overlay

    /// Every room's corners so far for the 2D outline (the converter's live corners when it
    /// has them, else the taps), the current room last.
    public var outline: [WalkthroughOutlineRoom] {
      state.rooms.enumerated().map { index, room in
        let isCurrent = index == state.rooms.count - 1 && state.step != .roomName
        return WalkthroughOutlineRoom(
          id: room.id, label: room.label, corners: corners(of: room), isClosed: isClosed(room),
          isCurrent: isCurrent)
      }
    }

    /// The tapped points for the AR overlay.
    public var markers: [WalkthroughMarker] {
      var markers: [WalkthroughMarker] = []
      for room in state.rooms {
        markers += (room.corners ?? []).map { WalkthroughMarker(point: $0.p, kind: .corner) }
        if let closing = room.closingTap {
          markers.append(WalkthroughMarker(point: closing.p, kind: .corner))
        }
        markers += (room.walls ?? []).flatMap { $0 }.map {
          WalkthroughMarker(point: $0.p, kind: .wallTap)
        }
        markers += room.ceiling.map { WalkthroughMarker(point: $0.p, kind: .ceiling) }
        for opening in room.openings {
          let taps = [opening.leftJamb, opening.rightJamb] + [opening.sill, opening.head].compactMap { $0 }
          markers += taps.map { WalkthroughMarker(point: $0.p, kind: .opening) }
        }
      }
      if let opening = state.opening {
        markers += opening.taps.map { WalkthroughMarker(point: $0.p, kind: .opening) }
      }
      return markers
    }

    /// The walls of every room so far as floor segments, for the AR overlay's lines.
    public var wallLines: [(start: Vec3, end: Vec3)] {
      state.rooms.flatMap { room in
        segments(of: room, closed: isClosed(room)).map { ($0.start.vec3, $0.end.vec3) }
      }
    }

    /// Each wall's length of a room's corners, metres, in order (the closing wall last when
    /// closed): the outline's labels.
    public static func wallLengths(_ corners: [Vec3], closed: Bool) -> [Double] {
      guard corners.count >= 2 else { return [] }
      let count = closed ? corners.count : corners.count - 1
      return (0..<count).map { index in
        let a = corners[index]
        let b = corners[(index + 1) % corners.count]
        let dx = b.x - a.x
        let dz = b.z - a.z
        return (dx * dx + dz * dz).squareRoot()
      }
    }

    // MARK: Check the scale (step 4)

    public var scaleWall: WalkthroughScaleWall? {
      scaleWalls.first { $0.id == scaleWallId }
    }

    /// Continue is offered without a scale (Skip) or with a wall and a tape length that parses.
    public var canApplyScale: Bool { scaleWall != nil && tape.isEntered }

    /// "Use this length": the tape length of the chosen wall scales every length of the floor.
    public func applyScale() {
      guard phase == .scale, let wall = scaleWall, let length = tape.length else { return }
      scaleCheck = WalkthroughLog.ScaleCheck(
        roomId: wall.roomId, wallIndex: wall.wallIndex,
        tape: WalkthroughLog.Length(
          valueMm: length.valueMm, enteredUnit: length.enteredUnit, enteredText: length.enteredText))
      solve()
      phase = .check
    }

    /// Skip: the scale is the phone's own (`scaleSource: ar`).
    public func skipScale() {
      guard phase == .scale else { return }
      scaleCheck = nil
      solve()
      phase = .check
    }

    public func backToScale() {
      if phase == .check { phase = .scale }
    }

    /// The scale correction as the Check screen says it ("Scale from the tape: × 0.9983"), nil
    /// without a tape check.
    public var scaleText: String? {
      guard let factor = conversion?.summary.scaleFactor else { return nil }
      return "Scale from the tape: \u{00D7} " + String(format: "%.4f", factor)
    }

    // MARK: Check (step 5)

    /// The converter's notes, then the solver's are on `result`.
    public var notes: [String] { conversion?.notes ?? [] }

    public var completenessWord: String {
      guard let result else { return "Not solved" }
      return result.isLimited ? "Limited" : "Complete"
    }

    public var canFinish: Bool { phase == .check && result != nil && !isFinishing }

    /// The log as it stands (no recording): the converter's input for the scale list and the
    /// check.
    public func log(recording: WalkthroughRecording? = nil, finishedAt: UTCTimestamp? = nil)
      -> WalkthroughLog
    {
      var video: WalkthroughLog.Video?
      if let recording, recording.videoURL != nil {
        video = WalkthroughLog.Video(
          path: WalkthroughFloorWriter.videoPackagePath(areaKey: areaKey, captureId: captureId),
          width: recording.width, height: recording.height,
          framesPerSecond: recording.framesPerSecond)
      }
      return WalkthroughLog(
        visitId: visitId, captureId: captureId, areaKey: areaKey, startedAt: startedAt,
        finishedAt: finishedAt ?? .now(), video: video,
        intrinsics: video == nil ? nil : recording?.intrinsics, floorY: logFloorY,
        frames: recording?.frames ?? [], rooms: state.rooms.filter(isClosed),
        scaleCheck: scaleCheck)
    }

    /// What Finish floor writes: the final log (with the video and the frames) and its
    /// conversion and solution.
    public struct Finished: Sendable {
      public var log: WalkthroughLog
      public var conversion: WalkthroughConversion
      public var result: SketchSolveResult
      /// The recorded video to move into the originals; nil when nothing was recorded.
      public var videoURL: URL?
      public var recordingProblem: String?
    }

    /// Finish floor: stops the session (the recording finishes), builds the final log and
    /// converts and solves it once more with the recorded frames. Throws the converter's or the
    /// solver's error; the recording is kept for another try.
    public func finish() async throws -> Finished {
      reader?.cancel()
      let recording: WalkthroughRecording
      if let stopped = self.recording {
        recording = stopped
      } else {
        recording = await session.stop()
        self.recording = recording
      }
      let finalLog = log(recording: recording, finishedAt: .now())
      let conversion = try WalkthroughConverter.convert(
        finalLog, displayUnits: displayUnits,
        sourcePath: WalkthroughFloorWriter.logPackagePath(areaKey: areaKey, captureId: captureId),
        recorded: finalLog.video != nil)
      let result = try SketchSolver.solve(
        conversion.measurements, context: SketchSolveContext(label: floorLabel))
      self.conversion = conversion
      self.result = result
      return Finished(
        log: finalLog, conversion: conversion, result: result,
        videoURL: finalLog.video == nil ? nil : recording.videoURL,
        recordingProblem: recording.problem)
    }

    public func markFinished() {
      phase = .finished
    }

    // MARK: Private

    private func remember() {
      history.append(state)
    }

    private var takesTap: Bool {
      switch state.step {
      case .roomName, .openings: return false
      default: return true
      }
    }

    /// The step's tap is on a wall (ceiling, window jambs, sills, heads).
    private var needsWall: Bool {
      switch state.step {
      case .ceiling: return true
      case .opening(let kind, let part):
        return kind == .window || part == .sill || part == .head
      default: return false
      }
    }

    private struct Hit {
      var point: WPoint
      var wallIndex: Int?
    }

    private var targetHit: Hit? {
      guard phase == .walking, takesTap, let latest, latest.tracking == .normal else { return nil }
      if !needsWall {
        guard let floor = latest.floorHit else { return nil }
        return Hit(point: WPoint(floor), wallIndex: nil)
      }
      guard let room = currentRoom else { return nil }
      var walls = segments(of: room, closed: true)
      if let wall = state.opening?.wallIndex {
        walls = walls.filter { $0.index == wall }
      }
      guard
        let hit = WalkthroughSpace.firstHit(
          walls, origin: WPoint(latest.rayOrigin), direction: WPoint(latest.rayDirection))
      else { return nil }
      return Hit(point: hit.point, wallIndex: hit.wallIndex)
    }

    private var isNearFirstCorner: Bool {
      guard let corners = currentRoom?.corners, corners.count >= 3, let first = corners.first,
        let floor = latest?.floorHit
      else { return false }
      let dx = floor.x - first.p.x
      let dz = floor.z - first.p.z
      return (dx * dx + dz * dz).squareRoot() <= WalkthroughDefaults.closeSnapMetres
    }

    private func apply(_ tap: WalkthroughLog.Tap, wallIndex: Int?) {
      let last = state.rooms.count - 1
      guard last >= 0 else { return }
      var room = state.rooms[last]
      switch state.step {
      case .corners:
        let corners = room.corners ?? []
        let first = corners.first.map { WPoint($0.p) }
        let distance = first.map { (WPoint(tap.p) - $0).horizontalLength } ?? .infinity
        if corners.count >= 3, distance <= WalkthroughDefaults.closeSnapMetres {
          room.closingTap = tap
          state.step = .ceiling
        } else {
          room.corners = corners + [tap]
        }
      case .walls:
        var walls = room.walls ?? []
        if let open = walls.last, open.count < 2 {
          walls[walls.count - 1].append(tap)
        } else {
          walls.append([tap])
        }
        room.walls = walls
      case .ceiling:
        room.ceiling.append(tap)
        state.step = .openings
      case .opening(let kind, let part):
        guard var opening = state.opening else { return }
        switch part {
        case .leftJamb:
          opening.leftJamb = tap
          if kind == .window { opening.wallIndex = wallIndex }
          state.step = .opening(kind, .rightJamb)
        case .rightJamb:
          opening.rightJamb = tap
          if opening.wallIndex == nil, let left = opening.leftJamb {
            let middle = (WPoint(left.p) + WPoint(tap.p)) * 0.5
            opening.wallIndex = WalkthroughSpace.nearestWall(
              to: middle, in: segments(of: room, closed: true))
          }
          state.step = .opening(kind, kind == .window ? .sill : .head)
        case .sill:
          opening.sill = tap
          state.step = .opening(kind, .head)
        case .head:
          opening.head = tap
          if let done = opening.finished { room.openings.append(done) }
          state.opening = nil
          state.step = .openings
          state.rooms[last] = room
          return
        }
        state.opening = opening
      case .roomName, .openings:
        return
      }
      state.rooms[last] = room
    }

    private func hasFloorTaps(_ room: WalkthroughLog.Room) -> Bool {
      !(room.corners ?? []).isEmpty || !(room.walls ?? []).isEmpty
    }

    private func isClosed(_ room: WalkthroughLog.Room) -> Bool {
      switch room.method {
      case .corners: return room.closingTap != nil
      case .walls: return state.closed.contains(room.id)
      }
    }

    /// A room's floor corners: the corner taps, or the meeting points of consecutive wall
    /// lines (the converter's live corners when it has them).
    private func corners(of room: WalkthroughLog.Room) -> [Vec3] {
      let closed = isClosed(room)
      // A closed "Tap each wall" room also has the corner between its last and first wall,
      // which the converter's live corners leave out.
      if !(closed && room.method == .walls),
        let live = WalkthroughConverter.liveCorners(room, floorY: floorY ?? 0), !live.isEmpty
      {
        return live
      }
      return ownCorners(of: room, closed: closed).map(\.vec3)
    }

    private func ownCorners(of room: WalkthroughLog.Room, closed: Bool) -> [WPoint] {
      switch room.method {
      case .corners:
        return (room.corners ?? []).map { WPoint($0.p) }
      case .walls:
        let walls = (room.walls ?? []).filter { $0.count >= 2 }
        guard walls.count >= 2 else {
          return walls.first.map { [WPoint($0[0].p), WPoint($0[$0.count - 1].p)] } ?? []
        }
        let y = floorY ?? walls[0][0].p.y
        var corners: [WPoint] = []
        // Corner i is where wall i − 1 meets wall i; an open room starts at wall 0's first tap.
        for index in walls.indices {
          if index == 0 && !closed {
            corners.append(WPoint(walls[0][0].p))
            continue
          }
          let previous = walls[(index + walls.count - 1) % walls.count]
          let wall = walls[index]
          let meet = WalkthroughSpace.intersect(
            WPoint(previous[0].p), WPoint(previous[previous.count - 1].p), WPoint(wall[0].p),
            WPoint(wall[wall.count - 1].p), y: y)
          corners.append(meet ?? WPoint(wall[0].p))
        }
        if !closed, let last = walls.last {
          corners.append(WPoint(last[last.count - 1].p))
        }
        return corners
      }
    }

    private func segments(of room: WalkthroughLog.Room, closed: Bool) -> [WalkthroughWallSegment] {
      let corners = ownCorners(of: room, closed: closed)
      guard corners.count >= 2 else { return [] }
      let count = closed && corners.count >= 3 ? corners.count : corners.count - 1
      return (0..<count).map { index in
        WalkthroughWallSegment(
          index: index, start: corners[index], end: corners[(index + 1) % corners.count])
      }
    }

    private var logFloorY: Double {
      if let floorY { return floorY }
      let taps = state.rooms.flatMap { ($0.corners ?? []) + ($0.walls ?? []).flatMap { $0 } }
      guard !taps.isEmpty else { return 0 }
      return taps.reduce(0) { $0 + $1.p.y } / Double(taps.count)
    }

    /// The walls of the walk with their walked length: from the converter (drift
    /// distributed), else from the taps.
    private func makeScaleWalls() -> [WalkthroughScaleWall] {
      var walkLog = log()
      walkLog.scaleCheck = nil
      let converted = try? WalkthroughConverter.convert(
        walkLog, displayUnits: displayUnits,
        sourcePath: WalkthroughFloorWriter.logPackagePath(areaKey: areaKey, captureId: captureId),
        recorded: false)
      return walkLog.rooms.flatMap { room -> [WalkthroughScaleWall] in
        let corners =
          converted?.corners[room.id] ?? ownCorners(of: room, closed: true).map(\.vec3)
        return Self.wallLengths(corners, closed: true).enumerated().map { index, metres in
          WalkthroughScaleWall(
            roomId: room.id, roomLabel: room.label, wallIndex: index, walkedMm: metres * 1000)
        }
      }
    }

    private func solve() {
      do {
        let converted = try WalkthroughConverter.convert(
          log(), displayUnits: displayUnits,
          sourcePath: WalkthroughFloorWriter.logPackagePath(areaKey: areaKey, captureId: captureId),
          recorded: videoURL != nil)
        conversion = converted
        result = try SketchSolver.solve(
          converted.measurements, context: SketchSolveContext(label: floorLabel))
        solveError = nil
      } catch {
        result = nil
        if let walk = error as? WalkthroughError {
          conversion = nil
          solveError = walk.description
        } else {
          solveError = (error as? SketchSolverError)?.description ?? String(describing: error)
        }
      }
    }
  }

  /// Everything Undo can go back over: the rooms, the step, the opening being tapped, the ids
  /// handed out and which "Tap each wall" rooms are closed.
  struct WalkState: Equatable {
    var rooms: [WalkthroughLog.Room] = []
    var step: WalkthroughStep = .roomName
    var opening: PendingOpening?
    var numbers: [String: Int] = [:]
    var closed: Set<String> = []

    /// `prefix-N`, N counting up across the capture.
    mutating func nextId(_ prefix: String) -> String {
      let number = (numbers[prefix] ?? 0) + 1
      numbers[prefix] = number
      return "\(prefix)-\(number)"
    }
  }

  /// An opening while its taps are being made.
  struct PendingOpening: Equatable {
    var id: String
    var kind: SketchOpeningKind
    var wallIndex: Int?
    var leftJamb: WalkthroughLog.Tap?
    var rightJamb: WalkthroughLog.Tap?
    var sill: WalkthroughLog.Tap?
    var head: WalkthroughLog.Tap?

    var taps: [WalkthroughLog.Tap] { [leftJamb, rightJamb, sill, head].compactMap { $0 } }

    var finished: WalkthroughLog.Opening? {
      guard let leftJamb, let rightJamb, let wallIndex else { return nil }
      return WalkthroughLog.Opening(
        id: id, kind: kind, wallIndex: wallIndex, leftJamb: leftJamb, rightJamb: rightJamb,
        head: head, sill: kind == .window ? sill : nil)
    }
  }
#endif

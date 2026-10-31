import CaptureContract
import Foundation

/// One room's floor outline as walked: corners in the walkthrough frame (metres, see
/// `FloorPoint`), counter-clockwise, before the scale check.
struct WalkedRoom {
  var room: WalkthroughLog.Room
  var corners: [FloorPoint]
  /// The loop gap (closing tap to first corner) in metres, before it was distributed. Nil
  /// without a closing tap.
  var gap: Double?
  /// True when the walk went clockwise and the corners were rewound (corner 0 kept).
  var rewound: Bool

  /// The document's wall index of a wall the log numbers in walking order.
  func wallIndex(walked index: Int) -> Int {
    rewound ? corners.count - 1 - index : index
  }
}

/// One conversion of a finished walkthrough to the F14 document (spec F15 section 3).
struct WalkthroughConversionRun {
  let log: WalkthroughLog
  let displayUnits: DisplayUnitSystem
  let sourcePath: String
  let recorded: Bool

  func run() throws -> WalkthroughConversion {
    guard !log.rooms.isEmpty else { throw WalkthroughError.noRooms }
    let walked = try log.rooms.map(walk)
    for room in walked {
      for opening in room.room.openings where !(0..<room.corners.count).contains(opening.wallIndex) {
        throw WalkthroughError.unknownWall(openingId: opening.id, wallIndex: opening.wallIndex)
      }
    }

    var notes: [String] = []
    for room in walked {
      if let gap = room.gap {
        notes.append(
          "\(room.room.label): the loop closed \(Int((gap * 1000).rounded())) mm apart; spread over the corners."
        )
      }
    }

    // 5. The scale check: tape / AR length of the taped wall, applied to every length.
    var scale = 1.0
    var scaleNote: String?
    if let check = log.scaleCheck {
      guard let room = walked.first(where: { $0.room.id == check.roomId }),
        (0..<room.corners.count).contains(check.wallIndex)
      else {
        throw WalkthroughError.unknownScaleWall(roomId: check.roomId, wallIndex: check.wallIndex)
      }
      let index = room.wallIndex(walked: check.wallIndex)
      let arMm = (room.corners[(index + 1) % room.corners.count] - room.corners[index]).length * 1000
      guard arMm > 1, check.tape.valueMm > 0 else {
        throw WalkthroughError.unknownScaleWall(roomId: check.roomId, wallIndex: check.wallIndex)
      }
      scale = check.tape.valueMm / arMm
      scaleNote =
        "Scale checked with a tape on \(room.room.label) wall \(check.wallIndex + 1): ×\(format(rounded(scale, places: 5)))."
    }

    // 4. Ceiling: the mean of each room's ceiling taps above the floor; a room without taps
    //    takes the previous room's (the rooms before the first tapped one take that one's).
    let own: [Double?] = log.rooms.map { room in
      guard !room.ceiling.isEmpty else { return nil }
      let mean = room.ceiling.reduce(0) { $0 + $1.p.y } / Double(room.ceiling.count) - log.floorY
      return mean > 0 ? mean * 1000 * scale : nil
    }
    var ceilings: [Double?] = []
    var previous: Double? = nil
    for value in own {
      previous = value ?? previous
      ceilings.append(previous)
    }
    if let first = own.compactMap({ $0 }).first {
      ceilings = ceilings.map { $0 ?? first }
    }
    let floorCeiling = ceilings.first ?? nil

    var rooms: [SketchMeasurements.Room] = []
    var corners: [String: [Vec3]] = [:]
    var wallNumber = 0
    for (roomIndex, walkedRoom) in walked.enumerated() {
      let room = walkedRoom.room
      let points = walkedRoom.corners
      let n = points.count

      // 2. Walls, turns and the diagonals across unsquare corners.
      var walls: [SketchMeasurements.Wall] = []
      var diagonals: [SketchMeasurements.Diagonal] = []
      var diagonalPairs: Set<[Int]> = []
      for index in 0..<n {
        wallNumber += 1
        let a = points[index]
        let b = points[(index + 1) % n]
        let c = points[(index + 2) % n]
        let lengthMm = (b - a).length * 1000 * scale
        guard lengthMm >= 1 else { throw WalkthroughError.tooFewCorners(roomId: room.id) }
        let turnDegrees = atan2((b - a).cross(c - b), (b - a).dot(c - b)) * 180 / Double.pi
        let turn: SketchTurn
        if abs(turnDegrees - 90) <= WalkthroughDefaults.squareToleranceDegrees {
          turn = .left
        } else if abs(turnDegrees + 90) <= WalkthroughDefaults.squareToleranceDegrees {
          turn = .right
        } else {
          turn = .unsquare
          let corner = (index + 1) % n
          let interior = 180 - turnDegrees
          notes.append(
            "\(room.label): corner \(corner + 1) is \(format(rounded(interior, places: 1)))°, not square; kept with the diagonal across it."
          )
          // The diagonal across the corner joins its two neighbours; a triangle has none.
          let pair = [index, (index + 2) % n].sorted()
          if n >= 4, diagonalPairs.insert(pair).inserted {
            let span = (points[pair[1]] - points[pair[0]]).length * 1000 * scale
            diagonals.append(
              SketchMeasurements.Diagonal(from: pair[0], to: pair[1], length: length(span)))
          }
        }
        walls.append(
          SketchMeasurements.Wall(
            id: "wall-\(wallNumber)", length: length(lengthMm), turn: turn == .left ? nil : turn))
      }

      // 3. Openings from the jamb, sill and head taps.
      var openings: [SketchMeasurements.Opening] = []
      for opening in room.openings {
        let wallIndex = walkedRoom.wallIndex(walked: opening.wallIndex)
        let a = points[wallIndex]
        let b = points[(wallIndex + 1) % n]
        let wallMm = (b - a).length * 1000 * scale
        guard let direction = (b - a).normalized else { continue }
        let along = [opening.leftJamb, opening.rightJamb].map {
          (FloorPoint($0.p) - a).dot(direction) * 1000 * scale
        }
        let width = abs(along[0] - along[1])
        let from = min(max(along.min() ?? 0, 0), wallMm)
        var height: Double?
        var sill: Double?
        switch opening.kind {
        case .door, .opening:
          height = opening.head.map { ($0.p.y - log.floorY) * 1000 * scale }
        case .window:
          sill = opening.sill.map { ($0.p.y - log.floorY) * 1000 * scale }
          if let head = opening.head, let sillTap = opening.sill {
            height = (head.p.y - sillTap.p.y) * 1000 * scale
          }
        }
        openings.append(
          SketchMeasurements.Opening(
            id: opening.id, kind: opening.kind, wallId: walls[wallIndex].id,
            width: positive(width), height: height.flatMap(positive), sill: sill.flatMap(positive),
            fromCorner: .start,
            // A jamb on the corner itself is 1 mm from it: the schema wants a positive length.
            fromCornerDistance: length(max(from, 1))))
      }

      let start = points[0]
      let wall0 = points[1 % n] - points[0]
      var angle = wall0.angle * 180 / Double.pi
      if angle <= -180 { angle += 360 }
      let placement = SketchMeasurements.Placement(
        x: micrometres(start.x * scale), z: micrometres(-start.y * scale),
        angleDeg: rounded(angle, places: 6))

      var roomCeiling: SketchMeasurements.Length?
      if let value = ceilings[roomIndex], let floor = floorCeiling, abs(value - floor) > 20 {
        roomCeiling = length(value)
      }

      rooms.append(
        SketchMeasurements.Room(
          id: room.id, label: room.label, type: room.type, walls: walls, diagonals: diagonals,
          openings: openings, ceilingHeight: roomCeiling, placement: placement))
      corners[room.id] = points.map { ($0 * scale).vec3() }
    }
    if let scaleNote { notes.append(scaleNote) }

    let measurements = SketchMeasurements(
      visitId: log.visitId, captureId: log.captureId, areaKey: log.areaKey,
      displayUnits: displayUnits,
      source: SketchMeasurements.Source(kind: .arWalkthrough, path: sourcePath),
      ceilingHeight: floorCeiling.map(length), rooms: rooms)

    let loop = walked.compactMap(\.gap).max().map { rounded($0 * 1000, places: 1) } ?? 0
    let summary = CaptureRecord.Capture.WalkthroughSummary(
      scaleSource: log.scaleCheck == nil ? .ar : .tape,
      scaleFactor: log.scaleCheck == nil ? nil : rounded(scale, places: 5),
      loopClosureMm: loop, trackingLimitedSeconds: trackingLimitedSeconds(), recorded: recorded)
    return WalkthroughConversion(
      measurements: measurements, summary: summary, corners: corners, notes: notes)
  }

  // MARK: - Corners

  /// 1. The room's corners on the floor: the corner taps with the loop drift distributed by
  /// time, or the intersections of the wall lines; rewound to counter-clockwise.
  private func walk(_ room: WalkthroughLog.Room) throws -> WalkedRoom {
    var points: [FloorPoint]
    var gap: Double?
    switch room.method {
    case .corners:
      let taps = room.corners ?? []
      guard taps.count >= 3 else { throw WalkthroughError.tooFewCorners(roomId: room.id) }
      points = taps.map { FloorPoint($0.p) }
      if let closing = room.closingTap {
        let drift = FloorPoint(closing.p) - points[0]
        gap = drift.length
        let t0 = taps[0].t
        let span = closing.t - t0
        for index in points.indices {
          // Drift grows with time; when the times say nothing, with the tap order.
          let fraction =
            span > 1e-9
            ? min(max((taps[index].t - t0) / span, 0), 1) : Double(index) / Double(taps.count)
          points[index] = points[index] - drift * fraction
        }
      }
    case .walls:
      let walls = room.walls ?? []
      guard walls.count >= 3 else { throw WalkthroughError.tooFewCorners(roomId: room.id) }
      var lines: [FloorLine] = []
      for taps in walls {
        guard let line = FloorLine.fit(taps.map { FloorPoint($0.p) }) else {
          throw WalkthroughError.tooFewCorners(roomId: room.id)
        }
        lines.append(line)
      }
      let n = lines.count
      points = []
      for index in 0..<n {
        let before = (index + n - 1) % n
        guard let corner = lines[before].intersection(lines[index]) else {
          throw WalkthroughError.wallsDoNotMeet(roomId: room.id, wallIndex: before)
        }
        points.append(corner)
      }
    }

    var rewound = false
    if FloorPoint.signedArea2(points) < 0 {
      points = [points[0]] + points.dropFirst().reversed()
      rewound = true
    }
    return WalkedRoom(room: room, corners: points, gap: gap, rewound: rewound)
  }

  // MARK: - Summary

  /// Seconds between recorded frames whose tracking was not normal: each frame stands for the
  /// interval up to the next one.
  private func trackingLimitedSeconds() -> Double {
    let frames = log.frames.sorted { $0.t < $1.t }
    var total = 0.0
    for (frame, next) in zip(frames, frames.dropFirst()) where frame.tracking != .normal {
      total += next.t - frame.t
    }
    return rounded(total, places: 3)
  }

  // MARK: - Lengths

  private func length(_ valueMm: Double) -> SketchMeasurements.Length {
    let value = rounded(valueMm, places: 1)
    return SketchMeasurements.Length(
      valueMm: value, enteredUnit: WalkthroughLengthText.unit(displayUnits),
      enteredText: WalkthroughLengthText.text(value, units: displayUnits), measured: true)
  }

  /// A length when it is at least a millimetre; nil (the solver's default) otherwise.
  private func positive(_ valueMm: Double) -> SketchMeasurements.Length? {
    valueMm >= 1 ? length(valueMm) : nil
  }

  private func rounded(_ value: Double, places: Int) -> Double {
    let factor = pow(10, Double(places))
    let result = (value * factor).rounded() / factor
    return result == 0 ? 0 : result
  }

  private func format(_ value: Double) -> String {
    var text = String(value)
    if text.hasSuffix(".0") { text.removeLast(2) }
    return text
  }
}

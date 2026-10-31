import CaptureContract
import Foundation

/// How a wall's length in the model was arrived at (spec F14 1.5).
enum WallLengthSource: Hashable, Sendable {
  /// Read from a tape or laser: confidence high.
  case measured
  /// The operator's "about" value: confidence low, the capture is limited.
  case about
  /// Filled from closure as the only unknown on its axis: confidence medium.
  case derived
  /// Nothing to go on but the parallel walls or the 3 m fallback: confidence low, limited.
  case estimated
}

struct SolvedWall: Hashable, Sendable {
  /// The length after closure distribution or the least-squares fit.
  var lengthMm: Double
  var source: WallLengthSource
  var confidence: DetectionConfidence
  /// The axis the wall runs along in the room's own frame when every corner is taken as
  /// square: `x` for wall 0 and its parallels, `z` across.
  var axis: SketchSolveNote.Axis
}

/// One room solved in its own frame: corner 0 at the origin, wall 0 along +x, wound
/// counter-clockwise. Millimetres.
struct SolvedRoom: Sendable {
  var corners: [Plan2]
  var walls: [SolvedWall]
  var notes: [SketchSolveNote]
  /// The absolute closure residual of every axis whose walls were all known, before it was
  /// distributed, plus the worst fit of a room solved with diagonals. For the summary.
  var closureResiduals: [Double]
}

/// The geometry of one room (spec F14 1.3 to 1.5). Rectilinear rooms are solved by the turns
/// and the closure rule; rooms with unsquare corners start from that shape and are refined by
/// least squares against the measured sides and diagonals.
enum RoomSolver {
  static func solve(_ room: SketchMeasurements.Room) throws -> SolvedRoom {
    let n = room.walls.count
    guard n >= 3 else { throw SketchSolverError.tooFewWalls(roomId: room.id) }
    for diagonal in room.diagonals {
      try validate(diagonal, wallCount: n, roomId: room.id)
    }
    var notes: [SketchSolveNote] = []

    // 1. Headings in quarter turns: wall 0 along +x, each turn adds or removes a quarter. An
    //    unsquare corner is taken as left for the rectilinear shape (the starting point of the fit).
    var headings = [Int](repeating: 0, count: n)
    var heading = 0
    for index in 0..<n {
      headings[index] = heading
      switch room.walls[index].turn ?? .left {
      case .left, .unsquare: heading = (heading + 1) % 4
      case .right: heading = (heading + 3) % 4
      }
    }

    // Unsquare corners with a diagonal across them are free in the fit; the rectilinear
    // closure rule (1.4) applies only when there are none, since such a room's axes need not
    // close and the fit grades it instead.
    let freeCorners = Set(
      (0..<n).filter { corner in
        guard room.walls[(corner + n - 1) % n].turn == .unsquare else { return false }
        let neighbours: Set<Int> = [(corner + n - 1) % n, (corner + 1) % n]
        return room.diagonals.contains { Set([$0.from, $0.to]) == neighbours }
      })
    let rectilinear = freeCorners.isEmpty

    // 2. Lengths: what was entered, then one axis at a time what has to be filled in.
    var lengths = [Double?](repeating: nil, count: n)
    var sources = [WallLengthSource](repeating: .estimated, count: n)
    for (index, wall) in room.walls.enumerated() {
      if let entered = wall.length, entered.valueMm.isFinite, entered.valueMm > 0 {
        lengths[index] = entered.valueMm
        sources[index] = entered.measured ? .measured : .about
      }
    }
    var closureResiduals: [Double] = []
    var filled = [Double](repeating: 0, count: n)
    for axisIndex in 0..<2 {
      let axis: SketchSolveNote.Axis = axisIndex == 0 ? .x : .z
      let onAxis = (0..<n).filter { headings[$0] % 2 == axisIndex }
      fillAxis(
        onAxis, axis: axis, room: room, headings: headings, rectilinear: rectilinear,
        lengths: &lengths, sources: &sources, notes: &notes, closureResiduals: &closureResiduals)
    }
    for index in 0..<n {
      filled[index] = lengths[index] ?? SketchDefaults.fallbackWallLengthMm
    }

    // 3. Corners by walking the walls.
    var corners: [Plan2] = []
    var point = Plan2.zero
    for index in 0..<n {
      corners.append(point)
      point = point + Plan2.heading(headings[index]) * filled[index]
    }

    var confidences = sources.map(confidence(for:))

    // 4. Unsquare corners without a diagonal are drawn square and noted, with both adjoining
    //    walls low.
    for corner in 0..<n where room.walls[(corner + n - 1) % n].turn == .unsquare {
      let before = (corner + n - 1) % n
      if !freeCorners.contains(corner) {
        notes.append(
          SketchSolveNote(
            kind: .cornerAssumedSquare(roomId: room.id, corner: corner),
            message:
              "\(room.label): corner \(corner) is marked unsquare but has no diagonal across it; drawn square."
          ))
        confidences[before] = .low
        confidences[corner] = .low
      }
    }

    var walls = (0..<n).map { index in
      SolvedWall(
        lengthMm: filled[index], source: sources[index], confidence: confidences[index],
        axis: headings[index] % 2 == 0 ? .x : .z)
    }

    if !freeCorners.isEmpty {
      corners = fitCorners(
        start: corners, room: room, lengths: lengths, sources: sources, freeCorners: freeCorners)
      for index in 0..<n {
        walls[index].lengthMm = (corners[(index + 1) % n] - corners[index]).length
      }
      if lengths.allSatisfy({ $0 != nil }) {
        gradeFit(
          corners: corners, room: room, walls: walls, notes: &notes,
          closureResiduals: &closureResiduals)
      }
    } else {
      checkDiagonals(corners: corners, room: room, walls: walls, notes: &notes)
    }

    // 5. A sketch entered clockwise (the turns net to the right) is mirrored so the polygon is
    //    counter-clockwise as the contract requires; wall 0 stays along +x.
    if Plan2.signedArea2(corners) < 0 {
      corners = corners.map { Plan2($0.x, -$0.y) }
    }

    return SolvedRoom(
      corners: corners, walls: walls, notes: notes, closureResiduals: closureResiduals)
  }

  // MARK: - Lengths and closure

  private static func fillAxis(
    _ onAxis: [Int], axis: SketchSolveNote.Axis, room: SketchMeasurements.Room, headings: [Int],
    rectilinear: Bool, lengths: inout [Double?], sources: inout [WallLengthSource],
    notes: inout [SketchSolveNote], closureResiduals: inout [Double]
  ) {
    guard !onAxis.isEmpty else { return }
    let n = room.walls.count
    let known = onAxis.filter { lengths[$0] != nil }
    let unknown = onAxis.filter { lengths[$0] == nil }
    var estimated: [Int] = []

    func sum(_ indices: [Int], sign: Int) -> Double {
      indices.filter { headings[$0] / 2 == sign }.reduce(0) { $0 + (lengths[$1] ?? 0) }
    }

    if unknown.count == 1, let index = unknown.first {
      // One unknown on the axis: closure gives it (1.5, "derived").
      let positive = headings[index] / 2 == 0
      let derived = positive ? sum(known, sign: 1) - sum(known, sign: 0) : sum(known, sign: 0) - sum(known, sign: 1)
      if derived > 0 {
        lengths[index] = derived
        sources[index] = .derived
        notes.append(
          SketchSolveNote(
            kind: .wallDerivedFromClosure(wallId: room.walls[index].id),
            message:
              "\(room.label): \(room.walls[index].id) derived from closure (\(Int(derived.rounded())) mm)."
          ))
      } else {
        estimated = [index]
      }
    } else {
      estimated = unknown
    }

    for index in estimated {
      let estimate = estimateLength(index, known: known, lengths: lengths, sources: sources, wallCount: n)
      lengths[index] = estimate
      sources[index] = .estimated
      notes.append(
        SketchSolveNote(
          kind: .wallEstimated(wallId: room.walls[index].id),
          message:
            "\(room.label): \(room.walls[index].id) was not measured; estimated at \(Int(estimate.rounded())) mm."
        ))
    }
    for index in onAxis where sources[index] == .about {
      notes.append(
        SketchSolveNote(
          kind: .wallEstimated(wallId: room.walls[index].id),
          message:
            "\(room.label): \(room.walls[index].id) is an \"about\" value (\(Int((lengths[index] ?? 0).rounded())) mm), not measured."
        ))
    }

    // Closure (1.4): the lengths going one way must equal the lengths coming back.
    let forward = sum(onAxis, sign: 0)
    let backward = sum(onAxis, sign: 1)
    let residual = forward - backward
    let extent = max(forward, backward)
    if unknown.isEmpty {
      guard rectilinear else { return }
      let grade = grade(residual: residual, extent: extent)
      closureResiduals.append(abs(residual))
      let axisName = axis == .x ? "x" : "z"
      let message: String
      switch grade {
      case .pass:
        message =
          "\(room.label): walls close within \(Int(abs(residual).rounded())) mm on the \(axisName) axis."
      case .limitation:
        message =
          "Measurements of \(room.label) do not close by \(Int(abs(residual).rounded())) mm on the \(axisName) axis."
      case .refused:
        message =
          "Measurements of \(room.label) do not close by \(Int(abs(residual).rounded())) mm on the \(axisName) axis (over 3 %); re-check the lengths."
      }
      notes.append(
        SketchSolveNote(
          kind: .closureResidual(roomId: room.id, axis: axis, residualMm: residual, grade: grade),
          message: message))
      _ = distribute(residual, over: onAxis, headings: headings, lengths: &lengths)
    } else if abs(residual) > 1e-9 {
      // Estimates did not close the axis (or the derivation failed): the estimated walls take
      // the residual so the entered values stay as they were; all walls only as a last resort.
      if !distribute(residual, over: estimated, headings: headings, lengths: &lengths) {
        _ = distribute(residual, over: onAxis, headings: headings, lengths: &lengths)
      }
    }
  }

  /// The estimate for an unmeasured wall when closure cannot give it (1.5): the opposite wall
  /// of a rectangle, else the mean of the measured walls on the axis, else the "about" ones,
  /// else 3 m.
  private static func estimateLength(
    _ index: Int, known: [Int], lengths: [Double?], sources: [WallLengthSource], wallCount: Int
  ) -> Double {
    if wallCount == 4, let opposite = lengths[(index + 2) % 4] {
      return opposite
    }
    let measured = known.filter { sources[$0] == .measured }.compactMap { lengths[$0] }
    if !measured.isEmpty {
      return measured.reduce(0, +) / Double(measured.count)
    }
    let any = known.compactMap { lengths[$0] }
    if !any.isEmpty {
      return any.reduce(0, +) / Double(any.count)
    }
    return SketchDefaults.fallbackWallLengthMm
  }

  /// The surveyor's compass rule: every selected wall moves in proportion to its length so the
  /// axis closes. False, with nothing changed, when that would make a wall vanish.
  private static func distribute(
    _ residual: Double, over indices: [Int], headings: [Int], lengths: inout [Double?]
  ) -> Bool {
    let total = indices.reduce(0) { $0 + (lengths[$1] ?? 0) }
    guard total > 0 else { return false }
    var adjusted = lengths
    for index in indices {
      guard let length = lengths[index] else { continue }
      let sign: Double = headings[index] / 2 == 0 ? 1 : -1
      let moved = length - sign * residual * length / total
      guard moved > 0 else { return false }
      adjusted[index] = moved
    }
    lengths = adjusted
    return true
  }

  static func grade(residual: Double, extent: Double) -> SketchSolveNote.ClosureGrade {
    let magnitude = abs(residual)
    let pass = max(SketchDefaults.closurePassFraction * extent, SketchDefaults.closurePassMinimumMm)
    if magnitude <= pass { return .pass }
    if magnitude <= SketchDefaults.closureLimitFraction * extent { return .limitation }
    return .refused
  }

  private static func confidence(for source: WallLengthSource) -> DetectionConfidence {
    switch source {
    case .measured: return .high
    case .derived: return .medium
    case .about, .estimated: return .low
    }
  }

  // MARK: - Unsquare corners

  private static func validate(
    _ diagonal: SketchMeasurements.Diagonal, wallCount n: Int, roomId: String
  ) throws {
    let bad = SketchSolverError.badDiagonal(roomId: roomId, from: diagonal.from, to: diagonal.to)
    guard (0..<n).contains(diagonal.from), (0..<n).contains(diagonal.to) else { throw bad }
    guard diagonal.from != diagonal.to else { throw bad }
    let apart = abs(diagonal.from - diagonal.to)
    guard apart != 1, apart != n - 1 else { throw bad }
    guard diagonal.length.valueMm.isFinite, diagonal.length.valueMm > 0 else { throw bad }
  }

  /// Corner coordinates by least squares (1.4): the residuals are every wall with a length
  /// against that length (measured and "about" at full weight, derived and estimated as a weak
  /// prior that keeps the fit well posed), every diagonal, and a right angle at every corner
  /// that is not free. Corner 0 is the origin and corner 1 stays on +x, which removes the
  /// position and rotation; the angle at corner 0 follows from closure, as the last angle of a
  /// polygon always does.
  private static func fitCorners(
    start: [Plan2], room: SketchMeasurements.Room, lengths: [Double?],
    sources: [WallLengthSource], freeCorners: Set<Int>
  ) -> [Plan2] {
    let n = start.count
    func pack(_ corners: [Plan2]) -> [Double] {
      var values = [corners[1].x]
      for index in 2..<n {
        values.append(corners[index].x)
        values.append(corners[index].y)
      }
      return values
    }
    func unpack(_ values: [Double]) -> [Plan2] {
      var corners = [Plan2.zero, Plan2(values[0], 0)]
      for index in 2..<n {
        corners.append(Plan2(values[1 + 2 * (index - 2)], values[2 + 2 * (index - 2)]))
      }
      return corners
    }
    // A right angle off by 1° is worth about 1.7 m of length error, so the squares the operator
    // asserted hold and the measured lengths share the slack.
    let angleWeight = 1e5
    let fitted = LeastSquares.fit(initial: pack(start)) { values in
      let corners = unpack(values)
      var residuals: [Double] = []
      for index in 0..<n {
        guard let target = lengths[index] else { continue }
        let weight: Double = (sources[index] == .measured || sources[index] == .about) ? 1 : 0.1
        residuals.append(((corners[(index + 1) % n] - corners[index]).length - target) * weight)
      }
      for diagonal in room.diagonals {
        residuals.append((corners[diagonal.to] - corners[diagonal.from]).length - diagonal.length.valueMm)
      }
      for corner in 1..<n where !freeCorners.contains(corner) {
        let incoming = corners[corner] - corners[corner - 1]
        let outgoing = corners[(corner + 1) % n] - corners[corner]
        guard let a = incoming.normalized, let b = outgoing.normalized else {
          residuals.append(0)
          continue
        }
        residuals.append(a.dot(b) * angleWeight)
      }
      return residuals
    }
    return unpack(fitted)
  }

  /// Grades the worst disagreement between the fit and the entered sides and diagonals with the
  /// closure tolerance, on the axis of the worst element (1.4).
  private static func gradeFit(
    corners: [Plan2], room: SketchMeasurements.Room, walls: [SolvedWall],
    notes: inout [SketchSolveNote], closureResiduals: inout [Double]
  ) {
    let n = corners.count
    var worst = 0.0
    var worstAxis: SketchSolveNote.Axis = .x
    for index in 0..<n {
      guard let entered = room.walls[index].length?.valueMm else { continue }
      let deviation = walls[index].lengthMm - entered
      if abs(deviation) > abs(worst) {
        worst = deviation
        worstAxis = walls[index].axis
      }
    }
    for diagonal in room.diagonals {
      let span = corners[diagonal.to] - corners[diagonal.from]
      let deviation = span.length - diagonal.length.valueMm
      if abs(deviation) > abs(worst) {
        worst = deviation
        worstAxis = abs(span.x) >= abs(span.y) ? .x : .z
      }
    }
    let xs = corners.map(\.x)
    let ys = corners.map(\.y)
    let extent = max((xs.max() ?? 0) - (xs.min() ?? 0), (ys.max() ?? 0) - (ys.min() ?? 0))
    let grade = grade(residual: worst, extent: extent)
    closureResiduals.append(abs(worst))
    let axisName = worstAxis == .x ? "x" : "z"
    notes.append(
      SketchSolveNote(
        kind: .closureResidual(roomId: room.id, axis: worstAxis, residualMm: worst, grade: grade),
        message: grade == .pass
          ? "\(room.label): sides and diagonals agree within \(Int(abs(worst).rounded())) mm."
          : "Measurements of \(room.label) disagree by \(Int(abs(worst).rounded())) mm on the \(axisName) axis after the diagonal fit."
      ))
  }

  /// A diagonal in a room with every corner square is a squareness check: it is reported only
  /// when it disagrees with the solved corners by more than the pass tolerance. It does not
  /// move anything and does not count as a closure residual of the summary.
  private static func checkDiagonals(
    corners: [Plan2], room: SketchMeasurements.Room, walls: [SolvedWall],
    notes: inout [SketchSolveNote]
  ) {
    let xs = corners.map(\.x)
    let ys = corners.map(\.y)
    let extent = max((xs.max() ?? 0) - (xs.min() ?? 0), (ys.max() ?? 0) - (ys.min() ?? 0))
    for diagonal in room.diagonals {
      let span = corners[diagonal.to] - corners[diagonal.from]
      let deviation = span.length - diagonal.length.valueMm
      let grade = grade(residual: deviation, extent: extent)
      guard grade != .pass else { continue }
      let axis: SketchSolveNote.Axis = abs(span.x) >= abs(span.y) ? .x : .z
      notes.append(
        SketchSolveNote(
          kind: .closureResidual(roomId: room.id, axis: axis, residualMm: deviation, grade: grade),
          message:
            "\(room.label): the diagonal from corner \(diagonal.from) to corner \(diagonal.to) disagrees with the square room by \(Int(abs(deviation).rounded())) mm."
        ))
    }
  }
}

extension SketchDefaults {
  /// What a wall gets when nothing on its axis was measured (spec F14 1.5): 3 m.
  static let fallbackWallLengthMm: Double = 3000
}

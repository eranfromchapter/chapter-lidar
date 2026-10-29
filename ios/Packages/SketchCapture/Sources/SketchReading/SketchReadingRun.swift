import CaptureContract
import Foundation

/// One conversion of a sketch reading to the F14 document (spec F16 section 4).
struct SketchReadingRun {
  let interpretation: SketchInterpretation
  let userLength: UserScaleLength?
  let visitId: LowercaseUUID
  let captureId: LowercaseUUID
  let areaKey: String
  let displayUnits: DisplayUnitSystem
  let sourceKind: SketchSourceKind
  let imagePath: String
  let interpretationPath: String

  private var reading: SketchInterpretation.Reading { interpretation.reading }
  private var tolerance: Double { SketchReadingDefaults.squareToleranceDegrees }

  /// The scale and the written dimensions that measure walls.
  private struct Scale {
    var millimetresPerUnit: Double
    var source: SketchScaleSource
    var dimensions: [WallDimension]
  }

  /// Running numbers for ids that are unique across the capture.
  private struct Counters {
    var wall = 0
    var door = 0
    var window = 0
    var opening = 0
    var furniture = 0

    mutating func openingId(_ kind: SketchOpeningKind) -> String {
      switch kind {
      case .door:
        door += 1
        return "door-\(door)"
      case .window:
        window += 1
        return "window-\(window)"
      case .opening:
        opening += 1
        return "opening-\(opening)"
      }
    }
  }

  func run() throws -> SketchReadingConversion {
    guard reading.isFloorPlan else {
      let problem = reading.problem?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      throw SketchReadingError.notAFloorPlan(
        problem.isEmpty ? "nothing in it reads as a floor plan." : problem)
    }
    guard !reading.rooms.isEmpty else { throw SketchReadingError.noRooms }
    for (roomIndex, room) in reading.rooms.enumerated() {
      guard room.corners.count >= 3 else { throw SketchReadingError.tooFewCorners(roomIndex: roomIndex) }
      for opening in room.openings where !room.corners.indices.contains(opening.wall) {
        throw SketchReadingError.unknownWall(roomIndex: roomIndex, wallIndex: opening.wall)
      }
    }

    let scan = SketchReadingScan.wallDimensions(reading)
    var notes: [String] = []
    let scale = try chooseScale(scan.usable, notes: &notes)
    notes.append(contentsOf: scan.notes)

    var outlines: [RoomOutline] = []
    for (roomIndex, room) in reading.rooms.enumerated() {
      guard let outline = RoomOutline.make(room.corners, straightToleranceDegrees: tolerance)
      else { throw SketchReadingError.tooFewCorners(roomIndex: roomIndex) }
      outlines.append(outline)
    }
    let origin = PlanPoint(outlines[0].corners[0])

    var counters = Counters()
    var rooms: [SketchMeasurements.Room] = []
    for roomIndex in reading.rooms.indices {
      rooms.append(
        room(
          roomIndex, outline: outlines[roomIndex], origin: origin, scale: scale,
          counters: &counters, notes: &notes))
    }

    let measurements = SketchMeasurements(
      visitId: visitId, captureId: captureId, areaKey: areaKey, displayUnits: displayUnits,
      source: SketchMeasurements.Source(
        kind: sourceKind, path: imagePath, interpretation: interpretationPath),
      ceilingHeight: ceiling(), rooms: rooms)
    return SketchReadingConversion(
      measurements: measurements, scaleSource: scale.source,
      millimetresPerUnit: scale.millimetresPerUnit, notes: notes)
  }

  // MARK: - Scale

  /// Section 4.1: the user's length alone when there is one, else the median of what the
  /// written dimensions imply. Dimensions more than `scaleOutlierFraction` from that are
  /// dropped and noted; with no user length the scale is the median of those kept.
  private func chooseScale(_ usable: [WallDimension], notes: inout [String]) throws -> Scale {
    let fraction = SketchReadingDefaults.scaleOutlierFraction
    var reference: Double
    var candidates = usable
    if let user = userLength {
      guard reading.rooms.indices.contains(user.roomIndex),
        let drawn = SketchReadingScan.drawnLength(reading.rooms[user.roomIndex], wall: user.wallIndex),
        drawn >= RoomOutline.sameCornerUnits
      else {
        throw SketchReadingError.unknownWall(roomIndex: user.roomIndex, wallIndex: user.wallIndex)
      }
      let value = user.length.valueMm
      guard value.isFinite, value > 0 else { throw SketchReadingError.needsOneLength }
      reference = value / drawn
      candidates = usable.filter { !($0.room == user.roomIndex && $0.wall == user.wallIndex) }
    } else {
      guard !usable.isEmpty else { throw SketchReadingError.needsOneLength }
      reference = median(usable.map(\.ratio))
    }

    func off(_ dimension: WallDimension) -> Double {
      abs(dimension.ratio - reference) / reference
    }
    var kept = candidates.filter { off($0) <= fraction }
    let dropped = candidates.filter { off($0) > fraction }
    if userLength == nil, kept.isEmpty {
      // Only possible for an even count split wide apart: nothing says which side is right.
      kept = candidates
      notes.append(
        "The written dimensions disagree with each other by more than \(Int((fraction * 100).rounded())) %; all were used for the scale."
      )
    } else {
      for dimension in dropped {
        let percent = Int((off(dimension) * 100).rounded())
        let against = userLength == nil ? "the others" : "your length"
        notes.append(
          "\(dimension.text) on \(roomLabel(dimension.room)) wall \(dimension.wall + 1) was \(percent) % off \(against) and was not used."
        )
      }
    }

    if let user = userLength {
      notes.insert(
        "Your length of \(roomLabel(user.roomIndex)) wall \(user.wallIndex + 1) set the scale; every length not written on the sketch follows the drawing.",
        at: 0)
      return Scale(millimetresPerUnit: reference, source: .userLength, dimensions: kept)
    }
    let count = kept.count
    notes.insert(
      count == 1
        ? "1 written dimension set the scale; every other length follows the drawing."
        : "\(count) written dimensions set the scale.",
      at: 0)
    return Scale(
      millimetresPerUnit: median(kept.map(\.ratio)), source: .writtenDimensions(count: count),
      dimensions: kept)
  }

  // MARK: - Rooms

  /// Section 4.2 to 4.4 for one room.
  private func room(
    _ roomIndex: Int, outline: RoomOutline, origin: PlanPoint, scale: Scale,
    counters: inout Counters, notes: inout [String]
  ) -> SketchMeasurements.Room {
    let drawing = reading.rooms[roomIndex]
    let label = roomLabel(roomIndex)
    let mmPerUnit = scale.millimetresPerUnit
    let m = outline.corners.count
    // Plan millimetres, the first room's corner 0 at the origin.
    let points: [PlanPoint] = outline.corners.map { (PlanPoint($0) - origin) * mmPerUnit }
    let drawnMm: [Double] = (0..<m).map { (points[($0 + 1) % m] - points[$0]).length }

    if outline.rewound {
      notes.append("\(label) was drawn clockwise; its walls were renumbered counter-clockwise.")
    }
    if outline.removedCorners > 0 {
      let count = outline.removedCorners
      notes.append(
        "\(label): \(count) drawn corner\(count == 1 ? "" : "s") on a straight wall or repeated \(count == 1 ? "was" : "were") left out."
      )
    }

    // Lengths written on the sketch, and the user's.
    var fixed = [SketchMeasurements.Length?](repeating: nil, count: m)
    var fromSketch = [Bool](repeating: false, count: m)
    for dimension in scale.dimensions where dimension.room == roomIndex {
      guard let span = outline.wallMap[dimension.wall] else { continue }
      guard outline.drawnWall[span.wall] == dimension.wall else {
        notes.append(
          "\(dimension.text) measures part of \(label) wall \(dimension.wall + 1), which runs on as one wall; it set the scale only."
        )
        continue
      }
      guard fixed[span.wall] == nil else { continue }
      fixed[span.wall] = written(text: dimension.text, valueMm: dimension.valueMm)
      fromSketch[span.wall] = true
    }
    if let user = userLength, user.roomIndex == roomIndex, let span = outline.wallMap[user.wallIndex] {
      if outline.drawnWall[span.wall] == user.wallIndex {
        var length = user.length
        length.measured = true
        fixed[span.wall] = length
        fromSketch[span.wall] = false
      } else {
        notes.append(
          "Your length is for part of \(label) wall \(user.wallIndex + 1), which runs on as one wall; it set the scale only."
        )
      }
    }

    // Turns: square within the tolerance, else unsquare.
    let turns: [SketchTurn] = (0..<m).map { index in
      let a = points[(index + 1) % m] - points[index]
      let b = points[(index + 2) % m] - points[(index + 1) % m]
      let degrees = a.turn(to: b)
      if abs(degrees - 90) <= tolerance { return .left }
      if abs(degrees + 90) <= tolerance { return .right }
      return .unsquare
    }

    var lengthsMm: [Double] = (0..<m).map { fixed[$0]?.valueMm ?? drawnMm[$0] }
    var leftToClosure = [Bool](repeating: false, count: m)
    if !turns.contains(.unsquare) {
      close(turns: turns, fixed: fixed, fromSketch: fromSketch, lengths: &lengthsMm, leftToClosure: &leftToClosure)
    }

    var walls: [SketchMeasurements.Wall] = []
    for index in 0..<m {
      counters.wall += 1
      let length: SketchMeasurements.Length?
      if let entered = fixed[index] {
        length = entered
      } else if leftToClosure[index] {
        length = nil
      } else {
        length = estimate(lengthsMm[index])
      }
      let turn = turns[index]
      walls.append(
        SketchMeasurements.Wall(
          id: "wall-\(counters.wall)", length: length, turn: turn == .left ? nil : turn))
    }

    // Diagonals across unsquare corners, from the drawing.
    var diagonals: [SketchMeasurements.Diagonal] = []
    var pairs: Set<[Int]> = []
    for index in 0..<m where turns[index] == .unsquare {
      let corner = (index + 1) % m
      let a = points[(index + 1) % m] - points[index]
      let b = points[(index + 2) % m] - points[(index + 1) % m]
      let interior: Double = 180 - a.turn(to: b)
      notes.append(
        "\(label): corner \(corner + 1) is drawn at \(SketchReadingText.number(interior, places: 0))°, not square; kept with an estimated diagonal across it."
      )
      let pair = [index, (index + 2) % m].sorted()
      if m >= 4, pairs.insert(pair).inserted {
        let span = (points[pair[1]] - points[pair[0]]).length
        diagonals.append(
          SketchMeasurements.Diagonal(from: pair[0], to: pair[1], length: estimate(span)))
      }
    }

    // Openings by their fractions along the wall.
    var openings: [SketchMeasurements.Opening] = []
    for opening in drawing.openings {
      guard let span = outline.wallMap[opening.wall] else {
        notes.append(
          "\(label): a \(opening.kind.rawValue) on wall \(opening.wall + 1), which is drawn with no length, was left out."
        )
        continue
      }
      let wall = span.wall
      let f0 = min(max(span.map(opening.start), 0), 1)
      let f1 = min(max(span.map(opening.end), 0), 1)
      let low = min(f0, f1)
      let high = max(f0, f1)
      let wallMm = lengthsMm[wall]
      let width: Double = (high - low) * wallMm
      let from: Double = low * wallMm
      openings.append(
        SketchMeasurements.Opening(
          id: counters.openingId(opening.kind), kind: opening.kind, wallId: walls[wall].id,
          width: width >= 1 ? estimate(width) : nil, fromCorner: .start,
          // A jamb on the corner itself is 1 mm from it: the schema wants a positive length.
          fromCornerDistance: estimate(max(from, 1))))
    }

    // Placement: corner 0 where it is drawn, wall 0 leaving it as drawn (squared to the sheet
    // when within the tolerance, so hand-drawn rooms line up).
    var angle = (points[1 % m] - points[0]).degrees
    let snapped = (angle / 90).rounded() * 90
    if abs(angle - snapped) <= tolerance { angle = snapped }
    let placement = SketchMeasurements.Placement(
      x: micrometres(points[0].x / 1000), z: micrometres(-points[0].y / 1000),
      angleDeg: rounded(normalizedDegrees(angle), places: 6))

    // Furniture: centre and size at the scale; clockwise in the drawing (y down) is clockwise
    // seen from +Y, so the angle about +Y (counter-clockwise) is its negative.
    var furniture: [SketchMeasurements.Furniture] = []
    for item in drawing.furniture {
      let centre = (PlanPoint(item.center) - origin) * mmPerUnit
      let width: Double = item.width * mmPerUnit / 1000
      let depth: Double = item.depth * mmPerUnit / 1000
      guard width.isFinite, depth.isFinite, width >= 0.001, depth >= 0.001,
        centre.x.isFinite, centre.y.isFinite
      else {
        notes.append("\(label): a \(item.category.rawValue) drawn with no size was left out.")
        continue
      }
      counters.furniture += 1
      let angleDeg: Double = item.angleDeg.isFinite ? normalizedDegrees(-item.angleDeg) : 0
      furniture.append(
        SketchMeasurements.Furniture(
          id: "furniture-\(counters.furniture)", category: item.category,
          x: micrometres(centre.x / 1000), z: micrometres(-centre.y / 1000),
          widthM: micrometres(width), depthM: micrometres(depth),
          angleDeg: rounded(angleDeg, places: 6)))
    }

    return SketchMeasurements.Room(
      id: "room-\(roomIndex + 1)", label: label, type: drawing.type, walls: walls,
      diagonals: diagonals, openings: openings, placement: placement,
      furniture: furniture.isEmpty ? nil : furniture)
  }

  /// A rectilinear room's lengths along each axis (the solver's closure rule, spec F14 1.4):
  /// the one wall on an axis not written on the sketch, when the axis has a written dimension,
  /// is left to the solver to derive from closure; otherwise the walls not written take the
  /// drawn proportions, adjusted together so the axis closes and the written values stay as
  /// written.
  private func close(
    turns: [SketchTurn], fixed: [SketchMeasurements.Length?], fromSketch: [Bool],
    lengths: inout [Double], leftToClosure: inout [Bool]
  ) {
    let m = turns.count
    var headings: [Int] = []
    var heading = 0
    for index in 0..<m {
      headings.append(heading)
      heading = (heading + (turns[index] == .right ? 3 : 1)) % 4
    }
    func sign(_ index: Int) -> Double { headings[index] < 2 ? 1 : -1 }

    for axis in 0..<2 {
      let onAxis = (0..<m).filter { headings[$0] % 2 == axis }
      let open = onAxis.filter { fixed[$0] == nil }
      guard !open.isEmpty else { continue }
      if open.count == 1, onAxis.contains(where: { fromSketch[$0] }) {
        let unknown = open[0]
        var others = 0.0
        for index in onAxis where index != unknown {
          others += sign(index) * lengths[index]
        }
        let derived: Double = -sign(unknown) * others
        if derived >= 1 {
          lengths[unknown] = derived
          leftToClosure[unknown] = true
          continue
        }
      }
      var residual = 0.0
      for index in onAxis {
        residual += sign(index) * lengths[index]
      }
      let total = open.reduce(0.0) { $0 + lengths[$1] }
      guard total > 0 else { continue }
      var adjusted = lengths
      var usable = true
      for index in open {
        let share: Double = residual * lengths[index] / total
        let moved: Double = lengths[index] - sign(index) * share
        if moved < 1 {
          usable = false
          break
        }
        adjusted[index] = moved
      }
      if usable { lengths = adjusted }
    }
  }

  // MARK: - Ceiling

  /// Section 4.5: the ceiling height written on the sketch, with its label when the dimension
  /// list has it.
  private func ceiling() -> SketchMeasurements.Length? {
    guard let height = reading.ceilingHeightMm, height.isFinite, height > 0 else { return nil }
    let label = reading.dimensions.first { dimension in
      guard dimension.room == nil || dimension.wall == nil, let value = dimension.valueMm else {
        return false
      }
      return abs(value - height) <= 1
    }
    return written(text: label?.text, valueMm: height)
  }

  // MARK: - Lengths

  /// A length written on the sketch: its text as written in the drawing's units (generated in
  /// the display units when the text cannot be kept), measured.
  private func written(text: String?, valueMm: Double) -> SketchMeasurements.Length {
    let value = rounded(valueMm, places: 1)
    let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !trimmed.isEmpty, trimmed.count <= 40 else {
      return SketchMeasurements.Length(
        valueMm: value, enteredUnit: SketchReadingText.unit(displayUnits),
        enteredText: SketchReadingText.text(value, units: displayUnits), measured: true)
    }
    let unit: EnteredUnit
    switch reading.dimensionUnits {
    case .imperial: unit = .ftIn
    case .metric: unit = .mm
    case .none: unit = SketchReadingText.unit(displayUnits)
    }
    return SketchMeasurements.Length(
      valueMm: value, enteredUnit: unit, enteredText: trimmed, measured: true)
  }

  /// A length the drawing gives by proportion: estimated, in the display units.
  private func estimate(_ valueMm: Double) -> SketchMeasurements.Length {
    let value = max(rounded(valueMm, places: 1), 0.1)
    return SketchMeasurements.Length(
      valueMm: value, enteredUnit: SketchReadingText.unit(displayUnits),
      enteredText: SketchReadingText.text(value, units: displayUnits), measured: false)
  }

  private func roomLabel(_ roomIndex: Int) -> String {
    guard reading.rooms.indices.contains(roomIndex) else { return "Room \(roomIndex + 1)" }
    let trimmed = reading.rooms[roomIndex].label.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "Room \(roomIndex + 1)" : String(trimmed.prefix(100))
  }
}

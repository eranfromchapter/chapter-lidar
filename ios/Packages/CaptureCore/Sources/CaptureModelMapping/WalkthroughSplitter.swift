import CaptureContract

/// Splits a walk-through scan into rooms (floorplan plan, phase 3).
///
/// A walk-through is one `CapturedRoom` for a whole apartment: one floor outline, many walls, and
/// a section (a label and a centre, no shape) per room RoomPlan recognized. The splitter builds the
/// planar arrangement of the floor outline and the interior walls (ends welded, short gaps
/// closed), traces its faces, and lets the sections decide: a face with two or more sections is
/// cut along the cheapest structural cue (a reflex corner, a wall stub), a face without a section
/// is kept as a room when it is enclosed or holds a defining object (a closet, a second
/// bathroom), and anything else merges into a neighbour. It then splits the walls where rooms meet
/// and places every opening and object in a room.
///
/// Pure and deterministic: plain Double arithmetic in a fixed order, no trig, no hashing order,
/// so the result is the same on Linux and on Apple platforms. `split` returns nil when the capture
/// is not a walk-through or the split does not validate; the mapper then maps the capture as one
/// room, as before.
public enum WalkthroughSplitter {
  /// Tolerances and weights, in metres and square metres. The defaults are the tuned values.
  public struct Parameters: Sendable, Equatable {
    /// Weld and snap tolerance. Retried at half and a quarter when the arrangement fails its check.
    public var eps = 0.05
    /// A wall within this of a parallel outline edge (4 of 5 samples) is an outline wall.
    public var outlineTolerance = 0.15
    /// Interior walls parallel within 5 degrees and this close are near-duplicates ...
    public var duplicateLateral = 0.10
    /// ... when they overlap by at least this fraction of the shorter.
    public var duplicateOverlap = 0.5
    /// A dangling end at most this far past a crossing is trimmed back to it.
    public var overshoot = 0.5
    /// Reach of a dangling end's ray, L-corner and cone.
    public var extend = 0.60
    /// A dangling end this close to another segment joins it.
    public var join = 0.15
    /// Longest closure that encloses a room without a section.
    public var enclose = 1.20
    /// Longest ray in a cut.
    public var cutMax = 6.0
    /// Longest bridge, or gap in a chain of stubs, in a cut.
    public var bridgeMax = 2.5
    /// A floating stub within this of a stub's line continues it.
    public var chainLateral = 0.15
    /// Smallest piece, with a seed or enclosed, a cut may leave.
    public var minPiece = 1.0
    /// A section centre outside the outline by at most this is moved into the nearest face.
    public var sectionSnap = 0.75
    /// A typed section moves to a face with its defining objects within this.
    public var relocate = 1.0
    /// A kitchen object seed is at least this far from every seed of its face.
    public var objectSeedDistance = 2.0
    /// Shared boundary vertices within this of their chord are dropped.
    public var simplifyTolerance = 0.005
    /// Offset of the samples on either side of a wall that find its rooms.
    public var side = 0.10
    /// A room edge crossing a wall at a sine above this splits the wall.
    public var junctionSin = 0.2
    /// A room vertex within this of a wall splits it.
    public var junctionNear = 0.15
    /// Shorter wall pieces fold into the longer neighbour.
    public var minWallPiece = 0.15
    /// Score: minus this times the wall length a cut follows.
    public var realBonus = 0.5
    /// Score: virtual length times (1 + this times the sine off the nearest axis beyond 1 degree).
    public var axisWeight = 4.0
    /// Score: plus `nearWeight` times (this minus the distance) for a seed closer to the cut.
    public var nearSection = 0.75
    public var nearWeight = 4.0
    /// A cut longer than this inside an object footprint crosses the object.
    public var objectCross = 0.15
    /// Score: crossing a sofa or table, or another object that does not define a room type.
    public var objectPenaltyBig = 1.5
    public var objectPenaltySmall = 0.5
    /// Footprints shrink by this before the defining-object veto ...
    public var vetoShrink = 0.05
    /// ... and by this before the object penalty.
    public var penaltyShrink = 0.08
    /// A face without a seed that is smaller, or thinner (2A/P), always merges.
    public var sliverArea = 0.5
    public var sliverWidth = 0.25
    /// A face without a seed is kept as a room when at most this fraction of its boundary is
    /// virtual (cuts and closures).
    public var enclosedVirtual = 0.25
    /// Shape typing of a room without a type: at most this area is a closet ...
    public var closetMax = 2.5
    /// ... and a short side of at most this, with a long side at least `hallAspect` times it, a
    /// hallway.
    public var hallWidth = 1.6
    public var hallAspect = 2.0
    /// Height of a room without walls when the scan's median wall height is not above 0.
    public var heightDefault = 2.4
    /// A cut whose margin to a materially different cut is below this is marked approximate.
    public var approximateMargin = 0.6
    /// Two cuts give the same partition when no seed's piece differs by more than
    /// max(`samePartitionAbsolute`, `samePartitionRelative` of the larger).
    public var samePartitionAbsolute = 0.25
    public var samePartitionRelative = 0.02
    /// A kitchen seed from two or more kinds of appliance when no section is a kitchen.
    public var kitchenObjectSeeds = true

    public init() {}
  }

  /// How a wall end that stopped short was closed.
  public enum ClosureMethod: String, Sendable, Equatable {
    case join, ray, corner, cone, unclosed
  }

  public struct DanglingEnd: Sendable, Equatable {
    /// Source wall index.
    public var wall: Int
    public var method: ClosureMethod
    /// Length of the closure; nil when the end stayed open.
    public var gapM: Double?
  }

  /// An applied cut or enclosure.
  public struct CutDecision: Sendable, Equatable {
    /// Labels of the seeds of the face (`object:kitchen` for a kitchen object seed).
    public var seedLabels: [String]
    /// Kind of candidate, for example `reflex-ray` or `stub-stub`.
    public var tag: String
    public var virtualLengthM: Double
    /// Length of wall stubs the cut follows.
    public var wallLengthM: Double
    public var score: Double
    /// Score difference to the best candidate that splits the face materially differently; nil
    /// when there is none.
    public var margin: Double?
    /// The margin is below `Parameters.approximateMargin`: another split was nearly as good.
    public var approximate: Bool
    public var pieceAreasM2: [Double]
  }

  public struct Merge: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
      /// A thin or tiny face without a section.
      case sliver
      /// A face without a section that is not enclosed and holds no defining object.
      case sectionless
      /// A room inside another room.
      case enclosed
    }

    public var kind: Kind
    public var areaM2: Double
    public var virtualFraction: Double
  }

  public enum FallbackReason: String, Sendable, Equatable {
    case notWalkthrough, arrangementCheck, noSeeds, finalCheck, singleRoom, validation
    case openingWithoutWall
  }

  /// What the splitter did, for tests, logs and the Rooms screen. Not part of the contract.
  public struct Diagnostics: Sendable, Equatable {
    public var eps = 0.0
    /// The dominant wall direction (x, z); the other axis is at right angles.
    public var axis: [Double] = []
    public var outlineWalls: [Int] = []
    public var interiorWalls: [Int] = []
    public var initialFaceAreasM2: [Double] = []
    public var dangling: [DanglingEnd] = []
    public var duplicatesMerged = 0
    public var overshootsTrimmed = 0
    /// Section indexes.
    public var sectionsSnapped: [Int] = []
    public var sectionsIgnored: [Int] = []
    public var sectionsRelocated: [Int] = []
    public var objectSeeds = 0
    public var cuts: [CutDecision] = []
    /// Seed labels of faces left with two or more seeds (no valid cut).
    public var unsplit: [[String]] = []
    public var enclosures: [CutDecision] = []
    public var merges: [Merge] = []
    public var simplifiedShared = 0
    public var simplifiedCollinear = 0
    /// Identifiers of openings that reach past the end of their wall piece.
    public var straddlingOpenings: [String] = []
    public var fallbackReason: FallbackReason?

    public init() {}
  }

  /// A walk-through split into rooms, with everything the capture model needs.
  public struct Split: Sendable {
    public struct Room: Sendable {
      /// Floor outline at floor level, counter-clockwise seen from +Y (the contract winding).
      public var polygon: [Vector3]
      public var areaM2: Double
      public var typing: RoomTyping.Result
      public var heightM: Double
      /// False when no wall bounds the room and it got the scan's median wall height.
      public var heightFromWalls: Bool
      /// Sections inside the room (positions in `RoomPlanRoom.sections`).
      public var sectionIndexes: [Int]
      /// Ring in the plan, counter-clockwise there.
      var ring: [P2]
    }

    /// A piece of a source wall between room junctions.
    public struct WallPiece: Sendable {
      /// Position of the source wall in `RoomPlanRoom.walls`.
      public var sourceWall: Int
      /// Along the source wall from its start, in metres.
      public var startM: Double
      public var endM: Double
      public var start: Vector3
      public var end: Vector3
      /// Indexes into `rooms`, ascending.
      public var rooms: [Int]
    }

    public struct OpeningPlacement: Sendable {
      /// Index into `wallPieces`.
      public var piece: Int
      /// Along the piece from its start, in metres.
      public var offsetM: Double
    }

    public var rooms: [Room]
    public var wallPieces: [WallPiece]
    public var doors: [OpeningPlacement]
    public var windows: [OpeningPlacement]
    public var openings: [OpeningPlacement]
    /// Index into `rooms` per object, in document order.
    public var objectRooms: [Int]
    public var diagnostics: Diagnostics
  }

  /// The split of `document`, or nil when it is not a walk-through or the split fails (the mapper
  /// then maps it as before). `placements` are the mapper's pass-1 walls, in document order.
  public static func split(
    document: RoomPlanDocument, placements: [WallPlacement], parameters: Parameters = Parameters()
  ) -> Split? {
    analyze(document: document, placements: placements, parameters: parameters).split
  }

  /// `split`, with the diagnostics also when it fails.
  public static func analyze(
    document: RoomPlanDocument, placements: [WallPlacement], parameters: Parameters = Parameters()
  ) -> (split: Split?, diagnostics: Diagnostics) {
    var diagnostics = Diagnostics()
    let split = run(document, placements, parameters, &diagnostics)
    return (split, diagnostics)
  }

  private static func run(
    _ document: RoomPlanDocument, _ placements: [WallPlacement], _ p: Parameters,
    _ diagnostics: inout Diagnostics
  ) -> Split? {
    func fail(_ reason: FallbackReason) -> Split? {
      diagnostics.fallbackReason = reason
      return nil
    }
    guard WalkthroughInput.isWalkthrough(document),
      let plan = WalkthroughInput.plan(of: document, placements: placements),
      plan.walls.count == document.rooms[0].walls.count
    else { return fail(.notWalkthrough) }

    // Segments and the first arrangement, welded at eps, eps/2 or eps/4.
    var eps = p.eps
    var first: (segments: WalkthroughSegments, arrangement: PlanArrangement)?
    for _ in 0..<3 {
      let segments = WalkthroughSegments(plan: plan, parameters: p, eps: eps)
      let arrangement = PlanArrangement(
        segments: segments.segments, eps: eps, boundary: plan.outline)
      if arrangement.selfCheck() {
        first = (segments, arrangement)
        break
      }
      eps /= 2
    }
    guard let first else { return fail(.arrangementCheck) }
    diagnostics.eps = eps
    diagnostics.outlineWalls = first.segments.outlineWalls
    diagnostics.interiorWalls = first.segments.interiorWalls
    diagnostics.dangling = first.segments.dangling
    diagnostics.duplicatesMerged = first.segments.duplicatesMerged
    diagnostics.overshootsTrimmed = first.segments.overshootsTrimmed
    diagnostics.initialFaceAreasM2 = first.arrangement.faces.indices.map {
      Plan2D.area(first.arrangement.polygon($0))
    }
    let axes = PlanAxes(walls: plan.walls.map { ($0.a, $0.b) })
    diagnostics.axis = [axes.u.x, axes.u.y]

    let seeds = WalkthroughSeeds.make(
      arrangement: first.arrangement, plan: plan, parameters: p, diagnostics: &diagnostics)
    guard !seeds.isEmpty else { return fail(.noSeeds) }

    let cuts = WalkthroughCuts(plan: plan, parameters: p, axes: axes, eps: eps)
    let separated = cuts.separate(first.segments.segments, seeds: seeds, diagnostics: &diagnostics)
    let enclosed = cuts.enclose(separated.segments, seeds: seeds, diagnostics: &diagnostics)
    let arr = enclosed.arrangement
    guard arr.selfCheck() else { return fail(.finalCheck) }

    // Rooms.
    var grouping = WalkthroughRooms(arrangement: arr)
    let byFace = WalkthroughSeeds.byFace(arr, seeds)
    grouping.resolve(
      seedFaces: Set(byFace.indices.filter { !byFace[$0].isEmpty }), plan: plan, parameters: p,
      diagnostics: &diagnostics)
    let rings = grouping.simplifiedRings(
      tolerance: p.simplifyTolerance, diagnostics: &diagnostics)
    let sectionSeeds = seeds.filter { !$0.isObjectSeed }
    var candidates: [(key: (Int, Double, Int), ring: [P2])] = []
    for root in grouping.roots() {
      let ring = (rings[root] ?? []).map { arr.points[$0] }
      let inside = sectionSeeds.filter { Plan2D.contains(ring, $0.at) }.compactMap(\.sectionIndex)
      let roundedArea = (Plan2D.area(ring) * 1e6).rounded(.toNearestOrEven) / 1e6
      candidates.append(((inside.min() ?? Int.max, -roundedArea, root), ring))
    }
    candidates.sort { $0.key < $1.key }
    let ringsInOrder = candidates.map(\.ring)

    // Validation.
    guard ringsInOrder.count >= 2 else { return fail(.singleRoom) }
    let outlineArea = Plan2D.area(plan.outline)
    var areaSum = 0.0
    for ring in ringsInOrder { areaSum += Plan2D.area(ring) }
    guard ringsInOrder.allSatisfy(Plan2D.isSimple),
      abs(areaSum - outlineArea) <= 1e-6 * max(1, outlineArea),
      sectionSeeds.allSatisfy({ seed in
        ringsInOrder.filter { Plan2D.contains($0, seed.at) }.count == 1
      })
    else { return fail(.validation) }

    // Types: RoomTyping on the sections and objects inside, then the shape of a room it leaves
    // without a type.
    let sections = sectionSeeds.map {
      RoomPlanSection(
        label: $0.label, story: $0.story, center: Vector3($0.at.x, $0.centerY, $0.at.y))
    }
    let objects = plan.objects.map { RoomTyping.Object(category: $0.category, center: $0.center3) }
    var rooms: [Split.Room] = []
    for ring in ringsInOrder {
      let polygon = PolygonMath.counterClockwise(ring.map { Vector3($0.x, plan.floorY, $0.y) })
      var typing = RoomTyping.type(polygon: polygon, sections: sections, objects: objects)
      if typing == .unknown {
        let area = Plan2D.area(ring)
        let rect = Plan2D.minRect(ring)
        if area <= p.closetMax {
          typing = .typed(.closet, .inferred)
        } else if rect.short <= p.hallWidth, rect.long >= p.hallAspect * rect.short {
          typing = .typed(.hallway, .inferred)
        }
      }
      rooms.append(
        Split.Room(
          polygon: polygon, areaM2: Plan2D.area(ring), typing: typing, heightM: 0,
          heightFromWalls: false,
          sectionIndexes: sectionSeeds.filter { Plan2D.contains(ring, $0.at) }.compactMap(
            \.sectionIndex),
          ring: ring))
    }

    // Walls, openings, objects and heights.
    let downstream = WalkthroughDownstream(plan: plan, rooms: rooms.map(\.ring), parameters: p)
    let pieces = downstream.wallPieces()
    for (index, height) in downstream.heights(pieces: pieces).enumerated() {
      rooms[index].heightM = height.heightM
      rooms[index].heightFromWalls = height.fromWalls
    }
    let room = document.rooms[0]
    var placed: [[Split.OpeningPlacement]] = []
    for surfaces in [room.doors, room.windows, room.openings] {
      var list: [Split.OpeningPlacement] = []
      for surface in surfaces {
        guard
          let placement = downstream.place(
            surface, placements: placements, pieces: pieces, diagnostics: &diagnostics)
        else { return fail(.openingWithoutWall) }
        list.append(placement)
      }
      placed.append(list)
    }
    return Split(
      rooms: rooms, wallPieces: pieces, doors: placed[0], windows: placed[1], openings: placed[2],
      objectRooms: downstream.objectRooms(), diagnostics: diagnostics)
  }
}

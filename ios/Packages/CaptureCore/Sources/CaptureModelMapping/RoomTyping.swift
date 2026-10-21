import CaptureContract

/// Room types and labels from what RoomPlan reports: the section labels inside a room, or else
/// the objects in it. Pure and deterministic; `CaptureModelMapper` applies it to every room.
///
/// Points are tested in plan (x, z) against the room's floor polygon. Section centres and object
/// transforms are in the same RoomPlan frame as the walls and floors, which the mapper keeps as
/// the capture frame, so they are used as they are.
public enum RoomTyping {
  /// What the typing found for one room.
  public enum Result: Hashable, Sendable {
    /// A known type and where it came from.
    case typed(RoomType, RoomTypeSource)
    /// Sections of two or more types inside the room: a walk-through scan that RoomPlan reports
    /// as one room. It gets no type, so the report does not claim one; phase 3 of the floorplan
    /// plan splits such a room into its rooms.
    case mixed
    /// No usable section and no object that tells the type.
    case unknown

    public var type: RoomType? {
      if case .typed(let type, _) = self { return type }
      return nil
    }

    public var source: RoomTypeSource? {
      if case .typed(_, let source) = self { return source }
      return nil
    }
  }

  /// An object as the typing sees it: its category and the centre of its footprint.
  public struct Object: Hashable, Sendable {
    public var category: ObjectCategory
    public var center: Vector3

    public init(category: ObjectCategory, center: Vector3) {
      self.category = category
      self.center = center
    }
  }

  /// The type of the room with floor outline `polygon`. Only sections and objects inside the
  /// polygon count, and `unidentified` sections are ignored:
  /// - exactly one section: its type, from `roomplan_section`;
  /// - two or more sections, even of one type (two bedrooms): `mixed`, because RoomPlan reports
  ///   one section per room it recognises;
  /// - no usable section: the type the objects point to (`inferredType(from:)`), `inferred`; but
  ///   `mixed` when the objects belong to two or more kinds of room (`isMixed(_:)`), for example
  ///   a toilet, a bed and a stove in one walk-through scan.
  public static func type(polygon: [Vector3], sections: [RoomPlanSection], objects: [Object])
    -> Result
  {
    var sectionTypes: [RoomType] = []
    for section in sections {
      guard let type = section.roomType, let center = section.center,
        PolygonMath.contains(polygon, center)
      else { continue }
      sectionTypes.append(type)
    }
    if sectionTypes.count > 1 { return .mixed }
    if let type = sectionTypes.first { return .typed(type, .roomplanSection) }
    let inside = objects.filter { PolygonMath.contains(polygon, $0.center) }.map(\.category)
    if isMixed(inside) { return .mixed }
    return inferredType(from: inside).map { .typed($0, .inferred) } ?? .unknown
  }

  /// Objects that only one kind of room has: a toilet or bathtub, a stove, oven, refrigerator or
  /// dishwasher, a bed. Sofas, televisions, tables and chairs are left out because they also
  /// stand in bedrooms, kitchens and living rooms.
  static let defining: [(categories: Set<ObjectCategory>, type: RoomType)] = [
    ([.toilet, .bathtub], .bathroom),
    ([.stove, .oven, .refrigerator, .dishwasher], .kitchen),
    ([.bed], .bedroom),
  ]

  /// True when the objects belong to two or more kinds of room (`defining`).
  static func isMixed(_ categories: [ObjectCategory]) -> Bool {
    let present = Set(categories)
    return defining.filter { !$0.categories.isDisjoint(with: present) }.count > 1
  }

  /// The type a room's objects point to. The first rule that matches wins:
  /// toilet or bathtub: bathroom; stove, oven, refrigerator or dishwasher: kitchen; bed: bedroom;
  /// washer-dryer: laundry; sofa, television or fireplace: living room. Nil when none matches.
  /// A table with chairs says nothing: RoomPlan reports a desk and office chairs the same way
  /// (field test, 2026-10-19: an office came out as "Dining Room").
  public static func inferredType(from categories: [ObjectCategory]) -> RoomType? {
    let present = Set(categories)
    let rules: [(categories: Set<ObjectCategory>, type: RoomType)] = [
      ([.toilet, .bathtub], .bathroom),
      ([.stove, .oven, .refrigerator, .dishwasher], .kitchen),
      ([.bed], .bedroom),
      ([.washerDryer], .laundry),
      ([.sofa, .television, .fireplace], .livingRoom),
    ]
    return rules.first(where: { !$0.categories.isDisjoint(with: present) })?.type
  }

  /// The room type the operator's own name for a floor, an area or a room says, for example
  /// "Office", "Kitchen", "Primary bedroom" or "Shower"; nil when the name names no room
  /// ("Floor 1", "Apartment", "Room Mexico"). Whole words, ignoring case; the first match in
  /// this order wins, so "Hall bath" is a bathroom, "Living / dining" a living room and
  /// "Kitchen pantry" a kitchen. RoomPlan has no shower or bathtub-only room: a shower or a tub
  /// on its own is a bathroom, and a pantry or a storage room a closet.
  public static func areaType(_ label: String) -> RoomType? {
    let words = Set(
      label.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
    let rules: [(words: Set<String>, type: RoomType)] = [
      (
        [
          "bathroom", "bath", "wc", "toilet", "powder", "ensuite", "restroom", "washroom", "shower",
          "tub", "bathtub", "lavatory",
        ], .bathroom
      ),
      (["bedroom", "nursery"], .bedroom),
      (["kitchen", "kitchenette"], .kitchen),
      (["closet", "wardrobe", "pantry", "storage", "cupboard"], .closet),
      (["laundry"], .laundry),
      (["utility", "mechanical", "boiler"], .utility),
      (["office", "study"], .office),
      (["living", "lounge", "family", "den"], .livingRoom),
      (["dining"], .diningRoom),
      (["hall", "hallway", "corridor", "entry", "foyer", "entrance", "vestibule", "passage"], .hallway),
    ]
    return rules.first(where: { !$0.words.isDisjoint(with: words) })?.type
  }

  /// The operator names the room when a capture has a single room: if `captureLabel` names a
  /// room type (`areaType(_:)`), that room takes it, with source `operator`, and `labels(for:)`
  /// uses the operator's name as its label. The operator stood in the room, so this wins over
  /// RoomPlan's section and the objects. Captures of two or more rooms are returned unchanged.
  public static func namedByOperator(_ results: [Result], captureLabel: String) -> [Result] {
    guard results.count == 1, let type = areaType(captureLabel) else { return results }
    return [.typed(type, .operator)]
  }

  /// The types after the operator renamed rooms: a room whose override (`overrides[i]`, as for
  /// `labels(for:captureLabel:overrides:)`) differs from the label the room would get without
  /// it, and names a room type (`areaType(_:)`), takes that type with source `operator`: the
  /// operator stood in it, so "Shower" makes a bathroom of what the shape alone called a closet.
  /// A name that names no type ("Guest suite"), a blank one, or one equal to the derived label
  /// (compared as labels are compared for uniqueness) leaves the room's own result.
  ///
  /// Labels are numbered from `results`, not from this, so renaming one room never renumbers
  /// the others: call `labels(for:captureLabel:overrides:)` with the same `results`.
  public static func renamedByOperator(
    _ results: [Result], captureLabel: String, overrides: [String]
  ) -> [Result] {
    guard overrides.contains(where: { !isBlank($0) }) else { return results }
    let derived = labels(for: results, captureLabel: captureLabel)
    return results.indices.map { index in
      guard overrides.indices.contains(index), !isBlank(overrides[index]),
        key(overrides[index]) != key(derived[index]),
        let type = areaType(overrides[index])
      else { return results[index] }
      return .typed(type, .operator)
    }
  }

  /// The label of a room of `type`; nil for `other`, which is labelled like a room of unknown
  /// type.
  public static func label(of type: RoomType) -> String? {
    switch type {
    case .livingRoom: return "Living Room"
    case .diningRoom: return "Dining Room"
    case .kitchen: return "Kitchen"
    case .bedroom: return "Bedroom"
    case .bathroom: return "Bathroom"
    case .closet: return "Closet"
    case .hallway: return "Hallway"
    case .laundry: return "Laundry"
    case .office: return "Office"
    case .utility: return "Utility"
    case .other: return nil
    }
  }

  /// Labels of a capture's rooms, in room order, from each room's typing `results`:
  /// - the single room of a capture the operator named (`namedByOperator(_:captureLabel:)`):
  ///   `captureLabel`;
  /// - a typed room: the label of its type, for example `Bedroom`; when two or more rooms of the
  ///   capture have that type they are numbered in room order: `Bedroom 1`, `Bedroom 2`;
  /// - a mixed room: `captureLabel` (for example `Apartment`), numbered the same way;
  /// - type `other` or no type: `Room N`, N being the room's 1-based position.
  /// Numbering counts every room, also one whose label is overridden, so renaming one room does
  /// not renumber the others.
  ///
  /// `overrides[i]`, when given and not blank, replaces the label of room i. Labels are unique
  /// within the capture, compared ignoring case and repeated spaces as the station's photo
  /// coverage check compares them: a label already used gets ` 2`, ` 3` and so on, and a derived
  /// label gives way to an override.
  ///
  /// When a label and its number would be longer than `maximumLabelLength`, the label is
  /// shortened so the number fits (see `label(_:number:)`).
  public static func labels(
    for results: [Result], captureLabel: String, overrides: [String] = []
  ) -> [String] {
    let bases: [String?] = results.map { result in
      switch result {
      case .typed(let type, .operator) where results.count == 1:
        return isBlank(captureLabel) ? label(of: type) : captureLabel
      case .typed(let type, _): return label(of: type)
      case .mixed: return isBlank(captureLabel) ? nil : captureLabel
      case .unknown: return nil
      }
    }
    var totals: [String: Int] = [:]
    for case let base? in bases { totals[base, default: 0] += 1 }
    var numbered: [String: Int] = [:]
    let derived = bases.enumerated().map { index, base -> String in
      guard let base else { return "Room \(index + 1)" }
      guard totals[base, default: 0] > 1 else { return base }
      numbered[base, default: 0] += 1
      return label(base, number: numbered[base, default: 0])
    }

    let overridden: [String?] = results.indices.map { index in
      guard overrides.indices.contains(index), !isBlank(overrides[index]) else { return nil }
      return overrides[index]
    }
    let reserved = Set(overridden.compactMap { $0.map(key) })
    var taken: Set<String> = []
    var labels: [String] = []
    for (index, derivedLabel) in derived.enumerated() {
      var label = overridden[index] ?? derivedLabel
      let isUsed = { (candidate: String) -> Bool in
        taken.contains(key(candidate))
          || (overridden[index] == nil && reserved.contains(key(candidate)))
      }
      if isUsed(label) {
        let base = label
        var suffix = 2
        repeat {
          label = Self.label(base, number: suffix)
          suffix += 1
        } while isUsed(label) || reserved.contains(key(label))
      }
      taken.insert(key(label))
      labels.append(label)
    }
    return labels
  }

  /// The longest room label the capture-model schema allows (`room.label` maxLength 100),
  /// counted in Unicode scalars as JSON Schema counts it. A label within it is also within the
  /// 100 characters the app allows for a photo's room label.
  public static let maximumLabelLength = 100

  /// `base`, a space and `number`, for example `Bedroom 2`. When that would be longer than
  /// `maximumLabelLength` Unicode scalars, whole characters are dropped from the end of `base`,
  /// and then any white space left at its end, so the number fits. A capture label can be 100
  /// characters, and two mixed rooms would otherwise make `<label> 1` and `<label> 2` too long
  /// for the schema and for photo labels.
  static func label(_ base: String, number: Int) -> String {
    let suffix = " \(number)"
    let available = maximumLabelLength - suffix.unicodeScalars.count
    guard base.unicodeScalars.count > available else { return base + suffix }
    var shortened = Substring(base)
    var length = base.unicodeScalars.count
    while length > available, let last = shortened.popLast() {
      length -= last.unicodeScalars.count
    }
    while shortened.last?.isWhitespace == true { shortened.removeLast() }
    return String(shortened) + suffix
  }

  /// A label as the uniqueness rule compares it: lower case, runs of white space as one space.
  static func key(_ label: String) -> String {
    label.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

  private static func isBlank(_ text: String) -> Bool {
    text.allSatisfy(\.isWhitespace)
  }
}

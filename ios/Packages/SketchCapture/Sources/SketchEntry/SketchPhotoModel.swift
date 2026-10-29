#if canImport(Observation)
  import CaptureContract
  import Foundation
  import Observation
  import SketchReading
  import SketchSolver

  /// Where "Photograph a sketch" stands (spec F16 2). Step 1 (New capture) and step 2 (How to
  /// measure, with the floor, mode and units) are the host's.
  public enum SketchPhotoPhase: Sendable, Equatable {
    /// Step 3 of 5: take the photo, or choose it from Photos or Files.
    case source
    /// Step 4 of 5: the station (Claude) reads the photo.
    case reading
    /// The photo is not a floor plan, or could not be read (`problem` says why): retake it or
    /// enter the sketch by hand.
    case problem
    /// Step 4 of 5: the sketch has no written dimensions; the operator taps one wall and types
    /// its length.
    case oneLength
    /// Step 5 of 5: Check, with the 3D preview.
    case check
    case finished
  }

  /// Words of the sketch photo screens, so the screens and the tests agree.
  public enum SketchPhotoText {
    public static let sourceTitle = "Photograph the sketch"
    public static let readingTitle = "Reading your sketch\u{2026}"
    public static let readingSubtitle =
      "Claude is reading the rooms, doors, windows, furniture and any written dimensions. This "
      + "usually takes 10 to 40 seconds."
    public static let notAPlanTitle = "This photo is not a floor plan"
    public static let unreadableTitle = "The sketch could not be read"
    public static let retake = "Retake the photo"
    public static let enterByHand = "Enter it by hand"
    public static let lengthTitle = "One length"
    public static let lengthQuestion = "Tap a wall you know, then type its length"
    public static let lengthFooter =
      "The sketch has no written dimensions. Every other length follows the drawing's "
      + "proportions and is marked estimated."
    public static let chooseWall = "Tap a wall on the plan"
    public static let enterLength = "Enter the wall's length"
    /// The field-test build without an API key answers a fixed reading.
    public static let demoNotice = "Demo reading: add an API key to read real sketches"
  }

  /// The photo as it goes to the reader: JPEG or PNG bytes (HEIC and PDF converted, the longer
  /// side at most 2048 px) and their MIME type. The original bytes are kept unchanged for the
  /// package.
  public struct SketchPhotoUploadImage: Sendable, Equatable {
    public var data: Data
    public var mediaType: String

    public init(data: Data, mediaType: String) {
      self.data = data
      self.mediaType = mediaType
    }
  }

  /// State and actions behind "Photograph a sketch" (spec F16 2): the photo (kept as taken),
  /// the reading the station returns, the one length when the sketch has no written dimensions,
  /// the converted F14 measurements and the solver's result for Check. The screens only read
  /// this and call its methods, so the flow runs in tests without a view.
  @MainActor
  @Observable
  public final class SketchPhotoModel {
    public private(set) var phase: SketchPhotoPhase = .source
    public let visitId: LowercaseUUID
    public let captureId: LowercaseUUID
    /// From How to measure: the capture record's label, area key, mode and units.
    public let floorLabel: String
    public let areaKey: String
    public let mode: CaptureMode
    public let displayUnits: DisplayUnitSystem
    /// Shown on the reading screens when set (the demo reading of a field-test build).
    public let notice: String?

    /// The photo exactly as taken or imported; written unchanged as `sketch.<ext>`.
    public private(set) var image: SketchImageSelection?
    /// Hand sketch (camera, Photos) or existing plan (a file).
    public private(set) var sourceKind: SketchSourceKind = .handSketch
    /// What Claude read; kept as `sketch-interpretation.json`.
    public private(set) var interpretation: SketchInterpretation?
    /// Why the photo could not be used (phase `.problem`).
    public private(set) var problem: String?
    /// The problem is "not a floor plan" (else the reading failed).
    public private(set) var problemIsNotAPlan = false

    /// The drawn walls of the one-length step.
    public private(set) var drawnWalls: [DrawnWall] = []
    /// The wall the operator tapped (`DrawnWall.id`).
    public var selectedWallId: String?
    /// Its length, in the capture's long unit.
    public var length: SketchLengthField

    public private(set) var conversion: SketchReadingConversion?
    public private(set) var result: SketchSolveResult?
    public private(set) var solveError: String?
    /// Finish floor is writing the originals.
    public var isFinishing = false

    @ObservationIgnored private let interpreter: any SketchInterpreting
    @ObservationIgnored private let prepare: @Sendable (SketchImageSelection) throws -> SketchPhotoUploadImage
    @ObservationIgnored private var reading: Task<Void, Never>?
    /// Counts readings, so the answer of a cancelled one is dropped.
    @ObservationIgnored private var readingNumber = 0

    /// `prepare` turns the photo into what is sent (`SketchPhotoUpload.prepare` on the phone).
    public init(
      visitId: LowercaseUUID = LowercaseUUID(), captureId: LowercaseUUID = LowercaseUUID(),
      floorLabel: String, areaKey: String, mode: CaptureMode = .floor,
      displayUnits: DisplayUnitSystem = .imperial, notice: String? = nil,
      interpreter: any SketchInterpreting,
      prepare: @escaping @Sendable (SketchImageSelection) throws -> SketchPhotoUploadImage =
        SketchPhotoUpload.prepare
    ) {
      self.visitId = visitId
      self.captureId = captureId
      self.floorLabel = floorLabel
      self.areaKey = areaKey
      self.mode = mode
      self.displayUnits = displayUnits
      self.notice = notice
      self.interpreter = interpreter
      self.prepare = prepare
      self.length = SketchLengthField(unit: SketchUnits(display: displayUnits).long)
    }

    // MARK: Step 3: the photo

    /// Starts reading `selection` in the background (the screens call this).
    public func start(_ selection: SketchImageSelection, kind: SketchSourceKind = .handSketch) {
      reading?.cancel()
      reading = Task { [weak self] in await self?.read(selection, kind: kind) }
    }

    /// Reads `selection`: `.reading`, then `.oneLength` or `.check`, or `.problem`.
    public func read(_ selection: SketchImageSelection, kind: SketchSourceKind = .handSketch) async {
      readingNumber += 1
      let number = readingNumber
      image = selection
      sourceKind = selection.format == .pdf ? .existingPlan : (kind == .none ? .handSketch : kind)
      interpretation = nil
      conversion = nil
      result = nil
      solveError = nil
      problem = nil
      problemIsNotAPlan = false
      drawnWalls = []
      selectedWallId = nil
      length = SketchLengthField(unit: SketchUnits(display: displayUnits).long)
      phase = .reading
      do {
        let prepare = self.prepare
        let upload = try await Task.detached(priority: .userInitiated) { try prepare(selection) }.value
        let read = try await interpreter.interpret(imageData: upload.data, mediaType: upload.mediaType)
        guard number == readingNumber, phase == .reading else { return }
        guard read.reading.isFloorPlan else {
          throw SketchReadingError.notAFloorPlan(
            read.reading.problem ?? "Claude found no floor plan in the photo.")
        }
        interpretation = read
        drawnWalls = SketchReadingConverter.drawnWalls(read)
        if SketchReadingConverter.needsOneLength(read) {
          phase = .oneLength
        } else {
          convert(userLength: nil)
        }
      } catch {
        guard number == readingNumber, phase == .reading, !(error is CancellationError) else { return }
        fail(error)
      }
    }

    /// Cancel on "Reading your sketch…": back to choosing the photo.
    public func cancelReading() {
      readingNumber += 1
      reading?.cancel()
      reading = nil
      phase = .source
    }

    /// "Retake the photo", or Back from the one-length step: choose the photo again.
    public func retake() {
      readingNumber += 1
      reading?.cancel()
      reading = nil
      problem = nil
      phase = .source
    }

    private func fail(_ error: Error) {
      if case .notAFloorPlan(let why)? = error as? SketchReadingError {
        problem = why
        problemIsNotAPlan = true
      } else {
        problem = Self.message(for: error)
        problemIsNotAPlan = false
      }
      phase = .problem
    }

    /// The words of a failure: an error's own description, else the system's.
    static func message(for error: Error) -> String {
      if let error = error as? LocalizedError, let text = error.errorDescription { return text }
      let bridged = error as NSError
      if bridged.domain == NSURLErrorDomain || bridged.domain == NSCocoaErrorDomain {
        return error.localizedDescription
      }
      return String(describing: error)
    }

    // MARK: Step 4: one length

    /// True when the sketch has no written dimension that sets the scale.
    public var needsOneLength: Bool {
      interpretation.map(SketchReadingConverter.needsOneLength) ?? false
    }

    public var selectedWall: DrawnWall? {
      drawnWalls.first { $0.id == selectedWallId }
    }

    /// Selects a wall (a tap on the drawn plan).
    public func selectWall(_ id: String) {
      guard drawnWalls.contains(where: { $0.id == id }) else { return }
      selectedWallId = id
    }

    /// Why Continue is disabled on the one-length step; nil when enabled.
    public var lengthBlocker: String? {
      if selectedWall == nil { return SketchPhotoText.chooseWall }
      if length.length == nil { return SketchPhotoText.enterLength }
      return nil
    }

    public var lengthContinueTitle: String { lengthBlocker ?? "Continue" }

    /// Continue on the one-length step: the reading converted with the typed length, then Check.
    public func continueFromLength() {
      guard lengthBlocker == nil, let wall = selectedWall, let typed = length.length else { return }
      convert(
        userLength: UserScaleLength(
          roomIndex: wall.roomIndex, wallIndex: wall.wallIndex, length: typed))
    }

    /// Back from Check: the one length again when the sketch needed it, else choose the photo.
    public func backFromCheck() {
      guard phase == .check else { return }
      if needsOneLength {
        phase = .oneLength
      } else {
        retake()
      }
    }

    // MARK: Step 5: Check

    private func convert(userLength: UserScaleLength?) {
      guard let interpretation else { return }
      do {
        let converted = try SketchReadingConverter.convert(
          interpretation, userLength: userLength, visitId: visitId, captureId: captureId,
          areaKey: areaKey, displayUnits: displayUnits, sourceKind: sourceKind,
          imagePath: imagePath ?? "", interpretationPath: interpretationPath)
        conversion = converted
        solve()
        phase = .check
      } catch {
        fail(error)
      }
    }

    /// Solves the converted measurements; nil (and `solveError`) when the solver refuses them.
    @discardableResult
    public func solve() -> SketchSolveResult? {
      guard let measurements = conversion?.measurements else { return nil }
      do {
        let solved = try SketchSolver.solve(
          measurements, context: SketchSolveContext(label: floorLabel.isEmpty ? "Floor" : floorLabel))
        result = solved
        solveError = nil
        return solved
      } catch {
        result = nil
        solveError = (error as? SketchSolverError)?.description ?? String(describing: error)
        return nil
      }
    }

    /// The converter's notes (scale, dimensions used or dropped), shown before the solver's.
    public var leadingNotes: [String] {
      var notes = conversion?.notes ?? []
      if let notice { notes.insert(notice, at: 0) }
      return notes
    }

    /// "Complete" or "Limited" (an undimensioned sketch is always limited), "Not solved".
    public var completenessWord: String {
      guard let result else { return "Not solved" }
      return result.isLimited ? "Limited" : "Complete"
    }

    public var canFinish: Bool { result != nil && conversion != nil && !isFinishing }

    /// The F14 document written as `sketch-measurements.json`.
    public var measurements: SketchMeasurements? { conversion?.measurements }

    public func markFinished() {
      phase = .finished
    }

    // MARK: Paths

    /// `Original Exports/{areaKey}/{captureId}/sketch.jpg`; nil before a photo.
    public var imagePath: String? {
      image.map { SketchFloorWriter.packageFolder(areaKey: areaKey, captureId: captureId) + $0.fileName }
    }

    /// `Original Exports/{areaKey}/{captureId}/sketch-interpretation.json`.
    public var interpretationPath: String {
      SketchFloorWriter.packageFolder(areaKey: areaKey, captureId: captureId)
        + PackageLayout.sketchInterpretationFileName
    }
  }
#endif

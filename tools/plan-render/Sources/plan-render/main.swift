import CaptureContract
import CaptureModelMapping
import CoreGraphics
import Foundation
import ImageIO
import PlanExport
import UniformTypeIdentifiers

// plan-render: the plan sheet and the colour Floorplan of one scan, written with the current app
// code.
//
//   plan-render <roomplan.json | capture-model.json> <out-dir>
//               [--address <text>] [--units imperial|metric] [--title <text>]
//               [--label <capture label>] [--room-names <names.json>]
//               [--record <capture-record.json> --capture-id <id>] [--captured-at <ISO 8601>]
//
// A roomplan.json (the raw RoomPlan capture) is mapped as the phone's scan viewer maps it: with
// the capture's label (`--label`, default "Scan") and the operator's room names (`--room-names`:
// a JSON array of `RoomName`, the capture's entry of the visit's room-names.json), through
// `RoomNaming.map`. A capture-model.json is drawn as it is. Two pages, public API, nothing
// redrawn here:
//
// - the plan sheet (`PlanSheetWriter`, the Tabloid 11 x 17 in page the package carries):
//   plan-sheet.pdf and plan-sheet.png. Its title block comes from the capture record
//   (`--record`, the capture `--capture-id`, as `PlanExportContext(record:captureId:)`; the raw
//   scan is then mapped with the record's visit and capture ids, as the package maps it).
//   Without a record, or when the record cannot be read or does not hold the capture, it is
//   `PlanExportContext(unrecordedScan:)`: "not recorded" for the deal, capture id, operator,
//   device and mode, the `--address` if any, "No compass reading", and the date `--captured-at`
//   (else the input file's modified time). Nothing is made up.
// - the colour Floorplan (`FloorplanWriter.write`, the phone's "Colour floorplan"):
//   floorplan.pdf, floorplan.svg and floorplan.png.
//
// The PNGs are page 1 of each PDF at 200 dpi on white. Then prints a one-line JSON summary.
// Failures go to stderr as one readable line, with exit code 2 (usage), 3 (input unreadable),
// 4 (not a capture this code can read or map), 5 (drawing) or 6 (writing).

enum PlanRender {
  static let usage = """
    Usage: plan-render <roomplan.json | capture-model.json> <out-dir> \
    [--address <text>] [--units imperial|metric] [--title <text>] \
    [--label <capture label>] [--room-names <names.json>] \
    [--record <capture-record.json> --capture-id <id>] [--captured-at <ISO 8601>]
    """
  static let dpi: CGFloat = 200

  struct Failure: Error {
    let code: Int32
    let message: String
  }

  struct Arguments {
    var input: URL
    var outDir: URL
    var options: FloorplanWriter.Options
    var units: DisplayUnitSystem
    /// The capture's label, as the phone maps the scan with it.
    var label = "Scan"
    var roomNames: URL?
    var address: String?
    /// The capture record and the capture of it this scan is.
    var record: URL?
    var captureId: String?
    var capturedAt: UTCTimestamp?
  }

  static func parse(_ args: [String]) throws -> Arguments {
    var positional: [String] = []
    var address: String?
    var title = "Floorplan"
    var units = DisplayUnitSystem.imperial
    var label = "Scan"
    var roomNames: URL?
    var record: URL?
    var captureId: String?
    var capturedAt: UTCTimestamp?
    var i = 0
    func value(_ flag: String) throws -> String {
      i += 1
      guard i < args.count else { throw Failure(code: 2, message: "\(flag) needs a value.") }
      return args[i]
    }
    while i < args.count {
      let arg = args[i]
      switch arg {
      case "--address": address = try value(arg)
      case "--title": title = try value(arg)
      case "--label":
        let text = try value(arg).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw Failure(code: 2, message: "--label needs a value.") }
        label = text
      case "--room-names": roomNames = URL(fileURLWithPath: try value(arg))
      case "--record": record = URL(fileURLWithPath: try value(arg))
      case "--capture-id": captureId = try value(arg)
      case "--captured-at":
        let text = try value(arg)
        // With or without fractional seconds ("2026-10-18T16:49:16Z", "…16.000Z").
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = ISO8601DateFormatter().date(from: text) ?? fractional.date(from: text)
        else {
          throw Failure(code: 2, message: "--captured-at must be an ISO 8601 time (got \(text)).")
        }
        capturedAt = UTCTimestamp(date)
      case "--units":
        let text = try value(arg)
        guard let system = DisplayUnitSystem(rawValue: text) else {
          throw Failure(code: 2, message: "--units must be imperial or metric (got \(text)).")
        }
        units = system
      case "-h", "--help": throw Failure(code: 0, message: usage)
      default:
        if arg.hasPrefix("--") { throw Failure(code: 2, message: "Unknown option \(arg).") }
        positional.append(arg)
      }
      i += 1
    }
    guard positional.count == 2 else { throw Failure(code: 2, message: usage) }
    let options = FloorplanWriter.Options(
      title: title, address: address, units: UnitFormatter(system: units))
    return Arguments(
      input: URL(fileURLWithPath: positional[0]),
      outDir: URL(fileURLWithPath: positional[1], isDirectory: true), options: options,
      units: units, label: label, roomNames: roomNames, address: address, record: record,
      captureId: captureId, capturedAt: capturedAt)
  }

  /// The plan sheet's context: the capture record's when it can be read and holds the capture,
  /// else the unrecorded scan's, with why in `note`.
  static func sheetContext(_ arguments: Arguments)
    -> (record: CaptureRecord?, captureId: LowercaseUUID?, note: String?)
  {
    guard let url = arguments.record else { return (nil, nil, "no capture record") }
    let record: CaptureRecord
    do {
      record = try CaptureContractJSON.makeDecoder().decode(
        CaptureRecord.self, from: Data(contentsOf: url))
    } catch {
      return (nil, nil, "the capture record could not be read: \(describe(error))")
    }
    guard let text = arguments.captureId, let id = LowercaseUUID(rawValue: text),
      record.captures.contains(where: { $0.captureId == id })
    else { return (nil, nil, "the capture record does not hold this capture") }
    return (record, id, nil)
  }

  /// The operator's room names in `url`: a JSON array of `RoomName`.
  static func roomNames(from url: URL) throws -> [RoomName] {
    do {
      return try JSONDecoder().decode([RoomName].self, from: Data(contentsOf: url))
    } catch {
      throw Failure(
        code: 3, message: "\(url.lastPathComponent) is not a list of room names: \(describe(error))")
    }
  }

  /// The capture model of the input, and which kind of file it was. A roomplan.json is mapped
  /// with `label` and the room `names`, as the phone's scan viewer maps it.
  static func model(
    from url: URL, label: String = "Scan", names: [RoomName] = [],
    record: CaptureRecord? = nil, captureId: LowercaseUUID? = nil
  ) throws -> (model: CaptureModel, source: String) {
    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch {
      throw Failure(
        code: 3, message: "\(url.lastPathComponent) could not be read: \(error.localizedDescription)")
    }
    let name = url.lastPathComponent.lowercased()
    if name.hasSuffix("capture-model.json") {
      do {
        return (try CaptureContractJSON.makeDecoder().decode(CaptureModel.self, from: data), "capture-model")
      } catch {
        throw Failure(
          code: 4,
          message: "\(url.lastPathComponent) is not a capture model this code can read: \(describe(error))")
      }
    }
    let document: RoomPlanDocument
    do {
      document = try RoomPlanDocument.decode(from: data)
    } catch {
      throw Failure(
        code: 4,
        message: "\(url.lastPathComponent) is not a RoomPlan capture this code can read: \(describe(error))")
    }
    // The record's ids, as the package maps the scan; else fixed ids (the sheet then prints
    // none), so the same file always maps the same way.
    let capture = record?.captures.first { $0.captureId == captureId }
    let context = MappingContext(
      visitId: record?.visitId ?? LowercaseUUID(rawValue: "00000000-0000-4000-8000-000000000001")!,
      captureId: capture?.captureId
        ?? LowercaseUUID(rawValue: "00000000-0000-4000-8000-000000000002")!,
      areaKey: capture?.areaKey ?? "scan", label: label)
    do {
      return (try RoomNaming.map(document, context: context, names: names).model, "roomplan")
    } catch {
      throw Failure(code: 4, message: "The RoomPlan capture could not be mapped: \(describe(error))")
    }
  }

  /// One line for a decoding or mapping error (Foundation's own text names no field).
  static func describe(_ error: Error) -> String {
    func at(_ context: DecodingError.Context) -> String {
      let path = context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }
      return path.isEmpty ? "" : " at \(path.joined(separator: "."))"
    }
    switch error {
    case DecodingError.keyNotFound(let key, let context):
      return "missing \(key.stringValue)\(at(context))"
    case DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context),
      DecodingError.dataCorrupted(let context):
      return "\(context.debugDescription)\(at(context))"
    case let error as CustomStringConvertible:
      return error.description
    default:
      return error.localizedDescription
    }
  }

  /// Page 1 of `pdf` as a PNG at `dpi` on white, with that resolution in the file so it prints
  /// at the page's size (as the app's floorplan.png, at a lower resolution).
  static func png(pdf: Data, dpi: CGFloat) throws -> (data: Data, width: Int, height: Int) {
    let failure = Failure(code: 5, message: "A PDF page could not be drawn as an image.")
    guard let provider = CGDataProvider(data: pdf as CFData),
      let document = CGPDFDocument(provider), let page = document.page(at: 1)
    else { throw failure }
    let box = page.getBoxRect(.mediaBox)
    let scale = dpi / 72
    let width = Int((box.width * scale).rounded())
    let height = Int((box.height * scale).rounded())
    guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { throw failure }
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.interpolationQuality = .high
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: -box.minX, y: -box.minY)
    context.drawPDFPage(page)
    let out = NSMutableData()
    guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithData(
        out, UTType.png.identifier as CFString, 1, nil)
    else { throw failure }
    let properties = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw failure }
    return (out as Data, width, height)
  }

  static func run(_ args: [String]) throws {
    let arguments = try parse(args)
    let names = try arguments.roomNames.map(roomNames(from:)) ?? []
    let recorded = sheetContext(arguments)
    let (model, source) = try model(
      from: arguments.input, label: arguments.label, names: names, record: recorded.record,
      captureId: recorded.captureId)
    // The plan sheet's title block: the record's, else "not recorded".
    let context: PlanExportContext
    if let record = recorded.record, let id = recorded.captureId {
      do {
        context = try PlanExportContext(record: record, captureId: id)
      } catch {
        throw Failure(code: 4, message: "The capture record could not be used: \(describe(error))")
      }
    } else {
      let modified =
        (try? arguments.input.resourceValues(forKeys: [.contentModificationDateKey]))?
        .contentModificationDate ?? Date(timeIntervalSince1970: 0)
      context = PlanExportContext(
        unrecordedScan: arguments.label,
        capturedAt: arguments.capturedAt ?? UTCTimestamp(modified), address: arguments.address)
    }
    let sheet: PlanSheetOutput
    do {
      sheet = try PlanSheetWriter.write(model: model, context: context)
    } catch {
      throw Failure(code: 5, message: "The plan sheet could not be drawn: \(describe(error))")
    }
    let sheetImage = try png(pdf: sheet.file.data, dpi: dpi)
    let plan: FloorplanWriter.Floorplan
    do {
      plan = try FloorplanWriter.write(model: model, options: arguments.options)
    } catch {
      throw Failure(code: 5, message: "The Floorplan could not be drawn: \(describe(error))")
    }
    let image = try png(pdf: plan.pdf, dpi: dpi)
    let folder = arguments.outDir
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try plan.pdf.write(to: folder.appendingPathComponent("floorplan.pdf"), options: .atomic)
      try Data(plan.svg.utf8).write(
        to: folder.appendingPathComponent("floorplan.svg"), options: .atomic)
      try image.data.write(to: folder.appendingPathComponent("floorplan.png"), options: .atomic)
      try sheet.file.data.write(
        to: folder.appendingPathComponent(PlanSheetWriter.fileName), options: .atomic)
      try sheetImage.data.write(
        to: folder.appendingPathComponent("plan-sheet.png"), options: .atomic)
    } catch {
      throw Failure(
        code: 6, message: "The plan files could not be written: \(error.localizedDescription)")
    }
    var planSheet: [String: Any] = [
      "scaleDenominator": sheet.scaleDenominator,
      "isClipped": sheet.isClipped,
      "titleBlock": context.isRecorded ? "capture record" : "not recorded",
      "png": ["width": sheetImage.width, "height": sheetImage.height, "dpi": Int(dpi)],
    ]
    if let note = recorded.note { planSheet["note"] = note }
    let summary: [String: Any] = [
      "source": source,
      "units": arguments.units.rawValue,
      "rooms": model.rooms.count,
      "roomLabels": model.rooms.map(\.label),
      "walls": model.walls.count,
      "page": plan.page.rawValue,
      "widthMM": plan.widthMM,
      "heightMM": plan.heightMM,
      "scaleDenominator": plan.scaleDenominator,
      "totalAreaM2": plan.totalAreaM2,
      "totalText": plan.totalText,
      "png": ["width": image.width, "height": image.height, "dpi": Int(dpi)],
      "planSheet": planSheet,
    ]
    let json = try JSONSerialization.data(
      withJSONObject: summary, options: [.sortedKeys, .withoutEscapingSlashes])
    FileHandle.standardOutput.write(json + Data("\n".utf8))
  }
}

do {
  try PlanRender.run(Array(CommandLine.arguments.dropFirst()))
} catch let failure as PlanRender.Failure {
  let handle = failure.code == 0 ? FileHandle.standardOutput : FileHandle.standardError
  handle.write(Data("\(failure.code == 0 ? "" : "plan-render: ")\(failure.message)\n".utf8))
  exit(failure.code)
} catch {
  FileHandle.standardError.write(Data("plan-render: \(error.localizedDescription)\n".utf8))
  exit(1)
}

import CaptureContract
import CaptureModelMapping
import CoreGraphics
import Foundation
import ImageIO
import PlanExport
import UniformTypeIdentifiers

// plan-render: the Chapter Floorplan of one scan, written with the current app code.
//
//   plan-render <roomplan.json | capture-model.json> <out-dir>
//               [--address <text>] [--units imperial|metric] [--title <text>]
//
// A roomplan.json (the raw RoomPlan capture) is mapped with `CaptureModelMapper`, as the phone's
// scan viewer does; a capture-model.json is drawn as it is. The page is `FloorplanWriter.write`
// (public API, nothing redrawn here). Writes floorplan.pdf, floorplan.svg and floorplan.png
// (page 1 of the PDF at 200 dpi on white) into <out-dir>, then prints a one-line JSON summary.
// Failures go to stderr as one readable line, with exit code 2 (usage), 3 (input unreadable),
// 4 (not a capture this code can read or map), 5 (drawing) or 6 (writing).

enum PlanRender {
  static let usage = """
    Usage: plan-render <roomplan.json | capture-model.json> <out-dir> \
    [--address <text>] [--units imperial|metric] [--title <text>]
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
  }

  static func parse(_ args: [String]) throws -> Arguments {
    var positional: [String] = []
    var address: String?
    var title = "Floorplan"
    var units = DisplayUnitSystem.imperial
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
      units: units)
  }

  /// The capture model of the input, and which kind of file it was.
  static func model(from url: URL) throws -> (model: CaptureModel, source: String) {
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
    // Fixed ids: they appear in no drawing, and the same file then always maps the same way.
    let context = MappingContext(
      visitId: LowercaseUUID(rawValue: "00000000-0000-4000-8000-000000000001")!,
      captureId: LowercaseUUID(rawValue: "00000000-0000-4000-8000-000000000002")!,
      areaKey: "scan", label: "Scan")
    do {
      return (try CaptureModelMapper.map(document, context: context), "roomplan")
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
    let failure = Failure(code: 5, message: "The Floorplan PDF could not be drawn as an image.")
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
    let (model, source) = try model(from: arguments.input)
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
    } catch {
      throw Failure(
        code: 6, message: "The Floorplan files could not be written: \(error.localizedDescription)")
    }
    let summary: [String: Any] = [
      "source": source,
      "units": arguments.units.rawValue,
      "rooms": model.rooms.count,
      "walls": model.walls.count,
      "page": plan.page.rawValue,
      "widthMM": plan.widthMM,
      "heightMM": plan.heightMM,
      "scaleDenominator": plan.scaleDenominator,
      "totalAreaM2": plan.totalAreaM2,
      "totalText": plan.totalText,
      "png": ["width": image.width, "height": image.height, "dpi": Int(dpi)],
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

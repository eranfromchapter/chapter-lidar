import CaptureContract
import Foundation
import SketchReading
import StationClient

#if canImport(CoreGraphics)
  import CoreGraphics
#endif

/// Why the station could not read a sketch photo, in the words the app shows.
public enum SketchReaderError: Error, Equatable, LocalizedError, CustomStringConvertible {
  /// 503: no API key on the station, or Claude unavailable after the station's retries.
  case unavailable
  /// The phone could not reach the station.
  case offline
  /// Any other answer: the station's problem title (or the status).
  case failed(String)

  public var description: String {
    switch self {
    case .unavailable:
      return "The station cannot read sketches right now. Try again later, or enter the sketch by hand."
    case .offline:
      return "The station cannot be reached. Check the connection, or enter the sketch by hand."
    case .failed(let reason): return reason
    }
  }

  public var errorDescription: String? { description }
}

/// Reads a sketch photo or PDF through the station (spec F16 3): `POST
/// /v1/sketch-interpretations` with the bytes as base64, their media type (`image/jpeg`,
/// `image/png`, or `application/pdf` for a whole PDF) and the bearer token, as every station
/// call. 200 is what Claude read; 422 `sketch_not_a_plan` is `SketchReadingError.notAFloorPlan`
/// with the reading's problem; 503 is `SketchReaderError.unavailable`; anything else fails with
/// the problem's title. Give `station` a transport with a long timeout (a photo takes about a
/// minute, a multi-page PDF a few): `StationSketchInterpreter.timeout`.
public struct StationSketchInterpreter: SketchInterpreting {
  /// Seconds the phone waits for the station's answer (a 20-page PDF takes about 3 minutes).
  public static let timeout: TimeInterval = 600

  private let station: StationClient

  public init(station: StationClient) {
    self.station = station
  }

  public func interpret(imageData: Data, mediaType: String) async throws -> SketchInterpretation {
    do {
      return try await station.createSketchInterpretation(
        SketchInterpretationRequest(mediaType: mediaType, imageData: imageData))
    } catch let rejected as SketchInterpretationRejected {
      if rejected.problem?.code == "sketch_not_a_plan" || rejected.interpretation != nil {
        throw SketchReadingError.notAFloorPlan(rejected.reason)
      }
      throw SketchReaderError.failed(rejected.reason)
    } catch let error as StationError {
      throw Self.readerError(error)
    }
  }

  static func readerError(_ error: StationError) -> SketchReaderError {
    switch error {
    case .server(503, _): return .unavailable
    case .offline: return .offline
    case .unauthorized: return .failed("Sign in again to read the sketch.")
    case .forbidden: return .failed("This account may not read sketches.")
    default:
      if let problem = error.problem {
        return .failed(problem.detail.map { "\(problem.title): \($0)" } ?? problem.title)
      }
      switch error {
      case .unexpectedStatus(let status): return .failed("The station answered \(status).")
      case .network(let code): return .failed("The request failed (\(code)).")
      case .invalidResponse(let what): return .failed("The station's answer could not be read: \(what)")
      default: return .failed("The sketch could not be read.")
      }
    }
  }
}

/// The pixel size of a JPEG or PNG from its header (no decoding), or the first page's size in
/// points of a PDF (its media box, rounded; Apple platforms), for the interpretation's `image`
/// of a reading made without the station.
public enum ImageHeader {
  public static func size(of data: Data) -> SketchInterpretation.ImageSize? {
    if data.starts(with: Array("%PDF".utf8)) { return pdfPageSize(of: data) }
    let bytes = [UInt8](data.prefix(256 * 1024))
    if bytes.count >= 24, bytes[0] == 0x89, bytes[1] == 0x50, bytes[2] == 0x4E, bytes[3] == 0x47 {
      let width = Int(bytes[16]) << 24 | Int(bytes[17]) << 16 | Int(bytes[18]) << 8 | Int(bytes[19])
      let height = Int(bytes[20]) << 24 | Int(bytes[21]) << 16 | Int(bytes[22]) << 8 | Int(bytes[23])
      return width > 0 && height > 0 ? .init(width: width, height: height) : nil
    }
    guard bytes.count >= 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return nil }
    let frames: Set<UInt8> = [0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF]
    var offset = 2
    while offset + 4 <= bytes.count {
      guard bytes[offset] == 0xFF else { return nil }
      while offset < bytes.count, bytes[offset] == 0xFF { offset += 1 }
      guard offset < bytes.count else { return nil }
      let marker = bytes[offset]
      offset += 1
      if marker == 0x01 || (0xD0...0xD8).contains(marker) { continue }
      if marker == 0xD9 || marker == 0xDA || offset + 2 > bytes.count { return nil }
      let length = Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
      guard length >= 2 else { return nil }
      if frames.contains(marker) {
        guard offset + 7 <= bytes.count else { return nil }
        let height = Int(bytes[offset + 3]) << 8 | Int(bytes[offset + 4])
        let width = Int(bytes[offset + 5]) << 8 | Int(bytes[offset + 6])
        return width > 0 && height > 0 ? .init(width: width, height: height) : nil
      }
      offset += length
    }
    return nil
  }

  /// The first page's media box of a PDF in points, rounded; nil without CoreGraphics.
  static func pdfPageSize(of data: Data) -> SketchInterpretation.ImageSize? {
    #if canImport(CoreGraphics)
      guard let provider = CGDataProvider(data: data as CFData),
        let document = CGPDFDocument(provider), let page = document.page(at: 1)
      else { return nil }
      let box = page.getBoxRect(.mediaBox)
      let width = Int(Double(box.width).rounded())
      let height = Int(Double(box.height).rounded())
      return width > 0 && height > 0 ? .init(width: width, height: height) : nil
    #else
      return nil
    #endif
  }
}

import Foundation

public struct LASOptions: Sendable {
  public var generatorVersion: String
  /// Header creation date (UTC day of year and year). Defaults to now.
  public var creationDate: Date
  /// Default false: no WKT, as the spec says (local coordinates). Strict LAS 1.4 says formats 6
  /// to 10 should set the WKT bit; PDAL only warns. Set true to write the WKT bit and a
  /// `LOCAL_CS` engineering CRS (metres, Z up) in a `LASF_Projection` VLR, if a reader
  /// (ReCap) turns out to insist on it.
  public var writeLocalCoordinateSystemWKT: Bool

  public init(
    generatorVersion: String = ExportInfo.version, creationDate: Date = Date(),
    writeLocalCoordinateSystemWKT: Bool = false
  ) {
    self.generatorVersion = generatorVersion
    self.creationDate = creationDate
    self.writeLocalCoordinateSystemWKT = writeLocalCoordinateSystemWKT
  }
}

/// What a written LAS file contains, taken from the header that was written.
public struct LASSummary: Sendable, Equatable {
  public var pointCount: Int
  /// Header extents, in LAS coordinates (X, Y, Z up).
  public var min: SIMD3<Double>
  public var max: SIMD3<Double>
  public var fileBytes: Int
}

/// Writes LAS 1.4, point data record format 7 (XYZ, RGB, GPS time, intensity 0).
///
/// - Axes: LAS is Z up. The model's (x, y, z) with +Y up is written as LAS (x, -z, y), which keeps
///   the frame right-handed (same convention as the fixtures' `points.las`).
/// - Scale 0.001 m; offsets at the bounding-box minimum; header extents are computed from the
///   stored integers, so they equal the written points exactly.
/// - No WKT (local coordinates): global encoding bit 4 is clear and there is no CRS VLR
///   (unless `LASOptions.writeLocalCoordinateSystemWKT` is set).
/// - Global encoding bit 3 (synthetic return numbers) is set: the return numbers (1 of 1) are not
///   measured, the file is derived data. One ASCII VLR (`ChapterCapture`, record 1) states that
///   the cloud comes from a phone depth sensor and is not survey data.
/// - System identifier `Chapter Capture`, generating software `Chapter Capture <version>`.
/// - Legacy point counts are zero (required for formats 6 to 10); the 64-bit count is set.
/// - GPS time is a synthetic ascending sequence (1 microsecond per point in order); samples carry
///   no timestamp.
public enum LASWriter {
  public static let headerSize = 375
  public static let recordLength = 36
  public static let scale = 0.001
  public static let pointFormat: UInt8 = 7
  /// Global encoding: bit 3, synthetic return numbers.
  public static let globalEncoding: UInt16 = 0x0008
  /// Global encoding bit 4: the CRS is WKT (only with `writeLocalCoordinateSystemWKT`).
  public static let wktBit: UInt16 = 0x0010
  public static let localCoordinateSystemWKT =
    "LOCAL_CS[\"Chapter Capture local frame\",LOCAL_DATUM[\"Local\",0],UNIT[\"metre\",1],"
    + "AXIS[\"X\",OTHER],AXIS[\"Y\",OTHER],AXIS[\"Z\",UP]]"
  public static let vlrUserID = "ChapterCapture"
  public static let vlrRecordID: UInt16 = 1

  private static let chunkPoints = 1 << 18

  public static func encode(points: [DepthSample], options: LASOptions = LASOptions()) throws -> (
    data: Data, summary: LASSummary
  ) {
    var data = Data()
    let summary = try stream(points: points, options: options) { chunk in
      data.append(contentsOf: chunk)
    }
    return (data, summary)
  }

  /// Streams the file to disk in chunks (no full copy of the output in memory).
  @discardableResult
  public static func write(
    points: [DepthSample], to url: URL, options: LASOptions = LASOptions()
  ) throws -> LASSummary {
    let manager = FileManager.default
    try manager.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let temporary = url.appendingPathExtension("part")
    _ = manager.createFile(atPath: temporary.path, contents: nil)
    let handle = try FileHandle(forWritingTo: temporary)
    do {
      let summary = try stream(points: points, options: options) { chunk in
        try handle.write(contentsOf: chunk)
      }
      try handle.close()
      if manager.fileExists(atPath: url.path) { try manager.removeItem(at: url) }
      try manager.moveItem(at: temporary, to: url)
      return summary
    } catch {
      try? handle.close()
      try? manager.removeItem(at: temporary)
      throw error
    }
  }

  private static func lasCoordinates(_ s: DepthSample) -> SIMD3<Double> {
    SIMD3(Double(s.x), -Double(s.z), Double(s.y))
  }

  private static func stream(
    points: [DepthSample], options: LASOptions, sink: ([UInt8]) throws -> Void
  ) throws -> LASSummary {
    guard !points.isEmpty else { throw MeshExportError.noPoints }
    // Pass 1: bounding-box minimum (the offsets).
    var offset = SIMD3<Double>(repeating: .infinity)
    for s in points {
      guard s.x.isFinite, s.y.isFinite, s.z.isFinite else {
        throw MeshExportError.invalidMesh("a point is not finite")
      }
      let p = lasCoordinates(s)
      offset = SIMD3(Swift.min(offset.x, p.x), Swift.min(offset.y, p.y), Swift.min(offset.z, p.z))
    }
    // Pass 2: integer extents. The minimum integer is 0 on every axis by construction.
    var maxInt = SIMD3<Int64>(repeating: 0)
    for s in points {
      let q = quantized(lasCoordinates(s), offset: offset)
      maxInt = SIMD3(Swift.max(maxInt.x, q.x), Swift.max(maxInt.y, q.y), Swift.max(maxInt.z, q.z))
    }
    guard maxInt.x <= Int64(Int32.max), maxInt.y <= Int64(Int32.max), maxInt.z <= Int64(Int32.max)
    else {
      throw MeshExportError.coordinateRange("extent exceeds 2,147,483 m at 0.001 m scale")
    }
    let maxExtent = SIMD3(
      offset.x + Double(maxInt.x) * scale, offset.y + Double(maxInt.y) * scale,
      offset.z + Double(maxInt.z) * scale)

    // VLRs: the provenance statement, and optionally the local WKT.
    var vlrs: [(user: String, record: UInt16, description: String, data: [UInt8])] = [
      (vlrUserID, vlrRecordID, "Capture provenance", Array(ExportProvenance.statement.utf8))
    ]
    if options.writeLocalCoordinateSystemWKT {
      vlrs.append(
        ("LASF_Projection", 2112, "OGC WKT local CS", Array(localCoordinateSystemWKT.utf8) + [0]))
    }
    let pointDataOffset = headerSize + vlrs.reduce(0) { $0 + 54 + $1.data.count }

    var header = ByteBuffer(capacity: pointDataOffset)
    header.appendFixedASCII("LASF", length: 4)
    header.append(UInt16(0))  // file source id
    header.append(
      options.writeLocalCoordinateSystemWKT ? globalEncoding | wktBit : globalEncoding)
    header.append(contentsOf: [UInt8](repeating: 0, count: 16))  // project GUID
    header.append(UInt8(1))  // version major
    header.append(UInt8(4))  // version minor
    header.appendFixedASCII(ExportInfo.systemIdentifier, length: 32)
    header.appendFixedASCII(
      ExportInfo.generator(version: options.generatorVersion), length: 32)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
    let day = calendar.ordinality(of: .day, in: .year, for: options.creationDate) ?? 1
    let year = calendar.component(.year, from: options.creationDate)
    header.append(UInt16(day))
    header.append(UInt16(year))
    header.append(UInt16(headerSize))
    header.append(UInt32(pointDataOffset))
    header.append(UInt32(vlrs.count))  // number of VLRs
    header.append(pointFormat)
    header.append(UInt16(recordLength))
    header.append(UInt32(0))  // legacy point count
    for _ in 0..<5 { header.append(UInt32(0)) }  // legacy counts by return
    for _ in 0..<3 { header.append(scale) }
    header.append(offset.x)
    header.append(offset.y)
    header.append(offset.z)
    header.append(maxExtent.x)
    header.append(offset.x)
    header.append(maxExtent.y)
    header.append(offset.y)
    header.append(maxExtent.z)
    header.append(offset.z)
    header.append(UInt64(0))  // waveform data packet record
    header.append(UInt64(0))  // first EVLR
    header.append(UInt32(0))  // number of EVLRs
    header.append(UInt64(points.count))  // number of point records
    header.append(UInt64(points.count))  // points by return: return 1
    for _ in 1..<15 { header.append(UInt64(0)) }
    precondition(header.count == headerSize)

    // VLR headers (54 bytes each) and data.
    for vlr in vlrs {
      header.append(UInt16(0))  // reserved
      header.appendFixedASCII(vlr.user, length: 16)
      header.append(vlr.record)
      header.append(UInt16(vlr.data.count))
      header.appendFixedASCII(vlr.description, length: 32)
      header.append(contentsOf: vlr.data)
    }
    precondition(header.count == pointDataOffset)
    try sink(header.bytes)

    // Pass 3: records, in chunks.
    var chunk = ByteBuffer(capacity: chunkPoints * recordLength)
    var index = 0
    for s in points {
      let q = quantized(lasCoordinates(s), offset: offset)
      chunk.append(Int32(truncatingIfNeeded: q.x))
      chunk.append(Int32(truncatingIfNeeded: q.y))
      chunk.append(Int32(truncatingIfNeeded: q.z))
      chunk.append(UInt16(0))  // intensity 0
      chunk.append(UInt8(0x11))  // return 1 of 1
      chunk.append(UInt8(0))  // flags, scanner channel 0
      chunk.append(UInt8(0))  // classification
      chunk.append(UInt8(0))  // user data
      chunk.append(Int16(0))  // scan angle
      chunk.append(UInt16(0))  // point source id
      chunk.append(Double(index) * 1e-6)  // GPS time
      chunk.append(UInt16(s.r) * 257)
      chunk.append(UInt16(s.g) * 257)
      chunk.append(UInt16(s.b) * 257)
      index += 1
      if index % chunkPoints == 0 {
        try sink(chunk.bytes)
        chunk.bytes.removeAll(keepingCapacity: true)
      }
    }
    if !chunk.bytes.isEmpty { try sink(chunk.bytes) }

    return LASSummary(
      pointCount: points.count, min: offset, max: maxExtent,
      fileBytes: pointDataOffset + points.count * recordLength)
  }

  private static func quantized(_ p: SIMD3<Double>, offset: SIMD3<Double>) -> SIMD3<Int64> {
    SIMD3(
      Int64(((p.x - offset.x) / scale).rounded()),
      Int64(((p.y - offset.y) / scale).rounded()),
      Int64(((p.z - offset.z) / scale).rounded()))
  }
}

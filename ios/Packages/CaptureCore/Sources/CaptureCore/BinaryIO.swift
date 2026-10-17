import Foundation

/// Little-endian binary writer used by the raw-originals formats.
struct ByteWriter {
  private(set) var data = Data()

  mutating func append(_ bytes: [UInt8]) {
    data.append(contentsOf: bytes)
  }

  mutating func append(_ value: UInt8) {
    data.append(value)
  }

  mutating func append(_ value: UInt32) {
    data.append(UInt8(truncatingIfNeeded: value))
    data.append(UInt8(truncatingIfNeeded: value >> 8))
    data.append(UInt8(truncatingIfNeeded: value >> 16))
    data.append(UInt8(truncatingIfNeeded: value >> 24))
  }

  mutating func append(_ value: Float) {
    append(value.bitPattern)
  }
}

/// Little-endian binary reader. Every read checks the remaining length.
struct ByteReader {
  let bytes: [UInt8]
  private(set) var offset = 0

  init(_ data: Data) {
    bytes = [UInt8](data)
  }

  var remaining: Int { bytes.count - offset }

  mutating func readBytes(_ count: Int) throws -> [UInt8] {
    guard count >= 0, remaining >= count else { throw RawOriginalsError.truncated }
    defer { offset += count }
    return Array(bytes[offset..<offset + count])
  }

  mutating func readU8() throws -> UInt8 {
    try readBytes(1)[0]
  }

  mutating func readU32() throws -> UInt32 {
    let b = try readBytes(4)
    return UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
  }

  mutating func readF32() throws -> Float {
    Float(bitPattern: try readU32())
  }
}

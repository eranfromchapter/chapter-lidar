import Foundation

/// zlib stream (RFC 1950) with one DEFLATE block (RFC 1951) of fixed Huffman codes and LZ77
/// matches found with hash chains. Pure Swift; output depends only on the input bytes.
enum Deflate {
  private static let lengthBase: [Int] = [
    3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131,
    163, 195, 227, 258,
  ]
  private static let lengthExtra: [Int] = [
    0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0,
  ]
  private static let distanceBase: [Int] = [
    1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537,
    2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577,
  ]
  private static let distanceExtra: [Int] = [
    0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13,
    13,
  ]

  private struct BitWriter {
    var bytes: [UInt8] = []
    private var buffer: UInt64 = 0
    private var count = 0

    /// Writes `bits` low bits of `value`, least significant bit first.
    mutating func write(_ value: Int, bits: Int) {
      buffer |= UInt64(value) << UInt64(count)
      count += bits
      while count >= 8 {
        bytes.append(UInt8(truncatingIfNeeded: buffer))
        buffer >>= 8
        count -= 8
      }
    }

    /// Writes a Huffman code, most significant bit first.
    mutating func writeCode(_ code: Int, length: Int) {
      var reversed = 0
      for bit in 0..<length where (code >> bit) & 1 == 1 {
        reversed |= 1 << (length - 1 - bit)
      }
      write(reversed, bits: length)
    }

    mutating func flush() {
      if count > 0 {
        bytes.append(UInt8(truncatingIfNeeded: buffer))
        buffer = 0
        count = 0
      }
    }
  }

  /// Fixed Huffman code and length for a literal/length symbol 0...287.
  private static func fixedCode(_ symbol: Int) -> (code: Int, length: Int) {
    switch symbol {
    case 0...143: return (0x30 + symbol, 8)
    case 144...255: return (0x190 + symbol - 144, 9)
    case 256...279: return (symbol - 256, 7)
    default: return (0xC0 + symbol - 280, 8)
    }
  }

  private static func lengthSymbol(_ length: Int) -> Int {
    var index = lengthBase.count - 1
    while lengthBase[index] > length { index -= 1 }
    return index
  }

  private static func distanceSymbol(_ distance: Int) -> Int {
    var index = distanceBase.count - 1
    while distanceBase[index] > distance { index -= 1 }
    return index
  }

  static func adler32(_ data: [UInt8]) -> UInt32 {
    var a: UInt32 = 1
    var b: UInt32 = 0
    var index = 0
    while index < data.count {
      let end = min(index + 5552, data.count)
      while index < end {
        a &+= UInt32(data[index])
        b &+= a
        index += 1
      }
      a %= 65521
      b %= 65521
    }
    return (b << 16) | a
  }

  static func zlibCompress(_ data: [UInt8]) -> [UInt8] {
    var writer = BitWriter()
    writer.bytes = [0x78, 0x01]
    writer.write(1, bits: 1)  // final block
    writer.write(1, bits: 2)  // fixed Huffman

    let window = 32768
    let mask = window - 1
    let hashSize = 1 << 15
    var head = [Int32](repeating: -1, count: hashSize)
    var previous = [Int32](repeating: -1, count: window)
    let count = data.count
    let maxChain = 24

    data.withUnsafeBufferPointer { bytes in
      @inline(__always) func hash(_ position: Int) -> Int {
        let value =
          (Int(bytes[position]) << 16) | (Int(bytes[position + 1]) << 8)
          | Int(bytes[position + 2])
        return (value &* 2_654_435_761) >> 8 & (hashSize - 1)
      }
      func insert(_ position: Int) {
        guard position + 2 < count else { return }
        let h = hash(position)
        previous[position & mask] = head[h]
        head[h] = Int32(position)
      }

      var position = 0
      while position < count {
        var bestLength = 0
        var bestDistance = 0
        if position + 2 < count {
          var candidate = Int(head[hash(position)])
          var chain = 0
          let limit = min(258, count - position)
          while candidate >= 0, position - candidate <= window, chain < maxChain {
            var length = 0
            while length < limit, bytes[candidate + length] == bytes[position + length] {
              length += 1
            }
            if length > bestLength {
              bestLength = length
              bestDistance = position - candidate
              if length == limit { break }
            }
            chain += 1
            candidate = Int(previous[candidate & mask])
          }
        }
        if bestLength >= 3 {
          let lengthIndex = lengthSymbol(bestLength)
          let (code, bits) = fixedCode(257 + lengthIndex)
          writer.writeCode(code, length: bits)
          if lengthExtra[lengthIndex] > 0 {
            writer.write(bestLength - lengthBase[lengthIndex], bits: lengthExtra[lengthIndex])
          }
          let distanceIndex = distanceSymbol(bestDistance)
          writer.writeCode(distanceIndex, length: 5)
          if distanceExtra[distanceIndex] > 0 {
            writer.write(
              bestDistance - distanceBase[distanceIndex], bits: distanceExtra[distanceIndex])
          }
          for offset in 0..<bestLength { insert(position + offset) }
          position += bestLength
        } else {
          let (code, bits) = fixedCode(Int(bytes[position]))
          writer.writeCode(code, length: bits)
          insert(position)
          position += 1
        }
      }
    }
    let (endCode, endBits) = fixedCode(256)
    writer.writeCode(endCode, length: endBits)
    writer.flush()
    let checksum = adler32(data)
    writer.bytes += [
      UInt8(checksum >> 24), UInt8((checksum >> 16) & 0xFF), UInt8((checksum >> 8) & 0xFF),
      UInt8(checksum & 0xFF),
    ]
    return writer.bytes
  }
}

enum CRC32 {
  private static let table: [UInt32] = (0..<256).map { index in
    var value = UInt32(index)
    for _ in 0..<8 {
      value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
    }
    return value
  }

  static func checksum(_ bytes: [UInt8]) -> UInt32 {
    var value: UInt32 = 0xFFFF_FFFF
    for byte in bytes {
      value = table[Int((value ^ UInt32(byte)) & 0xFF)] ^ (value >> 8)
    }
    return value ^ 0xFFFF_FFFF
  }
}

/// PNG encoder (8-bit grayscale) with a `pHYs` chunk for the resolution.
public enum PNGEncoder {
  /// Encodes `pixels` (row-major, one byte per pixel, 0 black and 255 white).
  /// `dpi` sets the physical resolution (300 means 11811 pixels per metre).
  public static func encodeGrayscale(width: Int, height: Int, pixels: [UInt8], dpi: Int? = nil)
    -> Data
  {
    precondition(width > 0 && height > 0 && pixels.count == width * height)
    func chunk(_ type: String, _ body: [UInt8]) -> [UInt8] {
      var out: [UInt8] = []
      func append(_ value: UInt32) {
        out += [
          UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF),
          UInt8(value & 0xFF),
        ]
      }
      append(UInt32(body.count))
      let typed = Array(type.utf8) + body
      out += typed
      append(CRC32.checksum(typed))
      return out
    }
    func be32(_ value: Int) -> [UInt8] {
      [
        UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF),
        UInt8(value & 0xFF),
      ]
    }

    var out: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    out += chunk("IHDR", be32(width) + be32(height) + [8, 0, 0, 0, 0])
    if let dpi {
      let perMetre = Int((Double(dpi) / 0.0254).rounded())
      out += chunk("pHYs", be32(perMetre) + be32(perMetre) + [1])
    }
    var raw: [UInt8] = []
    raw.reserveCapacity((width + 1) * height)
    for row in 0..<height {
      raw.append(0)
      raw += pixels[(row * width)..<((row + 1) * width)]
    }
    out += chunk("IDAT", Deflate.zlibCompress(raw))
    out += chunk("IEND", [])
    return Data(out)
  }
}

import Foundation

/// One depth sample: a point in the capture frame (metres, +Y up) with its colour and the
/// sensor confidence (0 low, 1 medium, 2 high).
public struct DepthSample: Sendable, Equatable {
  public var x: Float
  public var y: Float
  public var z: Float
  public var r: UInt8
  public var g: UInt8
  public var b: UInt8
  public var confidence: UInt8

  public init(
    x: Float, y: Float, z: Float, r: UInt8, g: UInt8, b: UInt8, confidence: UInt8 = 2
  ) {
    self.x = x
    self.y = y
    self.z = z
    self.r = r
    self.g = g
    self.b = b
    self.confidence = confidence
  }
}

/// Reader and writer of the `depth-samples.bin` file ("CHDS" version 1, little endian):
/// a 16-byte header (magic "CHDS", u32 version, u32 count, u32 reserved) followed by `count`
/// samples of 16 bytes: f32 x, y, z, then u8 r, g, b, confidence.
public enum DepthSampleFile {
  public static let headerBytes = 16
  public static let sampleBytes = 16
  public static let version: UInt32 = 1

  public static func read(_ data: Data) throws -> [DepthSample] {
    let bytes = [UInt8](data)
    guard bytes.count >= headerBytes else {
      throw MeshExportError.invalidDepthFile("shorter than the 16-byte header")
    }
    guard bytes[0] == 0x43, bytes[1] == 0x48, bytes[2] == 0x44, bytes[3] == 0x53 else {
      throw MeshExportError.invalidDepthFile("magic is not CHDS")
    }
    guard u32(bytes, 4) == version else {
      throw MeshExportError.invalidDepthFile("unsupported version \(u32(bytes, 4))")
    }
    let count = Int(u32(bytes, 8))
    guard bytes.count == headerBytes + count * sampleBytes else {
      throw MeshExportError.invalidDepthFile(
        "size \(bytes.count) does not match \(count) samples")
    }
    var samples: [DepthSample] = []
    samples.reserveCapacity(count)
    for index in 0..<count {
      let base = headerBytes + index * sampleBytes
      samples.append(
        DepthSample(
          x: Float(bitPattern: u32(bytes, base)),
          y: Float(bitPattern: u32(bytes, base + 4)),
          z: Float(bitPattern: u32(bytes, base + 8)),
          r: bytes[base + 12], g: bytes[base + 13], b: bytes[base + 14],
          confidence: bytes[base + 15]))
    }
    return samples
  }

  public static func read(contentsOf url: URL) throws -> [DepthSample] {
    try read(Data(contentsOf: url))
  }

  public static func encode(_ samples: [DepthSample]) -> Data {
    var out = ByteBuffer(capacity: headerBytes + samples.count * sampleBytes)
    out.append(contentsOf: [0x43, 0x48, 0x44, 0x53])
    out.append(version)
    out.append(UInt32(samples.count))
    out.append(UInt32(0))
    for s in samples {
      out.append(s.x)
      out.append(s.y)
      out.append(s.z)
      out.append(s.r)
      out.append(s.g)
      out.append(s.b)
      out.append(s.confidence)
    }
    return Data(out.bytes)
  }

  private static func u32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
    UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16
      | UInt32(bytes[offset + 3]) << 24
  }
}

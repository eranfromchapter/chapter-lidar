import Foundation

/// One sampled depth point, in the capture frame (metres, +Y up) with the camera colour at that
/// point and ARKit's depth confidence.
public struct DepthSample: Sendable, Equatable {
  public var x: Float
  public var y: Float
  public var z: Float
  public var red: UInt8
  public var green: UInt8
  public var blue: UInt8
  /// ARConfidenceLevel raw value: 0 low, 1 medium, 2 high.
  public var confidence: UInt8

  public init(
    x: Float, y: Float, z: Float, red: UInt8 = 0, green: UInt8 = 0, blue: UInt8 = 0,
    confidence: UInt8
  ) {
    self.x = x
    self.y = y
    self.z = z
    self.red = red
    self.green = green
    self.blue = blue
    self.confidence = confidence
  }

  /// Confidence value of `ARConfidenceLevel.medium`.
  public static let mediumConfidence: UInt8 = 1
}

/// "CHDS" version 1, little endian: a 16-byte header (magic `CHDS`, u32 version, u32 count,
/// u32 reserved), then `count` records of 16 bytes: f32 x, y, z, then u8 red, green, blue,
/// confidence. This is the format of `depth-samples.bin` in the intake package
/// (see fixtures/generator/src/depth.ts).
public enum DepthSamplesCodec {
  public static let magic: [UInt8] = Array("CHDS".utf8)
  public static let version: UInt32 = 1
  public static let headerSize = 16
  public static let recordSize = 16

  public static func encode(_ samples: [DepthSample]) -> Data {
    var writer = ByteWriter()
    writer.append(magic)
    writer.append(version)
    writer.append(UInt32(samples.count))
    writer.append(UInt32(0))
    for sample in samples {
      writer.append(sample.x)
      writer.append(sample.y)
      writer.append(sample.z)
      writer.append(sample.red)
      writer.append(sample.green)
      writer.append(sample.blue)
      writer.append(sample.confidence)
    }
    return writer.data
  }

  public static func decode(_ data: Data) throws -> [DepthSample] {
    var reader = ByteReader(data)
    guard try reader.readBytes(4) == magic else { throw RawOriginalsError.badMagic("CHDS") }
    let found = try reader.readU32()
    guard found == version else { throw RawOriginalsError.unsupportedVersion(found) }
    let count = Int(try reader.readU32())
    _ = try reader.readU32()
    guard reader.remaining == count * recordSize else { throw RawOriginalsError.truncated }
    var samples: [DepthSample] = []
    samples.reserveCapacity(count)
    for _ in 0..<count {
      samples.append(
        DepthSample(
          x: try reader.readF32(), y: try reader.readF32(), z: try reader.readF32(),
          red: try reader.readU8(), green: try reader.readU8(), blue: try reader.readU8(),
          confidence: try reader.readU8()))
    }
    return samples
  }

  /// Samples at or above `minimum` confidence. The live session applies this when sampling
  /// (the contract keeps points with confidence of medium or better); the writer never changes
  /// what it is given.
  public static func filter(_ samples: [DepthSample], minimumConfidence: UInt8 = DepthSample.mediumConfidence)
    -> [DepthSample]
  {
    samples.filter { $0.confidence >= minimumConfidence }
  }
}

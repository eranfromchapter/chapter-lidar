import Foundation

/// Little-endian byte buffer helpers shared by the binary writers.
struct ByteBuffer {
  var bytes: [UInt8] = []

  init(capacity: Int = 0) {
    bytes.reserveCapacity(capacity)
  }

  mutating func append(_ value: UInt8) { bytes.append(value) }

  mutating func append(_ value: UInt16) {
    bytes.append(UInt8(truncatingIfNeeded: value))
    bytes.append(UInt8(truncatingIfNeeded: value >> 8))
  }

  mutating func append(_ value: Int16) { append(UInt16(bitPattern: value)) }

  mutating func append(_ value: UInt32) {
    for shift in stride(from: 0, to: 32, by: 8) {
      bytes.append(UInt8(truncatingIfNeeded: value >> UInt32(shift)))
    }
  }

  mutating func append(_ value: Int32) { append(UInt32(bitPattern: value)) }

  mutating func append(_ value: UInt64) {
    for shift in stride(from: 0, to: 64, by: 8) {
      bytes.append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
    }
  }

  mutating func append(_ value: Float) { append(value.bitPattern) }
  mutating func append(_ value: Double) { append(value.bitPattern) }

  /// ASCII text padded with zeros (or cut) to exactly `length` bytes.
  mutating func appendFixedASCII(_ text: String, length: Int) {
    var written = 0
    for byte in text.utf8 where written < length {
      bytes.append(byte)
      written += 1
    }
    while written < length {
      bytes.append(0)
      written += 1
    }
  }

  mutating func append(contentsOf other: [UInt8]) { bytes.append(contentsOf: other) }

  /// Appends zero bytes until the length is a multiple of 4.
  mutating func padTo4(with fill: UInt8 = 0) {
    while bytes.count % 4 != 0 { bytes.append(fill) }
  }

  var count: Int { bytes.count }
}

/// Fixed-decimal number formatting without Foundation's slow `String(format:)`.
enum DecimalText {
  /// Appends `value` with exactly `decimals` digits after the point ("-0.000000" never appears).
  static func appendFixed(_ value: Double, decimals: Int, to out: inout [UInt8]) {
    var scale = 1.0
    for _ in 0..<decimals { scale *= 10 }
    let scaled = (abs(value) * scale).rounded()
    let whole = UInt64(scaled)
    if value < 0 && whole != 0 { out.append(UInt8(ascii: "-")) }
    let integerPart = whole / UInt64(scale)
    var fraction = whole % UInt64(scale)
    appendInteger(integerPart, to: &out)
    guard decimals > 0 else { return }
    out.append(UInt8(ascii: "."))
    var digits = [UInt8](repeating: UInt8(ascii: "0"), count: decimals)
    var index = decimals - 1
    while fraction > 0 && index >= 0 {
      digits[index] = UInt8(ascii: "0") + UInt8(fraction % 10)
      fraction /= 10
      index -= 1
    }
    out.append(contentsOf: digits)
  }

  static func appendInteger(_ value: UInt64, to out: inout [UInt8]) {
    if value == 0 {
      out.append(UInt8(ascii: "0"))
      return
    }
    var digits: [UInt8] = []
    var rest = value
    while rest > 0 {
      digits.append(UInt8(ascii: "0") + UInt8(rest % 10))
      rest /= 10
    }
    out.append(contentsOf: digits.reversed())
  }

  static func append(_ text: String, to out: inout [UInt8]) {
    out.append(contentsOf: Array(text.utf8))
  }
}

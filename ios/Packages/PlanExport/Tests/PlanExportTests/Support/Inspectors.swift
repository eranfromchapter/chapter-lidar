import Foundation

/// Reads the DXF tag pairs written by DXFWriter, without using DXFWriter code.
struct DXFFile {
  struct Entity {
    var type: String
    var pairs: [(code: Int, value: String)]

    var layer: String { value(8) ?? "" }
    func value(_ code: Int) -> String? { pairs.first { $0.code == code }?.value }
    func number(_ code: Int) -> Double { Double(value(code) ?? "") ?? .nan }
    func values(_ code: Int) -> [String] { pairs.filter { $0.code == code }.map(\.value) }
  }

  var header: [String: [(code: Int, value: String)]] = [:]
  var layerNames: [String] = []
  var entities: [Entity] = []
  var endsWithEOF = false
  var sections: [String] = []

  init(_ text: String) {
    var pairs: [(Int, String)] = []
    let lines = text.components(separatedBy: "\n")
    var index = 0
    while index + 1 < lines.count {
      if let code = Int(lines[index].trimmingCharacters(in: .whitespaces)) {
        pairs.append((code, lines[index + 1]))
      }
      index += 2
    }
    endsWithEOF = pairs.last.map { $0.0 == 0 && $0.1 == "EOF" } ?? false

    var section = ""
    var tableName = ""
    var current: Entity?
    var variable = ""
    var expectSectionName = false
    var expectTableName = false
    func flush() {
      if let entity = current {
        if section == "ENTITIES" {
          entities.append(entity)
        } else if section == "TABLES", tableName == "LAYER", let name = entity.value(2) {
          layerNames.append(name)
        }
      }
      current = nil
    }
    for (code, value) in pairs {
      if code == 0 {
        flush()
        switch value {
        case "SECTION": expectSectionName = true
        case "ENDSEC": section = ""
        case "TABLE": expectTableName = true
        case "ENDTAB": tableName = ""
        case "EOF": break
        default:
          if section == "ENTITIES" || (section == "TABLES" && tableName == "LAYER") {
            current = Entity(type: value, pairs: [])
          }
        }
        continue
      }
      if expectSectionName, code == 2 {
        section = value
        sections.append(value)
        expectSectionName = false
        continue
      }
      if expectTableName, code == 2 {
        tableName = value
        expectTableName = false
        continue
      }
      if section == "HEADER" {
        if code == 9 {
          variable = value
          header[variable] = []
        } else {
          header[variable, default: []].append((code, value))
        }
        continue
      }
      current?.pairs.append((code, value))
    }
    flush()
  }

  func entities(on layer: String) -> [Entity] { entities.filter { $0.layer == layer } }

  /// Vertices of an LWPOLYLINE in order.
  func vertices(of entity: Entity) -> [(Double, Double)] {
    var points: [(Double, Double)] = []
    var x: Double?
    for pair in entity.pairs {
      if pair.code == 10 {
        x = Double(pair.value)
      } else if pair.code == 20, let px = x {
        points.append((px, Double(pair.value) ?? .nan))
        x = nil
      }
    }
    return points
  }

  func lineLength(_ entity: Entity) -> Double {
    let dx = entity.number(11) - entity.number(10)
    let dy = entity.number(21) - entity.number(20)
    return (dx * dx + dy * dy).squareRoot()
  }
}

/// Reads PDFs written by PDFDocument: structure, page content streams and shown text.
struct PDFFile {
  let data: Data
  let text: String  // Latin-1 view of every byte

  struct Segment {
    var widthPoints: Double
    var x1: Double, y1: Double, x2: Double, y2: Double
    var lengthMM: Double {
      ((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1)).squareRoot() * 25.4 / 72
    }
  }

  init(_ data: Data) {
    self.data = data
    text = String(data.map { Character(Unicode.Scalar($0)) })
  }

  var header: String { String(text.prefix(8)) }

  /// Page content streams, in page order (embedded font programs, which carry `/Length1`,
  /// are left out).
  var contentStreams: [String] {
    var out: [String] = []
    var rest = Substring(text)
    while let start = rest.range(of: "stream\n") {
      let afterStart = start.upperBound
      guard let end = rest[afterStart...].range(of: "endstream") else { break }
      let dictionary = rest[..<start.lowerBound].range(of: "<<", options: .backwards)
        .map { rest[$0.lowerBound..<start.lowerBound] } ?? ""
      if !dictionary.contains("/Length1") {
        out.append(String(rest[afterStart..<end.lowerBound]))
      }
      rest = rest[end.upperBound...]
    }
    return out
  }

  /// BaseFont names of the fonts the document declares.
  var baseFonts: [String] {
    var out: [String] = []
    var rest = Substring(text)
    while let range = rest.range(of: "/BaseFont /") {
      let name = rest[range.upperBound...].prefix { !$0.isWhitespace && $0 != "/" && $0 != ">" }
      out.append(String(name))
      rest = rest[range.upperBound...]
    }
    return out
  }

  /// `m`/`l`/`S` two-point lines with the stroke width in force.
  func segments(page: Int = 0) -> [Segment] {
    var width = 1.0
    var out: [Segment] = []
    for line in contentStreams[page].split(separator: "\n") {
      let tokens = line.split(separator: " ")
      if tokens.count == 2, tokens[1] == "w" { width = Double(tokens[0]) ?? width }
      if tokens.count == 7, tokens[2] == "m", tokens[5] == "l", tokens[6] == "S",
        let x1 = Double(tokens[0]), let y1 = Double(tokens[1]), let x2 = Double(tokens[3]),
        let y2 = Double(tokens[4])
      {
        out.append(Segment(widthPoints: width, x1: x1, y1: y1, x2: x2, y2: y2))
      }
    }
    return out
  }

  /// Strings shown with Tj on a page, unescaped and decoded from WinAnsi (Latin-1 range).
  func shownText(page: Int? = nil) -> [String] {
    let streams = page.map { [contentStreams[$0]] } ?? contentStreams
    var out: [String] = []
    for stream in streams {
      for line in stream.split(separator: "\n") where line.hasSuffix(") Tj ET") {
        guard let open = line.firstIndex(of: "(") else { continue }
        let body = line[line.index(after: open)..<line.index(line.endIndex, offsetBy: -7)]
        out.append(PDFFile.unescape(String(body)))
      }
    }
    return out
  }

  static func unescape(_ body: String) -> String {
    var out = ""
    var chars = Array(body)
    var index = 0
    while index < chars.count {
      let c = chars[index]
      if c == "\\", index + 1 < chars.count {
        let next = chars[index + 1]
        if next.isNumber {
          var digits = ""
          var cursor = index + 1
          while cursor < chars.count, chars[cursor].isNumber, digits.count < 3 {
            digits.append(chars[cursor])
            cursor += 1
          }
          if let value = UInt32(digits, radix: 8), let scalar = Unicode.Scalar(value) {
            out.unicodeScalars.append(scalar)
          }
          index = cursor
          continue
        }
        out.append(next)
        index += 2
        continue
      }
      out.append(c)
      index += 1
    }
    chars.removeAll()
    return out
  }

  var mediaBoxes: [[Double]] {
    var out: [[Double]] = []
    var rest = Substring(text)
    while let range = rest.range(of: "/MediaBox [") {
      let after = rest[range.upperBound...]
      guard let close = after.firstIndex(of: "]") else { break }
      out.append(after[..<close].split(separator: " ").compactMap { Double($0) })
      rest = after[close...]
    }
    return out
  }
}

/// A zlib decoder for stored and fixed-Huffman blocks, which is all PNGEncoder writes.
enum TestInflate {
  struct Failure: Error, CustomStringConvertible {
    var description: String
  }

  static func zlib(_ bytes: [UInt8]) throws -> [UInt8] {
    guard bytes.count >= 6 else { throw Failure(description: "too short") }
    guard (Int(bytes[0]) << 8 | Int(bytes[1])) % 31 == 0, bytes[0] & 0x0F == 8 else {
      throw Failure(description: "bad zlib header")
    }
    var position = 2 * 8
    func bit() throws -> Int {
      guard position / 8 < bytes.count - 4 else { throw Failure(description: "out of data") }
      let value = Int(bytes[position / 8] >> UInt8(position % 8)) & 1
      position += 1
      return value
    }
    func bits(_ count: Int) throws -> Int {
      var value = 0
      for index in 0..<count { value |= try bit() << index }
      return value
    }
    func code(_ count: Int) throws -> Int {
      var value = 0
      for _ in 0..<count { value = value << 1 | (try bit()) }
      return value
    }
    let lengthBase = [
      3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115,
      131, 163, 195, 227, 258,
    ]
    let lengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    let distanceBase = [
      1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537,
      2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577,
    ]
    let distanceExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]

    var out: [UInt8] = []
    var final = false
    while !final {
      final = try bit() == 1
      let type = try bits(2)
      if type == 0 {
        position = (position + 7) / 8 * 8
        let length = Int(bytes[position / 8]) | Int(bytes[position / 8 + 1]) << 8
        position += 32
        out += bytes[(position / 8)..<(position / 8 + length)]
        position += length * 8
      } else if type == 1 {
        while true {
          var symbol = try code(7)
          if symbol <= 0b0010111 {
            symbol += 256
          } else {
            symbol = symbol << 1 | (try bit())
            if symbol >= 0x30 && symbol <= 0xBF {
              symbol -= 0x30
            } else if symbol >= 0xC0 && symbol <= 0xC7 {
              symbol = symbol - 0xC0 + 280
            } else {
              symbol = symbol << 1 | (try bit())
              guard symbol >= 0x190 else { throw Failure(description: "bad code") }
              symbol = symbol - 0x190 + 144
            }
          }
          if symbol < 256 {
            out.append(UInt8(symbol))
          } else if symbol == 256 {
            break
          } else {
            let index = symbol - 257
            let length = lengthBase[index] + (try bits(lengthExtra[index]))
            let distanceIndex = try code(5)
            let distance = distanceBase[distanceIndex] + (try bits(distanceExtra[distanceIndex]))
            guard distance <= out.count else { throw Failure(description: "distance too far") }
            for _ in 0..<length { out.append(out[out.count - distance]) }
          }
        }
      } else {
        throw Failure(description: "unsupported block type \(type)")
      }
    }
    // Adler-32 trailer.
    position = (position + 7) / 8 * 8
    let tail = bytes[(position / 8)...]
    guard tail.count == 4 else { throw Failure(description: "trailer is \(tail.count) bytes") }
    var a: UInt32 = 1
    var b: UInt32 = 0
    for byte in out {
      a = (a + UInt32(byte)) % 65521
      b = (b + a) % 65521
    }
    let expected = b << 16 | a
    let stored = tail.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    guard stored == expected else { throw Failure(description: "adler mismatch") }
    return out
  }
}

/// PNG structure reader: chunk list with CRC checks and the decoded pixel rows, for unfiltered
/// 8-bit grayscale and RGB.
struct PNGFile {
  struct Chunk {
    var type: String
    var body: [UInt8]
  }
  var width = 0
  var height = 0
  /// IHDR colour type: 0 grayscale, 2 RGB.
  var colorType = 0
  var chunks: [Chunk] = []
  /// Samples, row-major: one byte per pixel for grayscale, three (R, G, B) for RGB.
  var pixels: [UInt8] = []

  var channels: Int { colorType == 2 ? 3 : 1 }

  /// The pixel at column `x`, row `y` (from the top) as R, G, B (a gray level three times).
  func rgb(_ x: Int, _ y: Int) -> [UInt8] {
    let index = (y * width + x) * channels
    return channels == 3
      ? Array(pixels[index..<(index + 3)]) : Array(repeating: pixels[index], count: 3)
  }

  struct Failure: Error, CustomStringConvertible {
    var description: String
  }

  init(_ data: Data) throws {
    let bytes = [UInt8](data)
    guard bytes.prefix(8) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] else {
      throw Failure(description: "bad signature")
    }
    var index = 8
    func be32(_ at: Int) -> Int {
      Int(bytes[at]) << 24 | Int(bytes[at + 1]) << 16 | Int(bytes[at + 2]) << 8 | Int(bytes[at + 3])
    }
    var idat: [UInt8] = []
    while index + 12 <= bytes.count {
      let length = be32(index)
      let type = String(decoding: bytes[(index + 4)..<(index + 8)], as: UTF8.self)
      let body = Array(bytes[(index + 8)..<(index + 8 + length)])
      let stored = UInt32(be32(index + 8 + length))
      var crc: UInt32 = 0xFFFF_FFFF
      for byte in bytes[(index + 4)..<(index + 8 + length)] {
        crc ^= UInt32(byte)
        for _ in 0..<8 { crc = crc & 1 == 1 ? 0xEDB8_8320 ^ (crc >> 1) : crc >> 1 }
      }
      guard crc ^ 0xFFFF_FFFF == stored else { throw Failure(description: "bad CRC in \(type)") }
      chunks.append(Chunk(type: type, body: body))
      if type == "IHDR" {
        width = be32(index + 8)
        height = be32(index + 12)
        guard body[8] == 8, body[9] == 0 || body[9] == 2, body[10...12] == [0, 0, 0] else {
          throw Failure(description: "unsupported IHDR \(Array(body[8...12]))")
        }
        colorType = Int(body[9])
      }
      if type == "IDAT" { idat += body }
      index += 12 + length
    }
    guard index == bytes.count else { throw Failure(description: "trailing bytes") }
    let raw = try TestInflate.zlib(idat)
    let rowBytes = width * channels
    guard raw.count == (rowBytes + 1) * height else { throw Failure(description: "raw size") }
    for row in 0..<height {
      guard raw[row * (rowBytes + 1)] == 0 else { throw Failure(description: "filter") }
      pixels += raw[(row * (rowBytes + 1) + 1)..<((row + 1) * (rowBytes + 1))]
    }
  }

  func chunk(_ type: String) -> Chunk? { chunks.first { $0.type == type } }
}

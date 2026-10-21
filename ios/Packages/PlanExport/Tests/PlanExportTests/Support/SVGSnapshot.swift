import Foundation
import XCTest

/// SVG references for the visual checks, kept as the phone's snapshot harness keeps its PNGs
/// (`ChapterSnapshot`): `__Snapshots__/<test file name>/<name>.svg` next to the test file,
/// recorded with `RECORD_SNAPSHOTS=1`; a recording run fails on purpose, so it is never
/// mistaken for a pass. An SVG opens in any browser for review, and the comparison is
/// numeric: every number may differ by 0.01 (the writers' last decimal, which a different
/// libm may round the other way), everything else must be the same text. On a mismatch the
/// new SVG is written to `.build/test-output/snapshots/`.
enum SVGSnapshot {
  static var isRecording: Bool {
    ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"
  }

  static func referenceURL(name: String, file: StaticString) -> URL {
    let testFile = URL(fileURLWithPath: "\(file)", isDirectory: false)
    return testFile.deletingLastPathComponent()
      .appendingPathComponent("__Snapshots__", isDirectory: true)
      .appendingPathComponent(testFile.deletingPathExtension().lastPathComponent, isDirectory: true)
      .appendingPathComponent("\(name).svg", isDirectory: false)
  }

  /// The text split into numbers and the text between them.
  static func tokens(_ text: String) -> [(text: String, number: Double?)] {
    var out: [(String, Double?)] = []
    let scalars = Array(text.unicodeScalars)
    var index = 0
    var plain = ""
    func isDigit(_ i: Int) -> Bool {
      i < scalars.count && scalars[i].value >= 0x30 && scalars[i].value <= 0x39
    }
    func isScalar(_ i: Int, _ scalar: Unicode.Scalar) -> Bool {
      i < scalars.count && scalars[i] == scalar
    }
    while index < scalars.count {
      let starts = isDigit(index) || (isScalar(index, "-") && isDigit(index + 1))
      guard starts else {
        plain.unicodeScalars.append(scalars[index])
        index += 1
        continue
      }
      if !plain.isEmpty {
        out.append((plain, nil))
        plain = ""
      }
      var number = String(scalars[index])
      index += 1
      while isDigit(index) || (isScalar(index, ".") && isDigit(index + 1)) {
        number.unicodeScalars.append(scalars[index])
        index += 1
      }
      out.append((number, Double(number)))
    }
    if !plain.isEmpty { out.append((plain, nil)) }
    return out
  }

  /// The first difference between `actual` and `reference`, nil when they match.
  static func difference(_ actual: String, _ reference: String, tolerance: Double = 0.0101)
    -> String?
  {
    let a = tokens(actual)
    let b = tokens(reference)
    for (index, (x, y)) in zip(a, b).enumerated() {
      if let p = x.number, let q = y.number {
        if abs(p - q) > tolerance { return "token \(index): \(x.text) instead of \(y.text)" }
      } else if x.text != y.text {
        return "token \(index): \"\(x.text)\" instead of \"\(y.text)\""
      }
    }
    return a.count == b.count ? nil : "\(a.count) tokens instead of \(b.count)"
  }

  static func assertMatches(
    _ svg: String, named name: String, record: Bool = isRecording,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    let url = referenceURL(name: name, file: file)
    let manager = FileManager.default
    if record || !manager.fileExists(atPath: url.path) {
      do {
        try manager.createDirectory(
          at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(svg.utf8).write(to: url, options: .atomic)
        let why = record ? "RECORD_SNAPSHOTS is set" : "there was no reference"
        XCTFail(
          "Snapshot \(name): recorded \(url.path) (\(why)). Look at it, then run again without "
            + "RECORD_SNAPSHOTS.", file: file, line: line)
      } catch {
        XCTFail("Snapshot \(name): could not write \(url.path): \(error)", file: file, line: line)
      }
      return
    }
    guard let data = manager.contents(atPath: url.path) else {
      return XCTFail("Snapshot \(name): could not read \(url.path)", file: file, line: line)
    }
    guard let difference = difference(svg, String(decoding: data, as: UTF8.self)) else { return }
    let actual = Repo.testOutput.appendingPathComponent("snapshots/\(name).svg")
    try? manager.createDirectory(
      at: actual.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? Data(svg.utf8).write(to: actual)
    XCTFail(
      "Snapshot \(name) differs from \(url.lastPathComponent) at \(difference); new SVG: "
        + actual.path, file: file, line: line)
  }
}

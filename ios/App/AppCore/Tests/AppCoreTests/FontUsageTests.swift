import Foundation
import XCTest

/// The phone's own screens draw no SF text (owner decision, Oct 21, 2026; phone-capture §1,
/// §10.4): Inter for everything, Times New Roman for the large titles, the system monospaced
/// font for the timer and ids. SwiftUI's `Text` keeps no UIKit font a running app could be asked
/// about, so the sources of every screen are read here: no SF text style (`.font(.body)`,
/// `.font(.system(size:))`, `UIFont.systemFont`, …) except the monospaced one, and SF only for
/// SF Symbols (an `Image(systemName:)` sized with a system font is an icon, not text). The UI
/// test `debug.fontAudit` checks the UIKit text at run time. Also: no typed "chapter /
/// RENOVATION" wordmark (phone-capture §10.4).
final class FontUsageTests: XCTestCase {
  /// The screens' sources: the app, the capture, field and package screens, the components.
  private static let screenSources = [
    "ios/App/Sources/App",
    "ios/Packages/CaptureCore/Sources/CaptureUI",
    "ios/Packages/FieldKit/Sources/FieldKitUI",
    "ios/Packages/ChapterUI/Sources/ChapterUI",
  ]

  private static let systemTextStyle = try! NSRegularExpression(
    pattern:
      #"\.font\(\s*\.(system|body|headline|title|title2|title3|subheadline|caption|caption2|footnote|callout|largeTitle)\b|Font\.system\(|UIFont\.(systemFont|preferredFont|boldSystemFont|italicSystemFont)\("#
  )

  private func swiftFiles(under path: String) -> [URL] {
    let root = Fixtures.repositoryRoot.appendingPathComponent(path, isDirectory: true)
    let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
    var files: [URL] = []
    while let url = enumerator?.nextObject() as? URL {
      if url.pathExtension == "swift" { files.append(url) }
    }
    return files
  }

  func testTheScreensUseNoSFText() throws {
    var offenders: [String] = []
    var checked = 0
    for folder in Self.screenSources {
      for file in swiftFiles(under: folder) {
        checked += 1
        let lines = try String(contentsOf: file, encoding: .utf8)
          .components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
          let range = NSRange(line.startIndex..., in: line)
          guard Self.systemTextStyle.firstMatch(in: line, range: range) != nil else { continue }
          if line.contains("design: .monospaced") || line.contains("monospacedSystemFont") {
            continue
          }
          // An SF Symbol sized with a system font: an icon, not text.
          let before = lines[max(0, index - 2)...index].joined(separator: " ")
          if before.contains("Image(systemName:") { continue }
          offenders.append("\(file.lastPathComponent):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
        }
      }
    }
    XCTAssertGreaterThan(checked, 40, "the screens' sources were found")
    XCTAssertEqual(offenders, [], "SF text on the phone's own screens")
  }

  func testNoTypedWordmark() throws {
    var offenders: [String] = []
    for folder in Self.screenSources {
      for file in swiftFiles(under: folder) where file.lastPathComponent != "ChapterLogoData.swift" {
        let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
        for (index, line) in lines.enumerated() where line.contains("RENOVATION") {
          // Comments and accessibility labels may name the logo; no code may type it.
          let code = line.trimmingCharacters(in: .whitespaces)
          if code.hasPrefix("//") || code.hasPrefix("///") { continue }
          offenders.append("\(file.lastPathComponent):\(index + 1): \(code)")
        }
      }
    }
    XCTAssertEqual(offenders, [])
  }
}

#if canImport(UIKit) && canImport(XCTest) && os(iOS)
  import ChapterUI
  import ImageIO
  import SwiftUI
  import UIKit
  import UniformTypeIdentifiers
  import XCTest

  /// The one snapshot harness of the phone (critique R-18d), used by every phone snapshot test
  /// (ChapterUI, CaptureUI, FieldKitUI, the package screens).
  ///
  ///     final class HomeSnapshotTests: ChapterSnapshotTestCase {
  ///       @MainActor func testDrawnState() {
  ///         assertChapterSnapshot(of: NavigationStack { CapturesHomeScreen(state: .drawn) },
  ///                               named: "home")
  ///       }
  ///     }
  ///
  /// References are PNGs in `__Snapshots__/<test file name>/<name>.png` next to the test file.
  /// Record them with `RECORD_SNAPSHOTS=1` (through xcodebuild: `TEST_RUNNER_RECORD_SNAPSHOTS=1
  /// xcodebuild test …`); a recording run fails on purpose, so it is never mistaken for a pass.
  /// On a mismatch the new image, the reference and a diff are attached to the test and written
  /// to `$SNAPSHOT_ARTIFACTS` (default: the temporary directory, `ChapterUISnapshots/`).
  ///
  /// Run on an iPhone 17 Pro simulator with iOS 26.0 (`referenceSystemVersion`; CI: ios.yml
  /// pins it), whose screen is the 402 × 874 pt @3x artboard frame. Other iOS versions draw the
  /// system chrome (navigation bar, switches) differently, by more than the tolerance.
  public enum ChapterSnapshot {
    /// The iOS version of the simulator every phone reference is recorded and compared on.
    public static let referenceSystemVersion = "26.0"

    /// Registers the fonts and applies the navigation bar appearance, as the app does at launch.
    /// `ChapterSnapshotTestCase` calls it in `setUp`. (The harness puts `chapterRoot()` on every
    /// view it draws.)
    @MainActor
    public static func prepare() {
      ChapterFonts.register()
      ChapterAppearance.apply()
    }

    /// True for the reference iOS version and its point releases ("26.0", "26.0.1").
    static func isReferenceSystem(_ version: String) -> Bool {
      version == referenceSystemVersion || version.hasPrefix(referenceSystemVersion + ".")
    }

    /// The simulator of this run, e.g. "iOS 18.5 on iPhone 16 Pro".
    @MainActor
    static var currentRuntime: String {
      let device = UIDevice.current
      let name = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? device.model
      return "\(device.systemName) \(device.systemVersion) on \(name)"
    }

    /// True when the environment asks to record references instead of comparing.
    public static var isRecording: Bool {
      ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"
    }

    /// Where the reference of `name` lives for the test file `file`.
    public static func referenceURL(name: String, file: StaticString) -> URL {
      let testFile = URL(fileURLWithPath: "\(file)", isDirectory: false)
      return testFile.deletingLastPathComponent()
        .appendingPathComponent("__Snapshots__", isDirectory: true)
        .appendingPathComponent(
          testFile.deletingPathExtension().lastPathComponent, isDirectory: true
        )
        .appendingPathComponent("\(name).png", isDirectory: false)
    }

    static var artifactsDirectory: URL {
      if let path = ProcessInfo.processInfo.environment["SNAPSHOT_ARTIFACTS"], !path.isEmpty {
        return URL(fileURLWithPath: path, isDirectory: true)
      }
      return FileManager.default.temporaryDirectory
        .appendingPathComponent("ChapterUISnapshots", isDirectory: true)
    }

    static func cgImage(png data: Data) -> CGImage? {
      guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
      return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func pngData(_ image: CGImage) -> Data? {
      let data = NSMutableData()
      guard
        let destination = CGImageDestinationCreateWithData(
          data, UTType.png.identifier as CFString, 1, nil)
      else { return nil }
      CGImageDestinationAddImage(destination, image, nil)
      return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
  }

  /// Registers the fonts and applies the appearance before each test (critique R-18d).
  open class ChapterSnapshotTestCase: XCTestCase {
    override open func setUp() {
      super.setUp()
      MainActor.assumeIsolated { ChapterSnapshot.prepare() }
    }
  }

  /// Renders `view` with `SnapshotRenderer` and compares it with the reference `name`; fails when
  /// more than 0.5 % of the pixels differ by more than 8/255 (`SnapshotTolerance.phone`), when the
  /// sizes differ, when there is no reference yet (it is recorded), or when recording.
  @MainActor
  public func assertChapterSnapshot<V: View>(
    of view: V, named name: String, size: CGSize = SnapshotRenderer.deviceSize,
    contentSize: UIContentSizeCategory = .large, tolerance: SnapshotTolerance = .phone,
    record: Bool = ChapterSnapshot.isRecording, file: StaticString = #filePath, line: UInt = #line
  ) {
    let referenceURL = ChapterSnapshot.referenceURL(name: name, file: file)
    let rendered = SnapshotRenderer.image(of: view, size: size, contentSize: contentSize)
    guard let png = rendered.pngData(), let actual = ChapterSnapshot.cgImage(png: png) else {
      XCTFail("Snapshot \(name): the view could not be rendered", file: file, line: line)
      return
    }

    let fileManager = FileManager.default
    if record || !fileManager.fileExists(atPath: referenceURL.path) {
      do {
        try fileManager.createDirectory(
          at: referenceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: referenceURL, options: .atomic)
        let why = record ? "RECORD_SNAPSHOTS is set" : "there was no reference"
        XCTFail(
          "Snapshot \(name): recorded \(referenceURL.path) (\(why)). Look at it, then run again "
            + "without RECORD_SNAPSHOTS.", file: file, line: line)
      } catch {
        XCTFail(
          "Snapshot \(name): could not write \(referenceURL.path): \(error)", file: file, line: line
        )
      }
      return
    }

    guard let data = try? Data(contentsOf: referenceURL),
      let reference = ChapterSnapshot.cgImage(png: data)
    else {
      XCTFail("Snapshot \(name): could not read \(referenceURL.path)", file: file, line: line)
      return
    }
    let (result, diff) = SnapshotComparison.compare(
      reference: reference, actual: actual, channelTolerance: tolerance.channelTolerance)
    guard !result.passes(tolerance) else { return }

    // Keep the evidence: attachments in the result bundle, and files on disk.
    let directory = ChapterSnapshot.artifactsDirectory
    try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    let actualURL = directory.appendingPathComponent("\(name).actual.png")
    try? png.write(to: actualURL, options: .atomic)
    var images = [("\(name).actual.png", png), ("\(name).reference.png", data)]
    if let diff, let diffPNG = ChapterSnapshot.pngData(diff) {
      try? diffPNG.write(to: directory.appendingPathComponent("\(name).diff.png"), options: .atomic)
      images.append(("\(name).diff.png", diffPNG))
    }
    XCTContext.runActivity(named: "Snapshot \(name)") { activity in
      for (fileName, bytes) in images {
        let attachment = XCTAttachment(data: bytes, uniformTypeIdentifier: UTType.png.identifier)
        attachment.name = fileName
        attachment.lifetime = .keepAlways
        activity.add(attachment)
      }
    }
    func pixels(_ size: CGSize) -> String { "\(Int(size.width)) x \(Int(size.height)) px" }
    let detail =
      result.sizesMatch
      ? String(
        format: "%.3f %% of the pixels differ by more than %d/255 (limit %.3f %%)",
        result.differingFraction * 100, tolerance.channelTolerance,
        tolerance.maxDifferingFraction * 100)
      : "the size is \(pixels(result.actualSize)), the reference \(pixels(result.referenceSize))"
    let runtime =
      ChapterSnapshot.isReferenceSystem(UIDevice.current.systemVersion)
      ? ""
      : " This run is on \(ChapterSnapshot.currentRuntime); the references are recorded on iOS "
        + "\(ChapterSnapshot.referenceSystemVersion) (iPhone 17 Pro), and the system chrome "
        + "differs between iOS versions."
    XCTFail(
      "Snapshot \(name) does not match \(referenceURL.lastPathComponent): \(detail). New image: "
        + "\(actualURL.path).\(runtime)", file: file, line: line)
  }
#endif

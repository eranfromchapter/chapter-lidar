import Foundation

/// How the app runs.
public enum LaunchMode: Equatable, Sendable {
  /// The real app: RoomPlan scan, camera, Microsoft Entra sign-in, the configured station.
  case live
  /// UI tests only (Debug builds only): the scan replays a bundled fixture capture
  /// (`ReplaySession`), the camera returns the fixture's photo, and sign-in and the station are
  /// in-process stubs. Nothing is sent over the network.
  case uiTestReplay(fixture: String)
  /// Field tests on a real phone before Entra and the station exist (Debug builds only): the
  /// real RoomPlan scan and camera, with the in-process stub sign-in and station. The sealed
  /// package stays on the phone; nothing is sent over the network.
  case fieldTest
}

/// Chooses the launch mode from the process arguments and the Info.plist field-test flag.
///
/// The UI-test mode is selected only when BOTH hold:
/// - the build is a Debug build (`isDebugBuild`, which the app passes from its own `#if DEBUG`), and
/// - the process was launched with `replayArgument` followed by a fixture name.
///
/// The field-test mode is selected when the build is a Debug build, the UI-test mode is not
/// selected, and `fieldTestFlag` (Info.plist `ChapterFieldTest`, build setting
/// `CHAPTER_FIELD_TEST`) is YES.
///
/// A Release build always gets `.live`, whatever the arguments: the stub station and token provider
/// are compiled only in Debug (`#if DEBUG`), so a Release build has nothing to switch to.
public enum LaunchModeResolver {
  /// Launch argument the UI tests pass, followed by the fixture name, e.g. `box-room`.
  public static let replayArgument = "-ChapterUITestReplay"

  /// Info.plist key of the field-test flag.
  public static let fieldTestKey = "ChapterFieldTest"

  /// Fixture names the replay mode accepts (bundled into the Debug app by ios/project.yml).
  public static let knownFixtures: Set<String> = ["box-room"]

  public static func resolve(
    arguments: [String], isDebugBuild: Bool, fieldTestFlag: String? = nil
  ) -> LaunchMode {
    guard isDebugBuild else { return .live }
    if let index = arguments.firstIndex(of: replayArgument),
      arguments.indices.contains(index + 1),
      knownFixtures.contains(arguments[index + 1])
    {
      return .uiTestReplay(fixture: arguments[index + 1])
    }
    if let flag = fieldTestFlag?.trimmingCharacters(in: .whitespaces).uppercased(),
      ["YES", "TRUE", "1"].contains(flag)
    {
      return .fieldTest
    }
    return .live
  }
}

/// What the UI tests ask of the replay mode besides the fixture (Debug builds only; the app
/// reads them only in `LaunchMode.uiTestReplay`). The station's own options (verdict, refused
/// session, offline uploads) are `UITestStationOptions`.
///
/// - `-ChapterUITestCompass verified|approximate|none`: the scripted compass (`FakeCompass`,
///   critique R-24) for the pre-check, the scan reading and the photo camera bearing. Default
///   `verified`.
/// - `-ChapterUITestVisitsRoot <name>`: keep the visits in `UITestVisits-<name>`, so a relaunch
///   finds them (letters, digits, `-` and `_` only). Without it every launch starts empty.
/// - `-ChapterUITestOffline`: also the HUB project list is offline after the first answer, so
///   "New capture" shows the copy saved on this phone (phone-capture §10.3 U4).
/// - `-ChapterUITestTrackingLost <first> <last>`: the replay loses tracking from step `first`
///   to step `last` (phone-capture §10.3 U5).
/// - `-ChapterUITestScanStep <seconds>`: the replay plays one step every that many seconds
///   (default 0.5), so the live scan's states can be seen.
/// - `-ChapterUITestV1Visits`: before the home reads the disk, visit folders as the v1 app left
///   them are made from the fixture (scans only, a draft, a sealed package; no `visit.json`).
/// - `-ChapterUITestNotifyDuringScan`: 1.5 s into a live scan, the "Verdict: …" notification of
///   another capture's newest package is tapped (the open visit must survive it).
public struct UITestLaunchOptions: Equatable, Sendable {
  public static let compassArgument = "-ChapterUITestCompass"
  public static let visitsRootArgument = "-ChapterUITestVisitsRoot"
  public static let offlineArgument = "-ChapterUITestOffline"
  public static let trackingLostArgument = "-ChapterUITestTrackingLost"
  public static let scanStepArgument = "-ChapterUITestScanStep"
  public static let v1VisitsArgument = "-ChapterUITestV1Visits"
  public static let notifyDuringScanArgument = "-ChapterUITestNotifyDuringScan"
  public static let defaultScanStep: TimeInterval = 0.5

  /// `verified`, `approximate` or `none` (`FakeCompass.Script`).
  public var compass: String
  /// The stable visits folder's suffix; nil for a fresh folder at every launch.
  public var visitsRoot: String?
  public var projectsOffline: Bool
  public var trackingLost: ClosedRange<Int>?
  public var scanStep: TimeInterval
  public var seedsV1Visits: Bool
  public var notifiesDuringScan: Bool

  public init(
    compass: String = "verified", visitsRoot: String? = nil, projectsOffline: Bool = false,
    trackingLost: ClosedRange<Int>? = nil, scanStep: TimeInterval = Self.defaultScanStep,
    seedsV1Visits: Bool = false, notifiesDuringScan: Bool = false
  ) {
    self.compass = compass
    self.visitsRoot = visitsRoot
    self.projectsOffline = projectsOffline
    self.trackingLost = trackingLost
    self.scanStep = scanStep
    self.seedsV1Visits = seedsV1Visits
    self.notifiesDuringScan = notifiesDuringScan
  }

  public init(arguments: [String]) {
    func values(after flag: String, count: Int = 1) -> [String]? {
      guard let index = arguments.firstIndex(of: flag), index + count < arguments.count else {
        return nil
      }
      return Array(arguments[(index + 1)...(index + count)])
    }
    let compass = values(after: Self.compassArgument)?.first.flatMap {
      ["verified", "approximate", "none"].contains($0) ? $0 : nil
    }
    let root = values(after: Self.visitsRootArgument)?.first.flatMap { name -> String? in
      let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
      guard !name.isEmpty, name.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
      return name
    }
    var lost: ClosedRange<Int>?
    if let pair = values(after: Self.trackingLostArgument, count: 2),
      let first = Int(pair[0]), let last = Int(pair[1]), first >= 1, last >= first
    {
      lost = first...last
    }
    let step = values(after: Self.scanStepArgument)?.first.flatMap(TimeInterval.init)
      .flatMap { $0 > 0 && $0 <= 10 ? $0 : nil }
    self.init(
      compass: compass ?? "verified", visitsRoot: root,
      projectsOffline: arguments.contains(Self.offlineArgument), trackingLost: lost,
      scanStep: step ?? Self.defaultScanStep,
      seedsV1Visits: arguments.contains(Self.v1VisitsArgument),
      notifiesDuringScan: arguments.contains(Self.notifyDuringScanArgument))
  }

  /// The visits folder's name under Application Support.
  public func visitsFolderName(fresh: UUID = UUID()) -> String {
    "UITestVisits-\(visitsRoot ?? fresh.uuidString)"
  }
}

/// Whether AppCore itself was compiled with the DEBUG condition. The UI-test stubs in AppCore
/// (`UITestStation`) exist only when this is true.
public enum AppCoreBuild {
  #if DEBUG
    public static let isDebug = true
  #else
    public static let isDebug = false
  #endif
}

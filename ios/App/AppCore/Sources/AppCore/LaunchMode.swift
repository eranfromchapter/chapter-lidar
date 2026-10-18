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

/// Whether AppCore itself was compiled with the DEBUG condition. The UI-test stubs in AppCore
/// (`UITestStation`) exist only when this is true.
public enum AppCoreBuild {
  #if DEBUG
    public static let isDebug = true
  #else
    public static let isDebug = false
  #endif
}

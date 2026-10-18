import Foundation

/// How the app runs.
public enum LaunchMode: Equatable, Sendable {
  /// The real app: RoomPlan scan, camera, Microsoft Entra sign-in, the configured station.
  case live
  /// UI tests only (Debug builds only): the scan replays a bundled fixture capture
  /// (`ReplaySession`), the camera returns the fixture's photo, and sign-in and the station are
  /// in-process stubs. Nothing is sent over the network.
  case uiTestReplay(fixture: String)
}

/// Chooses the launch mode from the process arguments.
///
/// The UI-test mode is selected only when BOTH hold:
/// - the build is a Debug build (`isDebugBuild`, which the app passes from its own `#if DEBUG`), and
/// - the process was launched with `replayArgument` followed by a fixture name.
///
/// A Release build always gets `.live`, whatever the arguments: the stub station and token provider
/// are compiled only in Debug (`#if DEBUG`), so a Release build has nothing to switch to.
public enum LaunchModeResolver {
  /// Launch argument the UI tests pass, followed by the fixture name, e.g. `box-room`.
  public static let replayArgument = "-ChapterUITestReplay"

  /// Fixture names the replay mode accepts (bundled into the Debug app by ios/project.yml).
  public static let knownFixtures: Set<String> = ["box-room"]

  public static func resolve(arguments: [String], isDebugBuild: Bool) -> LaunchMode {
    guard isDebugBuild else { return .live }
    guard let index = arguments.firstIndex(of: replayArgument),
      arguments.indices.contains(index + 1)
    else { return .live }
    let fixture = arguments[index + 1]
    guard knownFixtures.contains(fixture) else { return .live }
    return .uiTestReplay(fixture: fixture)
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

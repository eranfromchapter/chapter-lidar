// UI-test mode. DEBUG ONLY: this file is compiled only in the Debug configuration (`#if DEBUG`,
// and ios/project.yml excludes `UITest*` files from Release builds), and it is selected only
// when the app is launched with `-ChapterUITestReplay <fixture>` (LaunchModeResolver).
#if DEBUG
  import AppCore
  import CaptureContract
  import CaptureCore
  import CaptureUI
  import FieldKitUI
  import Foundation
  import StationClient
  import SwiftUI

  enum UITestEnvironment {
    /// Replay scan of the bundled fixture capture, the fixture's photo as the camera, and the
    /// in-process station and token from AppCore. Nothing leaves the simulator.
    @MainActor
    static func services(fixture: String, cacheRoot: URL) -> AppServices {
      let package = Bundle.main.resourceURL!.appendingPathComponent("package", isDirectory: true)
      let captureDirectory = firstDirectory(containing: "roomplan.json", under: package)
      let photo = firstFile(withExtension: "jpg", under: package)
      let storage = UITestBlobStorage()
      let station = StationAPI(
        configuration: try! StationClientConfiguration(stationURL: UITestStationTransport.stationURL),
        tokenProvider: UITestTokenProvider(),
        transport: UITestStationTransport(storage: storage))
      let version = ProcessInfo.processInfo.operatingSystemVersion
      let osVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
      return AppServices(
        station: station,
        projects: ProjectStore(
          source: station, cacheDirectory: cacheRoot.appendingPathComponent("StationCache")),
        blobTransport: UITestBlobTransport(storage: storage), signIn: nil,
        // The simulator has no LiDAR; the replay stands in for the scanner.
        capabilities: DeviceCapabilities(
          model: "UITestReplay", osName: .iOS, osVersion: osVersion,
          supportsSceneReconstructionMesh: true, roomPlanSupported: true),
        device: DeviceInfo(
          model: "UITestReplay", marketingName: "Simulator replay", osName: .iOS,
          osVersion: osVersion, hasLidar: false),
        makeSession: { _ in
          guard let captureDirectory else { throw CaptureSessionError.scanFailed("no fixture") }
          return try ReplaySession(source: ReplaySource.load(directory: captureDirectory))
        },
        photoSource: .fixed({
          guard let photo else { throw CocoaError(.fileNoSuchFile) }
          return try Data(contentsOf: photo)
        }),
        fixedOperator: SignedInOperator(name: UITestTokenProvider.operatorName, userId: nil))
    }

    private static func firstDirectory(containing name: String, under root: URL) -> URL? {
      let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
      while let url = enumerator?.nextObject() as? URL {
        if url.lastPathComponent == name { return url.deletingLastPathComponent() }
      }
      return nil
    }

    private static func firstFile(withExtension ext: String, under root: URL) -> URL? {
      let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
      while let url = enumerator?.nextObject() as? URL {
        if url.pathExtension.lowercased() == ext { return url }
      }
      return nil
    }
  }

  /// The camera viewfinder in UI tests: the real viewfinder screen (`PhotoViewfinder`: title,
  /// Rooms, Done, the rooms that still need a photo, the shutter) over a stand-in for the camera
  /// image; "Take photo" returns the fixture photo, then the real labeling screen is shown.
  struct UITestViewfinder: View {
    let model: PhotoLabelingModel
    let onDone: () -> Void
    let onRenameRooms: (() -> Void)?

    var body: some View {
      if model.pendingOriginal == nil {
        PhotoViewfinder(model: model, onDone: onDone, onRenameRooms: onRenameRooms) {
          ZStack {
            LinearGradient(
              colors: [Color(white: 0.30), Color(white: 0.16)], startPoint: .top,
              endPoint: .bottom)
            Label("Simulator: the fixture photo stands in for the camera", systemImage: "camera")
              .font(ChapterTokens.Typography.caption)
              .foregroundStyle(Color.white.opacity(0.7))
          }
        }
      } else {
        PhotoLabelingView(model: model, onRenameRooms: onRenameRooms)
      }
    }
  }
#endif

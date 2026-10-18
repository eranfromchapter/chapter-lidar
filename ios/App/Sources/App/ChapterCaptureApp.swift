import AppCore
import SwiftUI

/// Chapter Capture: one site visit from the capture record to the station's verdict.
@main
struct ChapterCaptureApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @State private var model = AppModel.make()
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      RootView(model: model)
        .onOpenURL { url in
          // Microsoft Entra sign-in returns here (msauth.<bundle id>://auth).
          model.handleOpenURL(url)
        }
        .onChange(of: scenePhase) { _, phase in
          if phase == .active { model.didBecomeActive() }
        }
    }
  }
}

/// Build-time facts of this app binary.
enum AppBuild {
  /// True only in the Debug configuration. Release builds cannot select the UI-test mode.
  static var isDebug: Bool {
    #if DEBUG
      return true
    #else
      return false
    #endif
  }
}

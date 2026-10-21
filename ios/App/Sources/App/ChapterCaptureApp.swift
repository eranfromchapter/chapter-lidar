import AppCore
import ChapterUI
import SwiftUI

/// Chapter Capture: one site visit from the capture record to the station's verdict.
@main
struct ChapterCaptureApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @State private var model = AppModel.make()
  @Environment(\.scenePhase) private var scenePhase

  init() {
    // Inter is bundled in ChapterUI and registered here, before any screen draws (not through
    // UIAppFonts, which cannot see a package's bundle); then the navigation bar's Chapter look.
    ChapterFonts.register()
    ChapterAppearance.apply()
  }

  var body: some Scene {
    WindowGroup {
      RootView(model: model)
        // Inter replaces SF on the phone: the default for text without a font of its own.
        .font(ChapterTheme.Font.body)
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

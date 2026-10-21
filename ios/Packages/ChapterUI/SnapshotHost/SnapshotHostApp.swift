import SwiftUI

/// The host app of ChapterUIHostedSnapshotTests (ios/project.yml, not part of the Swift
/// package): one empty window. Inside it the tests have a `UIApplication` and a window scene, so
/// `SnapshotRenderer` draws with `drawHierarchy` and the render server composites what the
/// package tests cannot draw (critique R-18d): the iOS 26 glass of the back button and of a
/// switch's knob, and content scrolled under the navigation bar.
@main
struct ChapterUISnapshotHostApp: App {
  var body: some Scene {
    WindowGroup {
      Color.clear
    }
  }
}

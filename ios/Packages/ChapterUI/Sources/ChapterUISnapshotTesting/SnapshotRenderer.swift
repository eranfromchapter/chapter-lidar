#if canImport(UIKit) && canImport(XCTest) && os(iOS)
  import ChapterUI
  import SwiftUI
  import UIKit

  /// Renders SwiftUI views the way every phone snapshot test does (critique R-18d): the view is
  /// hosted in a `UIWindow` of the iPhone 17 Pro screen (402 × 874 pt, safe area 62 pt at the top
  /// and 34 pt at the bottom) in the light appearance, and drawn at scale 3 from the window's
  /// layers, which also draws the UIKit-backed views (`TextField`, `Toggle`, `ScrollView`, the
  /// navigation bar) that `ImageRenderer` leaves out.
  ///
  /// How the window is drawn: in a test bundle with a host app, the window joins the app's window
  /// scene and is drawn with `drawHierarchy(in:afterScreenUpdates: true)`. Swift package tests run
  /// in the bare `xctest` process, which has no `UIApplication`; its windows are not on any render
  /// server, so `drawHierarchy` fails there ("Render server returned error", an all-black image)
  /// and the window's layer tree is drawn in process with `layer.render(in:)` instead. That draws
  /// everything ChapterUI and the screens use, UIKit-backed views included, except what iOS 26
  /// composites in the render server (backdrop and portal layers): the glass of a switch's knob
  /// and of the back button's pill is missing, and the back chevron comes out light. Compare
  /// those parts on a device, not in snapshots.
  @MainActor
  public enum SnapshotRenderer {
    /// The iPhone 16 Pro / 17 Pro screen of every artboard, in points.
    public static let deviceSize = CGSize(width: 402, height: 874)
    /// Its safe area.
    public static let deviceSafeArea = UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0)
    public static let scale: CGFloat = 3

    /// The view drawn in a window of `size` points at scale 3, in 8-bit sRGB. `contentSize` is the
    /// Dynamic Type size (Large is the default; `.accessibilityExtraLarge` is AX3).
    public static func image<V: View>(
      of view: V, size: CGSize = deviceSize, safeArea: UIEdgeInsets = deviceSafeArea,
      contentSize: UIContentSizeCategory = .large
    ) -> UIImage {
      let previousAnimations = UIView.areAnimationsEnabled
      UIView.setAnimationsEnabled(false)
      defer { UIView.setAnimationsEnabled(previousAnimations) }

      let host = UIHostingController(rootView: view.transaction { $0.disablesAnimations = true })
      let appScene = hostWindowScene
      let window: UIWindow
      if let appScene {
        window = UIWindow(windowScene: appScene)
        window.frame = CGRect(origin: .zero, size: size)
      } else {
        window = UIWindow(frame: CGRect(origin: .zero, size: size))
      }
      window.overrideUserInterfaceStyle = .light
      window.traitOverrides.preferredContentSizeCategory = contentSize
      window.rootViewController = host
      window.isHidden = false
      defer {
        window.isHidden = true
        window.rootViewController = nil
      }

      // The same safe area whether or not the test process has a window scene of its own.
      window.layoutIfNeeded()
      let current = host.view.safeAreaInsets
      host.additionalSafeAreaInsets = UIEdgeInsets(
        top: max(0, safeArea.top - current.top), left: max(0, safeArea.left - current.left),
        bottom: max(0, safeArea.bottom - current.bottom),
        right: max(0, safeArea.right - current.right))

      // Let SwiftUI lay out, run onAppear and settle the navigation bar.
      for _ in 0..<3 {
        window.setNeedsLayout()
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
      }

      CATransaction.flush()

      let format = UIGraphicsImageRendererFormat()
      format.scale = scale
      format.opaque = true
      format.preferredRange = .standard
      // A bare window still gets a screen-based scene of its own, but no render server behind it.
      return UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { context in
        if appScene != nil {
          window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        } else {
          window.layer.render(in: context.cgContext)
        }
      }
    }

    /// The host app's window scene, when the tests run inside an app; nil in the bare `xctest`
    /// process of a Swift package (no `UIApplication` exists there, so it is looked up by name).
    static var hostWindowScene: UIWindowScene? {
      let application =
        (NSClassFromString("UIApplication") as? NSObject.Type)?
        .value(forKey: "sharedApplication") as? UIApplication
      return application?.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }
  }
#endif

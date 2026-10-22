// UI-test font check (phone-capture §10.4, phone-field §15.3). DEBUG ONLY: compiled only in the
// Debug configuration (`#if DEBUG`; ios/project.yml excludes `UITest*` files from Release), and
// drawn only in the UI-test mode.
#if DEBUG
  import AppCore
  import ChapterUI
  import SwiftUI
  import UIKit

  /// Two hidden elements for the UI tests, refreshed every second:
  ///
  /// - `debug.fonts`: `ok` only when Inter Regular and SemiBold are registered (phone-field
  ///   §15.3), else what is missing.
  /// - `debug.fontAudit`: `ok` when every UIKit text view on the app's own screens (navigation
  ///   bar titles and buttons, text fields, text views, labels) uses Inter, Times New Roman or
  ///   the system monospaced font; else the offending texts and their fonts. System alerts,
  ///   action sheets and the keyboard are not the app's own screens and are skipped. SwiftUI's
  ///   own `Text` draws without a UIKit font; its fonts are checked in the sources
  ///   (AppCore `FontUsageTests`).
  struct UITestFontAudit: View {
    @State private var fonts = FontAudit.registration()
    @State private var audit = "pending"

    var body: some View {
      if LaunchModeResolver.resolve(
        arguments: ProcessInfo.processInfo.arguments, isDebugBuild: true) != .live
      {
        VStack(spacing: 0) {
          Color.clear
            .frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityLabel(Text("Fonts"))
            .accessibilityValue(Text(fonts))
            .accessibilityIdentifier("debug.fonts")
          Color.clear
            .frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityLabel(Text("Font audit"))
            .accessibilityValue(Text(audit))
            .accessibilityIdentifier("debug.fontAudit")
        }
        .allowsHitTesting(false)
        .task {
          while !Task.isCancelled {
            fonts = FontAudit.registration()
            audit = FontAudit.run()
            try? await Task.sleep(nanoseconds: 700_000_000)
          }
        }
      }
    }
  }

  enum FontAudit {
    /// Font families the phone's own screens may use (owner decision, Oct 21, 2026).
    static let allowedFamilies: Set<String> = ["Inter", "Times New Roman"]

    static func registration() -> String {
      let missing = [ChapterFonts.interRegular, ChapterFonts.interSemiBold].filter {
        UIFont(name: $0, size: 17) == nil
      }
      return missing.isEmpty ? "ok" : "missing \(missing.joined(separator: ", "))"
    }

    /// Walks every window's views; returns "ok" or the offenders.
    @MainActor
    static func run() -> String {
      var offenders: [String] = []
      let windows = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap(\.windows)
        .filter { !isSystemWindow($0) }
      for window in windows {
        visit(window, offenders: &offenders)
      }
      return offenders.isEmpty ? "ok" : offenders.prefix(8).joined(separator: "; ")
    }

    private static func isSystemWindow(_ window: UIWindow) -> Bool {
      let name = String(describing: type(of: window))
      return name.contains("Keyboard") || name.contains("TextEffects")
    }

    @MainActor
    private static func visit(_ view: UIView, offenders: inout [String]) {
      if view.isHidden || view.alpha < 0.01 { return }
      // Not the app's own screens: system alerts and action sheets, menus, the keyboard.
      if let controller = view.next as? UIViewController,
        controller is UIAlertController || controller is UIActivityViewController
      {
        return
      }
      let name = String(describing: type(of: view))
      if name.contains("Alert") || name.contains("ContextMenu") || name.contains("Keyboard")
        || name.contains("StatusBar") || name.contains("ActionSheet")
      {
        return
      }
      if let (text, font) = textAndFont(of: view), !text.isEmpty, !isAllowed(font) {
        offenders.append("\"\(text.prefix(30))\" in \(font.familyName)")
      }
      for subview in view.subviews {
        visit(subview, offenders: &offenders)
      }
    }

    @MainActor
    private static func textAndFont(of view: UIView) -> (String, UIFont)? {
      switch view {
      case let label as UILabel:
        guard let font = label.font else { return nil }
        return (label.text ?? label.attributedText?.string ?? "", font)
      case let field as UITextField:
        guard let font = field.font else { return nil }
        return (field.text?.isEmpty == false ? field.text! : field.placeholder ?? "", font)
      case let textView as UITextView:
        guard let font = textView.font else { return nil }
        return (textView.text ?? "", font)
      default:
        return nil
      }
    }

    private static func isAllowed(_ font: UIFont) -> Bool {
      allowedFamilies.contains(font.familyName)
        || font.fontDescriptor.symbolicTraits.contains(.traitMonoSpace)
    }
  }
#endif

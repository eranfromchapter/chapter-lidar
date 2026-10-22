import AppCore
import ChapterUI
import SwiftUI
import UIKit

struct RootView: View {
  let model: AppModel

  var body: some View {
    ZStack {
      ChapterTheme.Color.ground.ignoresSafeArea()
      switch model.screen {
      case .notConfigured(let issues):
        NotConfiguredView(issues: issues)
      case .signIn:
        SignInView(model: model)
      case .home(let home):
        AppNavigation(home: home)
      }
    }
    .background(WindowTint(color: ChapterTheme.Swatch.ink.uiColor))
    #if DEBUG
      // The UI tests' hidden checks (`debug.fonts`, `debug.fontAudit`, `debug.uploadedRecord`,
      // `debug.nextRevisionNotice`), drawn only in their mode.
      .overlay(alignment: .bottomLeading) {
        HStack(spacing: 0) {
          UITestFontAudit()
          UITestProbeView()
        }
      }
    #endif
  }
}

/// Ink as the window's tint: what UIKit draws on its own takes it too, above all the system
/// alerts' buttons ("Call the PM", "Re-seal"), which SwiftUI's `tint` (`chapterRoot()`) does
/// not reach and which would otherwise be the system blue (off-brand).
private struct WindowTint: UIViewRepresentable {
  let color: UIColor

  func makeUIView(context: Context) -> TintView {
    let view = TintView()
    view.color = color
    return view
  }

  func updateUIView(_ view: TintView, context: Context) {
    view.color = color
    view.apply()
  }

  final class TintView: UIView {
    var color: UIColor = .label

    override func didMoveToWindow() {
      super.didMoveToWindow()
      apply()
    }

    func apply() {
      guard let window, window.tintColor != color else { return }
      window.tintColor = color
    }
  }
}

/// Shown when a configuration value is missing or a placeholder. Nothing is sent anywhere
/// (phone-capture §3.6: the same wording, ChapterTheme type).
struct NotConfiguredView: View {
  let issues: [ConfigurationIssue]

  var body: some View {
    VStack(alignment: .leading, spacing: ChapterTheme.Metric.screenPadding) {
      ChapterLogo(height: ChapterTheme.Metric.logoHeightLarge)
      Text("App is not configured")
        .chapterTextStyle(.largeTitle)
        .foregroundStyle(ChapterTheme.Color.ink)
        .accessibilityAddTraits(.isHeader)
      Text("This build has no sign-in or station settings. Nothing is sent anywhere.")
        .chapterTextStyle(.subhead)
        .foregroundStyle(ChapterTheme.Color.muted)
      ForEach(issues, id: \.self) { issue in
        ProblemLine(text: issue.description)
      }
      Spacer()
    }
    // On the 16 pt margin, whatever the longest line (not centred as a block).
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, ChapterTheme.Metric.screenPadding)
    .padding(.top, 48)
    .chapterContentWidth()
  }
}

/// Microsoft Entra sign-in (phone-capture §3.6): the real Chapter logo (40 pt), "Sign in" in
/// Times, and the primary button. MSAL shows Microsoft's own sign-in page.
struct SignInView: View {
  let model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: ChapterTheme.Metric.screenPadding) {
      ChapterLogo(height: ChapterTheme.Metric.logoHeightLarge)
      Text("Sign in")
        .chapterTextStyle(.largeTitle)
        .foregroundStyle(ChapterTheme.Color.ink)
        .accessibilityAddTraits(.isHeader)
      Text("Use your Chapter Microsoft account.")
        .chapterTextStyle(.subhead)
        .foregroundStyle(ChapterTheme.Color.muted)
      if let message = model.signInMessage {
        ProblemLine(text: message)
      }
      Spacer()
    }
    // On the 16 pt margin, as the button below (not centred as a block).
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, ChapterTheme.Metric.screenPadding)
    .padding(.top, 48)
    .chapterContentWidth()
    .chapterActionBar {
      Button(model.isSigningIn ? "Signing in…" : "Sign in with Microsoft") {
        Task { await model.signIn() }
      }
      .buttonStyle(.chapter(.primary))
      .disabled(model.isSigningIn)
      .accessibilityIdentifier("signIn.microsoft")
    }
  }
}

/// A problem: the ■ glyph drawn as a shape, then the text in the blocked colour.
private struct ProblemLine: View {
  let text: String

  var body: some View {
    HStack(alignment: .top, spacing: ChapterTheme.Metric.statusGlyphGap) {
      StatusGlyph(.missing).padding(.top, 3)
      Text(text)
        .chapterTextStyle(.footnote)
        .foregroundStyle(ChapterTheme.Color.blocked)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .accessibilityElement(children: .combine)
  }
}

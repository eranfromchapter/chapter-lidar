import AppCore
import CaptureUI
import SwiftUI

private typealias Palette = ChapterTokens.Palette
private typealias Space = ChapterTokens.Space
private typealias Typo = ChapterTokens.Typography
private typealias Control = ChapterTokens.Control
private typealias Radius = ChapterTokens.Radius

struct RootView: View {
  let model: AppModel

  var body: some View {
    ZStack {
      Palette.ground.ignoresSafeArea()
      switch model.screen {
      case .notConfigured(let issues):
        NotConfiguredView(issues: issues)
      case .signIn:
        SignInView(model: model)
      case .visit(let visit):
        VisitView(visit: visit)
      }
    }
  }
}

/// Shown when a configuration value is missing or a placeholder. Nothing is sent anywhere.
struct NotConfiguredView: View {
  let issues: [ConfigurationIssue]

  var body: some View {
    VStack(alignment: .leading, spacing: Space.s4) {
      Text("App is not configured").font(Typo.serif(30)).foregroundStyle(Palette.ink)
        .accessibilityAddTraits(.isHeader)
      Text("This build has no sign-in or station settings. Nothing is sent anywhere.")
        .font(Typo.sans(15)).foregroundStyle(Palette.muted)
      ForEach(issues, id: \.self) { issue in
        Text("\u{25A0} \(issue.description)").font(Typo.caption).foregroundStyle(Palette.blocked)
      }
      Spacer()
    }
    .padding(.horizontal, 20)
    .padding(.top, Space.s7)
  }
}

/// Microsoft Entra sign-in. MSAL shows Microsoft's own sign-in page.
struct SignInView: View {
  let model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: Space.s4) {
      VStack(spacing: Space.s1) {
        Text("chapter").font(Typo.serif(30))
        Text("RENOVATION").font(Typo.sans(9)).tracking(4)
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Chapter Renovation")
      Text("Sign in").font(Typo.serif(30)).foregroundStyle(Palette.ink)
      Text("Use your Chapter Microsoft account.").font(Typo.sans(15))
        .foregroundStyle(Palette.muted)
      if let message = model.signInMessage {
        Text("\u{25A0} \(message)").font(Typo.caption).foregroundStyle(Palette.blocked)
      }
      Spacer()
      Button {
        Task { await model.signIn() }
      } label: {
        Text(model.isSigningIn ? "Signing in…" : "Sign in with Microsoft")
          .font(Typo.headline).foregroundStyle(Palette.surface)
          .frame(maxWidth: .infinity, minHeight: Control.primaryHeight)
          .background(Palette.ink, in: RoundedRectangle(cornerRadius: Radius.card))
      }
      .buttonStyle(.plain)
      .disabled(model.isSigningIn)
    }
    .padding(.horizontal, 20)
    .padding(.top, Space.s7)
    .padding(.bottom, 28)
  }
}

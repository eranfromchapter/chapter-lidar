#if canImport(SwiftUI) && canImport(Observation) && os(iOS)
  import ChapterUI
  import SwiftUI

  /// The card centred in the live scan's camera well (phone-capture §3.4.1, §3.4.3, artboard
  /// 2b-3b): width 280, padding 18 at the top and 16 elsewhere, radius 16, the alert-card fill,
  /// centred ink text; a 22 pt glyph, the title (bodyEmphasis), the body (subhead 15/20), and an
  /// optional `.cardAction` button 6 pt further down. VoiceOver announces it when it appears.
  struct ScanCard: View {
    let glyph: StatusKind
    let title: String
    let message: String
    var actionTitle: String?
    var actionIdentifier: String?
    var action: () -> Void = {}

    var body: some View {
      VStack(spacing: 8) {
        StatusGlyph(glyph, size: 22)
        Text(title)
          .chapterTextStyle(.bodyEmphasis)
          .foregroundStyle(ChapterTheme.Color.ink)
        Text(message)
          .chapterTextStyle(.subhead)
          .foregroundStyle(ChapterTheme.Color.ink)
          .fixedSize(horizontal: false, vertical: true)
        if let actionTitle {
          Button(actionTitle, action: action)
            .buttonStyle(.chapter(.cardAction))
            .padding(.top, 6)
            .accessibilityIdentifier(actionIdentifier ?? "")
        }
      }
      .multilineTextAlignment(.center)
      .padding(.top, 18)
      .padding([.horizontal, .bottom], 16)
      .frame(width: 280)
      .background(ChapterTheme.Color.alertCard, in: RoundedRectangle(cornerRadius: 16))
      .accessibilityElement(children: .contain)
      .onAppear {
        AccessibilityNotification.Announcement("\(title). \(message)").post()
      }
    }
  }

  /// The pill at the top of the camera well: the coaching pill (surface, ink text, ▲ before a
  /// RoomPlan warning) while scanning, the translucent "Paused · mm:ss" pill otherwise
  /// (phone-capture §3.4, §3.4.1, §3.4.2). Padding 8 × 12, radius 8; line 2 in footnote, up to 3
  /// lines.
  struct CoachingPill: View {
    enum Style {
      case coaching
      case paused
    }

    let style: Style
    let title: String
    let detail: String?
    var isWarning = false

    var body: some View {
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 5) {
          if isWarning { StatusGlyph(.partly) }
          Text(title)
            .chapterTextStyle(.subheadEmphasis)
            .foregroundStyle(style == .coaching ? ChapterTheme.Color.ink : ChapterTheme.Color.surface)
        }
        if let detail, !detail.isEmpty {
          Text(detail)
            .chapterTextStyle(.footnote)
            .foregroundStyle(
              style == .coaching ? ChapterTheme.Color.ink : ChapterTheme.Color.onDarkCaption
            )
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(.vertical, 8)
      .padding(.horizontal, 12)
      .background(
        style == .coaching ? ChapterTheme.Color.surface : ChapterTheme.Color.onDarkPill,
        in: RoundedRectangle(cornerRadius: 8)
      )
      .accessibilityElement(children: .combine)
    }
  }
#endif

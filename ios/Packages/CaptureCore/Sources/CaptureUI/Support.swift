#if canImport(SwiftUI) && canImport(Observation) && os(iOS)
  import CaptureCore
  import ChapterUI
  import SwiftUI

  extension RowStatusValue.Kind {
    /// The ChapterUI glyph of a CaptureCore status.
    var chapterKind: StatusKind {
      switch self {
      case .done: .done
      case .partly: .partly
      case .missing: .missing
      case .waiting: .waiting
      }
    }
  }

  extension RowStatusValue {
    /// The status as a ChapterUI row status.
    var rowStatus: RowStatus { RowStatus(kind.chapterKind, word) }
  }

  extension CompassPhoneText.Glyph {
    /// The 32 pt glyph and the pill arrow: an arrow only for a usable reading.
    var glyphState: CompassGlyphState {
      switch self {
      case .verified: .verified
      case .approximate: .approximate
      case .none: .notVerified
      }
    }
  }

  /// The widest the caption of `captureNavigationCaption` gets: on the narrowest LiDAR iPhone
  /// (390 pt) it still leaves the back button's 44 pt pill its 16 pt margins and a 16 pt gap.
  let captureCaptionMaxWidth: CGFloat = 280

  /// Proposes its one subview its ideal width up to `maxWidth`: a shorter text keeps its own
  /// width, a longer one gets `maxWidth` and is cut short by its truncation mode.
  struct CappedWidth: Layout {
    let maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
      guard let subview = subviews.first else { return .zero }
      let ideal = subview.sizeThatFits(.unspecified)
      return subview.sizeThatFits(ProposedViewSize(width: min(ideal.width, maxWidth), height: nil))
    }

    func placeSubviews(
      in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
      subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
  }

  extension View {
    /// The right-hand caption of the navigation bar at its own width: the project title of step
    /// 2 when adding a floor ("618 Valley Street") is longer than the bar gives a caption by
    /// default. A longer title (a whole address when the HUB project has no name, R-29) is cut
    /// short with "…" at `captureCaptionMaxWidth`, before it reaches the back button; VoiceOver
    /// reads it whole. Footnote, muted, one line; text, not a button.
    func captureNavigationCaption(_ text: String) -> some View {
      toolbar {
        PlainToolbarItem(placement: .topBarTrailing) {
          CappedWidth(maxWidth: captureCaptionMaxWidth) {
            Text(text)
              .chapterTextStyle(.footnote)
              .foregroundStyle(ChapterTheme.Color.muted)
              .lineLimit(1)
              .truncationMode(.tail)
          }
          .fixedSize()
        }
      }
    }

    /// The content column of a capture screen: 16 pt at the sides, the iPad's 600 pt column.
    func captureContent(top: CGFloat) -> some View {
      padding(.horizontal, ChapterTheme.Metric.screenPadding)
        .padding(.top, top)
        .padding(.bottom, ChapterTheme.Metric.sectionGap)
        .chapterContentWidth()
    }
  }
#endif

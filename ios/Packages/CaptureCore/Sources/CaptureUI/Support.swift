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

  extension View {
    /// The right-hand caption of the navigation bar at its full width: the project title of step
    /// 2 when adding a floor ("618 Valley Street") is longer than the bar gives a caption by
    /// default. Footnote, muted, one line; text, not a button.
    func captureNavigationCaption(_ text: String) -> some View {
      toolbar {
        PlainToolbarItem(placement: .topBarTrailing) {
          Text(text)
            .chapterTextStyle(.footnote)
            .foregroundStyle(ChapterTheme.Color.muted)
            .lineLimit(1)
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

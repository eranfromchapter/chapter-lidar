#if canImport(SwiftUI) && os(iOS)
  import ChapterUI
  import SketchEntry
  import SwiftUI

  // Shared pieces of the sketch screens (spec F14 2.4): the Chapter brand as the capture
  // screens draw it (Inter body text, Times large titles, the system bar with the chevron-only
  // back and the "Step N of 4" caption), and the length row every measurement is typed in.

  /// Proposes its one subview its ideal width up to `maxWidth`, as the capture screens' caption
  /// layout does: the bar gives a trailing caption less room than "Step 2 of 4" next to a long
  /// large title, so a shorter text keeps its own width and a longer one is cut at `maxWidth`.
  struct SketchCappedWidth: Layout {
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
    /// The content column of a sketch screen, as the capture screens have it.
    public func sketchContent(top: CGFloat = ChapterTheme.Metric.contentTopCompact) -> some View {
      padding(.horizontal, ChapterTheme.Metric.screenPadding)
        .padding(.top, top)
        .padding(.bottom, ChapterTheme.Metric.sectionGap)
        .chapterContentWidth()
    }

    /// The right-hand caption of the navigation bar at its own width ("Step 2 of 4", or the
    /// project title when adding a floor), cut short with "…" at 280 pt before it reaches the
    /// back button. Footnote, muted, one line; text, not a button.
    public func sketchNavigationCaption(_ text: String) -> some View {
      toolbar {
        PlainToolbarItem(placement: .topBarTrailing) {
          SketchCappedWidth(maxWidth: 280) {
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
  }

  /// A length as the operator types it: the title (body ink), the field (body ink, right
  /// aligned, the numbers-and-punctuation keyboard so feet and inch marks are at hand), the
  /// unit after it (footnote muted) and the Measured / About chip; under it, what is stored
  /// ("7,518 mm · 24' 8"") or why the value is refused. Min height 52, padding 8 × 16.
  public struct SketchLengthRow: View {
    let title: String
    @Binding var field: SketchLengthField
    /// `sketch.wall.wall-1.length`: the field; `.measured` is appended for the chip.
    let identifier: String
    var subtitle: String? = nil
    /// Draws the Measured / About chip (a tape check is always measured: no chip).
    var showsMeasuredChip = true
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(
      title: String, field: Binding<SketchLengthField>, identifier: String, subtitle: String? = nil,
      showsMeasuredChip: Bool = true
    ) {
      self.title = title
      self._field = field
      self.identifier = identifier
      self.subtitle = subtitle
      self.showsMeasuredChip = showsMeasuredChip
    }

    public var body: some View {
      VStack(alignment: .leading, spacing: 4) {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout =
          stacked
          ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
          : AnyLayout(HStackLayout(spacing: ChapterTheme.Metric.rowGap))
        layout {
          VStack(alignment: .leading, spacing: ChapterTheme.Metric.rowTitleGap) {
            Text(title)
              .chapterTextStyle(.body)
              .foregroundStyle(ChapterTheme.Color.ink)
            if let subtitle {
              Text(subtitle)
                .chapterTextStyle(.footnote)
                .foregroundStyle(ChapterTheme.Color.muted)
            }
          }
          .fixedSize(horizontal: !stacked, vertical: true)
          HStack(spacing: 6) {
            TextField(
              text: $field.text,
              prompt: Text(SketchUnits.prompt(field.unit)).foregroundStyle(ChapterTheme.Color.muted)
            ) {
              Text(title)
            }
            .font(ChapterTheme.Font.body)
            .foregroundStyle(ChapterTheme.Color.ink)
            .multilineTextAlignment(stacked ? .leading : .trailing)
            .keyboardType(.numbersAndPunctuation)
            .autocorrectionDisabled()
            .accessibilityIdentifier(identifier)
            Text(SketchUnits.suffix(field.unit))
              .chapterTextStyle(.footnote)
              .foregroundStyle(ChapterTheme.Color.muted)
              .accessibilityHidden(true)
            if showsMeasuredChip {
              measuredChip
            }
          }
        }
        if let error = field.errorMessage {
          Text(error)
            .chapterTextStyle(.footnote)
            .foregroundStyle(ChapterTheme.Color.blocked)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("\(identifier).error")
        } else if let stored = field.storedText {
          Text(field.measured ? stored : "About \(stored)")
            .chapterTextStyle(.footnote)
            .foregroundStyle(ChapterTheme.Color.muted)
            .accessibilityIdentifier("\(identifier).stored")
        }
      }
      .padding(.horizontal, ChapterTheme.Metric.rowPadding)
      .padding(.vertical, ChapterTheme.Metric.navigationRowVerticalPadding)
      .frame(maxWidth: .infinity, minHeight: ChapterTheme.Metric.navigationRowHeight, alignment: .leading)
    }

    private var measuredChip: some View {
      Button(field.measured ? "Measured" : "About") {
        field.measured.toggle()
      }
      .buttonStyle(.plain)
      .chapterTextStyle(.footnote)
      .foregroundStyle(
        field.measured ? ChapterTheme.Color.surface : ChapterTheme.Color.ink
      )
      .padding(.horizontal, 8)
      .frame(minHeight: 28)
      .background(
        field.measured ? ChapterTheme.Color.ink : ChapterTheme.Color.nude,
        in: RoundedRectangle(cornerRadius: ChapterTheme.Metric.chipRadius))
      .accessibilityLabel(Text("\(title): \(field.measured ? "measured" : "about")"))
      .accessibilityHint(Text("Switches between a measured value and an estimate"))
      .accessibilityIdentifier("\(identifier).measured")
    }
  }

  /// A row of single-choice chips ("Wall 1 … Wall 4", the room types), scrolling sideways.
  struct SketchChipRow<Value: Hashable>: View {
    struct Option: Identifiable {
      let value: Value
      let title: String
      let identifier: String
      var id: String { identifier }
    }

    let label: String
    let options: [Option]
    @Binding var selection: Value?

    var body: some View {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(options) { option in
            ChoiceChip(option.title, isSelected: selection == option.value, kind: .subject) {
              selection = option.value
            }
            .accessibilityIdentifier(option.identifier)
          }
        }
        .padding(.horizontal, ChapterTheme.Metric.rowPadding)
        .padding(.vertical, 8)
      }
      .accessibilityElement(children: .contain)
      .accessibilityLabel(Text(label))
    }
  }

  /// A row with a caption and a segmented control under it, inside a card.
  struct SketchSegmentedRow<Value: Hashable>: View {
    let label: String
    @Binding var selection: Value?
    let options: [ChapterSegmented<Value>.Option]

    var body: some View {
      VStack(alignment: .leading, spacing: 6) {
        Text(label)
          .chapterTextStyle(.footnote)
          .foregroundStyle(ChapterTheme.Color.muted)
          .accessibilityHidden(true)
        ChapterSegmented(label, selection: $selection, options: options)
          .dynamicTypeSize(...DynamicTypeSize.accessibility1)
      }
      .padding(.horizontal, ChapterTheme.Metric.rowPadding)
      .padding(.vertical, ChapterTheme.Metric.navigationRowVerticalPadding)
    }
  }
#endif

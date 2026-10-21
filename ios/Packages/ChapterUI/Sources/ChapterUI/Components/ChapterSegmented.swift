#if canImport(SwiftUI) && os(iOS)
  import SwiftUI

  /// The segmented control (phone-capture §2.4.4; phone-field's `SegmentedControl`): a nude track,
  /// 44 pt tall, padding 2, radius 9, with equal columns. A segment is a button with radius 7;
  /// unselected: clear, subhead ink; selected: surface, subheadEmphasis ink and two soft shadows.
  ///
  /// Accessibility: the group is labelled (`label`, e.g. "Mode") and each segment is a button with
  /// the selected trait when chosen. Choosing a segment plays the selection haptic. The selection
  /// may be nil: nothing is chosen until the operator taps.
  public struct ChapterSegmented<Value: Hashable>: View {
    public struct Option {
      public let value: Value
      public let title: String
      public let accessibilityIdentifier: String?
      /// What VoiceOver reads when the title is an abbreviation ("North" for "N"); the title
      /// when nil.
      public let accessibilityLabel: String?

      public init(
        _ value: Value, _ title: String, accessibilityIdentifier: String? = nil,
        accessibilityLabel: String? = nil
      ) {
        self.value = value
        self.title = title
        self.accessibilityIdentifier = accessibilityIdentifier
        self.accessibilityLabel = accessibilityLabel
      }
    }

    let label: String
    @Binding var selection: Value?
    let options: [Option]

    public init(_ label: String, selection: Binding<Value?>, options: [Option]) {
      self.label = label
      self._selection = selection
      self.options = options
    }

    public init(_ label: String, selection: Binding<Value>, options: [Option]) {
      self.label = label
      self._selection = Binding(
        get: { selection.wrappedValue },
        set: { value in if let value { selection.wrappedValue = value } })
      self.options = options
    }

    public var body: some View {
      HStack(spacing: 0) {
        ForEach(options.indices, id: \.self) { index in
          segment(options[index])
        }
      }
      // Every segment as tall as the tallest (a label may wrap at large text sizes).
      .fixedSize(horizontal: false, vertical: true)
      .padding(ChapterTheme.Metric.segmentedPadding)
      .background(
        ChapterTheme.Color.nude,
        in: RoundedRectangle(cornerRadius: ChapterTheme.Metric.segmentedRadius)
      )
      .sensoryFeedback(.selection, trigger: selection)
      .accessibilityElement(children: .contain)
      .accessibilityLabel(Text(label))
    }

    /// A segment fills the track inside its 2 pt padding: 40 pt.
    private var segmentHeight: CGFloat {
      ChapterTheme.Metric.segmentedHeight - 2 * ChapterTheme.Metric.segmentedPadding
    }

    private func segment(_ option: Option) -> some View {
      let isSelected = selection == option.value
      return Button {
        selection = option.value
      } label: {
        Text(option.title)
          .chapterTextStyle(isSelected ? .subheadEmphasis : .subhead)
          .foregroundStyle(ChapterTheme.Color.ink)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 4)
          .padding(.vertical, 2)
          .frame(maxWidth: .infinity, minHeight: segmentHeight, maxHeight: .infinity)
          .background {
            if isSelected {
              RoundedRectangle(cornerRadius: ChapterTheme.Metric.segmentRadius)
                .fill(ChapterTheme.Color.surface)
                .shadow(color: .black.opacity(0.12), radius: 4, y: 3)
                .shadow(color: .black.opacity(0.04), radius: 0.5, y: 3)
            }
          }
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(option.accessibilityLabel ?? option.title))
      .accessibilityAddTraits(isSelected ? .isSelected : [])
      .accessibilityIdentifier(ifPresent: option.accessibilityIdentifier)
    }
  }
#endif

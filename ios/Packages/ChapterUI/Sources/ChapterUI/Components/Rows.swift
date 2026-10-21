#if canImport(SwiftUI) && os(iOS)
  import SwiftUI

  private typealias Metric = ChapterTheme.Metric
  private typealias Palette = ChapterTheme.Color

  /// The status at the end of a row: a glyph and its word.
  public struct RowStatus: Hashable, Sendable {
    public let kind: StatusKind
    public let word: String

    public init(_ kind: StatusKind, _ word: String) {
      self.kind = kind
      self.word = word
    }
  }

  /// A row that opens something (phone-capture §2.4.2): title (body, ink) over an optional
  /// subtitle (footnote, muted, up to 2 lines), then an optional detail (body, muted, "Change")
  /// and an optional status, then the chevron. The whole row is the button.
  ///
  /// `.regular`: min height 52, padding 8 × 16 (lists, home rows). `.compact`: min height 48,
  /// padding 6 × 16 (the capture overview's rows). A placeholder title ("Choose a HUB project")
  /// is muted. At accessibility text sizes the row stacks: detail and status go under the
  /// subtitle, which then wraps freely.
  public struct NavigationRow: View {
    public enum Density: Sendable {
      case regular
      case compact
    }

    let title: String
    let subtitle: String?
    let detail: String?
    let status: RowStatus?
    let isPlaceholder: Bool
    let density: Density
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(
      title: String, subtitle: String? = nil, detail: String? = nil, status: RowStatus? = nil,
      isPlaceholder: Bool = false, density: Density = .regular, action: @escaping () -> Void
    ) {
      self.title = title
      self.subtitle = subtitle
      self.detail = detail
      self.status = status
      self.isPlaceholder = isPlaceholder
      self.density = density
      self.action = action
    }

    public var body: some View {
      Button(action: action) {
        HStack(spacing: Metric.rowGap) {
          if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
              RowTitles(
                title: title, subtitle: subtitle, isPlaceholder: isPlaceholder,
                subtitleLineLimit: nil)
              trailing
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          } else {
            RowTitles(title: title, subtitle: subtitle, isPlaceholder: isPlaceholder)
            trailing.fixedSize()
          }
          Chevron()
        }
        .padding(.horizontal, Metric.rowPadding)
        .padding(
          .vertical,
          density == .regular
            ? Metric.navigationRowVerticalPadding : Metric.overviewRowVerticalPadding
        )
        .frame(
          maxWidth: .infinity,
          minHeight: density == .regular ? Metric.navigationRowHeight : Metric.overviewRowHeight,
          alignment: .leading)
      }
      .buttonStyle(RowButtonStyle())
    }

    @ViewBuilder
    private var trailing: some View {
      if let detail {
        Text(detail)
          .chapterTextStyle(.body)
          .foregroundStyle(Palette.muted)
      }
      if let status {
        StatusLabel(kind: status.kind, word: status.word)
      }
    }
  }

  /// A navigation row with a 4 pt progress bar under its subtitle (the uploading capture on the
  /// home): title, subtitle and bar 6 pt apart, padding 10 × 16, min height 52.
  public struct ProgressNavigationRow: View {
    let title: String
    let subtitle: String?
    let fraction: Double
    let action: () -> Void

    public init(
      title: String, subtitle: String? = nil, fraction: Double, action: @escaping () -> Void
    ) {
      self.title = title
      self.subtitle = subtitle
      self.fraction = fraction
      self.action = action
    }

    public var body: some View {
      Button(action: action) {
        HStack(spacing: Metric.rowGap) {
          VStack(alignment: .leading, spacing: Metric.progressRowGap) {
            Text(title)
              .chapterTextStyle(.body)
              .foregroundStyle(Palette.ink)
            if let subtitle {
              Text(subtitle)
                .chapterTextStyle(.footnote)
                .foregroundStyle(Palette.muted)
                .lineLimit(2)
            }
            ProgressBar(fraction: fraction)
          }
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, alignment: .leading)
          Chevron()
        }
        .padding(.horizontal, Metric.rowPadding)
        .padding(.vertical, Metric.progressRowVerticalPadding)
        .frame(maxWidth: .infinity, minHeight: Metric.navigationRowHeight, alignment: .leading)
      }
      .buttonStyle(RowButtonStyle())
    }
  }

  /// A label and its value, not tappable ("Operator · Dana Ruiz"): label body ink, value body
  /// muted at the trailing edge, wrapping rather than truncating; min height 48, padding 0 × 16.
  public struct ValueRow: View {
    let label: String
    let value: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(label: String, value: String) {
      self.label = label
      self.value = value
    }

    public var body: some View {
      // At accessibility text sizes the value goes under the label.
      let layout =
        dynamicTypeSize.isAccessibilitySize
        ? AnyLayout(VStackLayout(alignment: .leading, spacing: Metric.rowTitleGap))
        : AnyLayout(HStackLayout(spacing: Metric.rowGap))
      layout {
        Text(label)
          .chapterTextStyle(.body)
          .foregroundStyle(Palette.ink)
          .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
        Text(value)
          .chapterTextStyle(.body)
          .foregroundStyle(Palette.muted)
          .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
          .frame(
            maxWidth: .infinity,
            alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
      }
      .padding(.horizontal, Metric.rowPadding)
      .padding(.vertical, 4)
      .frame(maxWidth: .infinity, minHeight: Metric.valueRowHeight)
      .accessibilityElement(children: .combine)
    }
  }

  /// One line of prominent text (the HUB address): bodyEmphasis ink, min height 52, padding
  /// 10 × 16. As a placeholder ("Choose a HUB project first", "No captures on this phone yet.")
  /// it is body muted.
  public struct ProminentTextRow: View {
    let text: String
    let isPlaceholder: Bool

    public init(_ text: String, isPlaceholder: Bool = false) {
      self.text = text
      self.isPlaceholder = isPlaceholder
    }

    public var body: some View {
      Text(text)
        .chapterTextStyle(isPlaceholder ? .body : .bodyEmphasis)
        .foregroundStyle(isPlaceholder ? Palette.muted : Palette.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Metric.rowPadding)
        .padding(.vertical, Metric.progressRowVerticalPadding)
        .frame(minHeight: Metric.navigationRowHeight)
    }
  }

  /// A label and a system switch tinted ink (the tokens' "Toggle: system, tint ink"; the system off
  /// track is kept). Min height 52, padding 8 × 16.
  public struct ToggleRow: View {
    let label: String
    @Binding var isOn: Bool

    public init(_ label: String, isOn: Binding<Bool>) {
      self.label = label
      self._isOn = isOn
    }

    public var body: some View {
      Toggle(isOn: $isOn) {
        Text(label)
          .chapterTextStyle(.body)
          .foregroundStyle(Palette.ink)
      }
      .tint(Palette.ink)
      .padding(.horizontal, Metric.rowPadding)
      .padding(.vertical, Metric.navigationRowVerticalPadding)
      .frame(minHeight: Metric.navigationRowHeight)
    }
  }

  /// A label and a text field (step 2's "Name"): label body ink at its own width, then the field,
  /// body ink, right-aligned, with its prompt in muted. Min height 52, padding 0 × 16. The field's
  /// accessibility label is `accessibilityLabel` ("Floor or area"), else the label.
  public struct TextFieldRow: View {
    let label: String
    @Binding var text: String
    let prompt: String?
    let accessibilityLabel: String?

    public init(
      label: String, text: Binding<String>, prompt: String? = nil,
      accessibilityLabel: String? = nil
    ) {
      self.label = label
      self._text = text
      self.prompt = prompt
      self.accessibilityLabel = accessibilityLabel
    }

    public var body: some View {
      HStack(spacing: Metric.rowGap) {
        Text(label)
          .chapterTextStyle(.body)
          .foregroundStyle(Palette.ink)
          .fixedSize()
          .accessibilityHidden(true)
        TextField(
          text: $text,
          prompt: prompt.map { Text($0).foregroundStyle(Palette.muted) }
        ) {
          Text(accessibilityLabel ?? label)
        }
        .font(ChapterTheme.Font.body)
        .foregroundStyle(Palette.ink)
        .multilineTextAlignment(.trailing)
      }
      .padding(.horizontal, Metric.rowPadding)
      .frame(minHeight: Metric.navigationRowHeight)
    }
  }

  /// "Add a room you cannot scan": the 22 pt plus circle and the title, body ink. Min height 48,
  /// padding 0 × 16, gap 12. The row is the button.
  public struct AddRow: View {
    let title: String
    let action: () -> Void

    public init(title: String, action: @escaping () -> Void) {
      self.title = title
      self.action = action
    }

    public var body: some View {
      Button(action: action) {
        HStack(spacing: Metric.rowGap) {
          PlusGlyph(accessibilityLabel: nil)
          Text(title)
            .chapterTextStyle(.body)
            .foregroundStyle(Palette.ink)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Metric.rowPadding)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: Metric.valueRowHeight, alignment: .leading)
      }
      .buttonStyle(RowButtonStyle())
    }
  }

  /// A removable entry ("Primary closet · Locked"): the 22 pt minus circle is a button with a 44 pt
  /// hit area and the label "Remove [title]", then title (body) over an optional subtitle
  /// (footnote, muted). Min height 52, padding 8 × 16, gap 12.
  public struct RemovableRow: View {
    let title: String
    let subtitle: String?
    let removeAccessibilityIdentifier: String?
    let onRemove: () -> Void

    public init(
      title: String, subtitle: String? = nil, removeAccessibilityIdentifier: String? = nil,
      onRemove: @escaping () -> Void
    ) {
      self.title = title
      self.subtitle = subtitle
      self.removeAccessibilityIdentifier = removeAccessibilityIdentifier
      self.onRemove = onRemove
    }

    public var body: some View {
      HStack(spacing: Metric.rowGap) {
        Button(action: onRemove) {
          MinusGlyph(accessibilityLabel: nil)
            // A 44 pt hit area around the 22 pt circle, without growing the row.
            .padding(11)
            .contentShape(Rectangle())
            .padding(-11)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Remove \(title)"))
        .accessibilityIdentifier(ifPresent: removeAccessibilityIdentifier)
        RowTitles(title: title, subtitle: subtitle, isPlaceholder: false)
      }
      .padding(.horizontal, Metric.rowPadding)
      .padding(.vertical, Metric.navigationRowVerticalPadding)
      .frame(maxWidth: .infinity, minHeight: Metric.navigationRowHeight, alignment: .leading)
    }
  }

  /// Free text ("Coverage notes"): a text editor in body 17/22 with the prompt in muted while
  /// empty; min height 72, padding 14 × 16, no background of its own.
  public struct TextAreaRow: View {
    @Binding var text: String
    let prompt: String?
    let accessibilityLabel: String

    public init(text: Binding<String>, prompt: String? = nil, accessibilityLabel: String) {
      self._text = text
      self.prompt = prompt
      self.accessibilityLabel = accessibilityLabel
    }

    public var body: some View {
      TextEditor(text: $text)
        .chapterTextStyle(.body)
        .foregroundStyle(Palette.ink)
        .scrollContentBackground(.hidden)
        // At least 72 pt, then as tall as its text; never stretched to fill the screen.
        .frame(minHeight: Metric.textAreaHeight)
        .fixedSize(horizontal: false, vertical: true)
        .overlay(alignment: .topLeading) {
          if text.isEmpty, let prompt {
            // The text view's own inset: 8 pt above the first line, 5 pt before it.
            Text(prompt)
              .chapterTextStyle(.body)
              .foregroundStyle(Palette.muted)
              .padding(.top, 8)
              .padding(.leading, 5)
              .allowsHitTesting(false)
              .accessibilityHidden(true)
          }
        }
        .padding(.horizontal, Metric.rowPadding - 5)
        .padding(.vertical, Metric.textAreaVerticalPadding - 8)
        .accessibilityLabel(Text(accessibilityLabel))
    }
  }

  /// Title over an optional subtitle, 2 pt apart, filling the row's free width.
  struct RowTitles: View {
    let title: String
    let subtitle: String?
    let isPlaceholder: Bool
    var subtitleLineLimit: Int? = 2

    var body: some View {
      VStack(alignment: .leading, spacing: Metric.rowTitleGap) {
        Text(title)
          .chapterTextStyle(.body)
          .foregroundStyle(isPlaceholder ? Palette.muted : Palette.ink)
        if let subtitle {
          Text(subtitle)
            .chapterTextStyle(.footnote)
            .foregroundStyle(Palette.muted)
            .lineLimit(subtitleLineLimit)
        }
      }
      .multilineTextAlignment(.leading)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  /// Rows highlight in nude while pressed and dim to 0.4 when disabled.
  struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
      RowButtonBody(label: configuration.label, isPressed: configuration.isPressed)
    }
  }

  private struct RowButtonBody<Label: View>: View {
    let label: Label
    let isPressed: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
      label
        .contentShape(Rectangle())
        .background(isPressed ? Palette.nude : Color.clear)
        .opacity(isEnabled ? 1 : 0.4)
    }
  }
#endif

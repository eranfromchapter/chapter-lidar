#if canImport(SwiftUI) && canImport(UIKit)
  import CaptureContract
  import ChapterUI
  import FieldRules
  import SwiftUI

  /// "Field controls" (design v2, artboard 2d-2; phone-field §4): the minimum set of every floor
  /// as one guided list, with what lies between two floors after each floor that has a next one.
  /// A row opens the entry sheet (`ControlEntrySheet`). Under the manual policy the bar shows
  /// `4 of 9 required`; under the standard policy (shipping) the scan's values fill the rows and
  /// nothing is missing.
  ///
  /// Pushed by the app (system back, large title). `model.focus(rowId:)` scrolls to a row and
  /// opens its sheet (Before you leave "Add").
  public struct FieldControlsView: View {
    @Bindable var model: FieldControlsModel

    public init(model: FieldControlsModel) {
      self.model = model
    }

    public var body: some View {
      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            Text(model.subtitle)
              .chapterTextStyle(.footnote)
              .foregroundStyle(FieldTheme.Color.muted)
              .frame(maxWidth: .infinity, alignment: .leading)
              .fixedSize(horizontal: false, vertical: true)
              .padding(.top, FieldTheme.Metric.subtitleTop)
              .accessibilityIdentifier("controls.subtitle")
            content
              .padding(.top, 10)
          }
          .padding(.horizontal, FieldTheme.Metric.screenPadding)
          .padding(.bottom, FieldTheme.Metric.screenPadding)
          .chapterContentWidth()
        }
        .onAppear { scroll(proxy) }
        .onChange(of: model.scrollTarget) { _, _ in scroll(proxy) }
      }
      .navigationTitle("Field controls")
      .navigationBarTitleDisplayMode(.large)
      .toolbar {
        if let progress = model.progress {
          PlainToolbarItem(placement: .topBarTrailing) {
            Text(progress.text)
              .chapterTextStyle(.footnote)
              .foregroundStyle(FieldTheme.Color.muted)
              .lineLimit(1)
              .accessibilityIdentifier("controls.progress")
          }
        }
      }
      .chapterBackChevronOnly()
      .chapterScreenBackground()
      .sheet(item: $model.entry) { entry in
        ControlEntrySheet(
          entry: entry, onCancel: { model.cancelEntry() }, onSave: { model.saveEntry() },
          onEditRecorded: { model.edit(recordedId: $0) })
      }
    }

    @ViewBuilder
    private var content: some View {
      if let message = model.emptyMessage {
        Text(message)
          .chapterTextStyle(.subhead)
          .foregroundStyle(FieldTheme.Color.muted)
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityIdentifier("controls.empty")
      } else {
        let sections = model.sections
        VStack(alignment: .leading, spacing: FieldMetric.controlSectionGap) {
          ForEach(sections) { section in
            ChapterSection(
              header: section.header,
              footer: section.id == sections.last?.id ? model.footnote : nil,
              headerStyle: .compact
            ) {
              ForEach(section.rows) { row in
                ControlRowView(row: row) { model.open(row) }
                  .id(row.id)
              }
            }
          }
        }
      }
    }

    private func scroll(_ proxy: ScrollViewProxy) {
      guard let target = model.scrollTarget else { return }
      DispatchQueue.main.async {
        withAnimation { proxy.scrollTo(target, anchor: .center) }
        model.scrollTarget = nil
      }
    }
  }

  /// One row of the list (phone-field §4.2): the status glyph, title over subtitle, the values
  /// (millimetres over feet and inches in SF Mono, and the scan's value), the chevron. Two-line
  /// rows are at least 50 pt, one-line rows 42. At accessibility text sizes the values go under
  /// the titles, so nothing is cut. The row is one accessibility element.
  struct ControlRowView: View {
    let row: ControlRow
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The glyph grows with the text (10 pt at the default size).
    @ScaledMetric(relativeTo: .body) private var glyphSize = FieldTheme.Metric.statusGlyph

    var body: some View {
      Button(action: action) {
        HStack(spacing: FieldTheme.Metric.rowGap) {
          StatusGlyph(row.status.glyph, size: glyphSize)
          if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
              titles
              values(alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          } else {
            titles
            values(alignment: .trailing).fixedSize()
          }
          Chevron()
        }
        .padding(.horizontal, FieldTheme.Metric.rowPadding)
        .padding(.vertical, row.isCompact ? 4 : FieldMetric.controlRowVerticalPadding)
        .frame(
          maxWidth: .infinity,
          minHeight: row.isCompact ? FieldMetric.controlRowCompactHeight : FieldMetric.controlRowHeight,
          alignment: .leading)
      }
      .buttonStyle(FieldRowButtonStyle())
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(row.accessibilityLabel)
      .accessibilityAddTraits(.isButton)
      .accessibilityIdentifier(row.accessibilityIdentifier)
    }

    private var titles: some View {
      VStack(alignment: .leading, spacing: FieldTheme.Metric.rowTitleGap) {
        Text(row.title)
          .chapterTextStyle(.body)
          .foregroundStyle(FieldTheme.Color.ink)
        if let subtitle = row.subtitle {
          Text(subtitle)
            .chapterTextStyle(.footnote)
            .foregroundStyle(FieldTheme.Color.muted)
        }
      }
      .multilineTextAlignment(.leading)
      .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func values(alignment: HorizontalAlignment) -> some View {
      VStack(alignment: alignment, spacing: FieldTheme.Metric.rowTitleGap) {
        if let value = row.valuePrimary {
          Text(value)
            .chapterTextStyle(.subhead)
            .foregroundStyle(row.valueTone.color)
        }
        if let secondary = row.valueSecondary {
          Text(secondary)
            .chapterTextStyle(.mono13)
            .foregroundStyle(FieldTheme.Color.muted)
        }
        if let extra = row.extraLine {
          Text(extra)
            .chapterTextStyle(.footnote)
            .foregroundStyle(FieldTheme.Color.muted)
        }
      }
      .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
    }
  }

  extension ControlStatus {
    /// ● done, ■ missing, ○ optional.
    var glyph: StatusKind {
      switch self {
      case .done: .done
      case .missing: .missing
      case .optional: .waiting
      }
    }
  }

  extension ControlValueTone {
    var color: Color {
      switch self {
      case .ink: FieldTheme.Color.ink
      case .blocked: FieldTheme.Color.blocked
      case .muted: FieldTheme.Color.muted
      }
    }
  }
#endif

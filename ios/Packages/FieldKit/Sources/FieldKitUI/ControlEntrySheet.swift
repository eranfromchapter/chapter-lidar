#if canImport(SwiftUI) && canImport(UIKit)
  import CaptureContract
  import ChapterUI
  import FieldRules
  import SwiftUI

  /// The entry sheet of a Field controls row (design v2, artboard 2d-3; phone-field §5): the
  /// words of the kind (where, which room, what), then the measurement as the instrument shows
  /// it: unit (mm, m, ft-in; feet and inches as two fields), the value, and tape or laser. The
  /// footnote says what is stored (`Stored as 3,061 mm.`) or what is wrong. List rows (ceiling
  /// heights, openings, landmarks) show what is recorded first; tapping one edits it.
  struct ControlEntrySheet: View {
    @Bindable var entry: ControlEntryModel
    let onCancel: () -> Void
    let onSave: () -> Void
    let onEditRecorded: (String) -> Void
    @FocusState private var focus: FocusField?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    enum FocusField: Hashable {
      case word(ControlEntryModel.Field)
      case feet
      case inches
      case value
      case heightFeet
      case heightInches
      case heightValue
    }

    var body: some View {
      VStack(spacing: 0) {
        SheetBar(
          title: entry.title, cancelTitle: entry.isReadOnly ? "Close" : "Cancel", onCancel: onCancel,
          actionTitle: entry.isReadOnly ? nil : "Save",
          isActionEnabled: entry.canSave, onAction: onSave,
          cancelAccessibilityIdentifier: "entry.cancel", actionAccessibilityIdentifier: "entry.save")
        ScrollView {
          VStack(alignment: .leading, spacing: FieldMetric.sheetSectionGap) {
            recordedSection
            wordSections
            if entry.hasMeasurement {
              measurementSection
            }
          }
          .disabled(entry.isReadOnly)
          .padding(.horizontal, FieldTheme.Metric.screenPadding)
          .padding(.top, 8)
          .padding(.bottom, FieldTheme.Metric.screenPadding)
        }
        .scrollDismissesKeyboard(.interactively)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .foregroundStyle(FieldTheme.Color.ink)
      .background(FieldTheme.Color.ground.ignoresSafeArea())
      .presentationDetents([.large])
      .chapterSheet()
      .onAppear {
        guard let first = initialFocus else { return }
        DispatchQueue.main.async { focus = first }
      }
      .onChange(of: entry.editingId) { _, _ in
        if entry.hasMeasurement { focus = firstValueField }
      }
      .accessibilityIdentifier("entry.sheet")
    }

    private var initialFocus: FocusField? {
      switch entry.initialFocus {
      case .firstValue: return firstValueField
      case .some(let field): return .word(field)
      case nil: return nil
      }
    }

    private var firstValueField: FocusField { entry.value.unit == .ftIn ? .feet : .value }

    // MARK: Recorded

    @ViewBuilder
    private var recordedSection: some View {
      if let caption = entry.recordedCaption {
        section(caption) {
          ChapterCard {
            ForEach(entry.recorded) { item in
              Button { onEditRecorded(item.id) } label: {
                HStack(spacing: FieldTheme.Metric.rowGap) {
                  VStack(alignment: .leading, spacing: FieldTheme.Metric.rowTitleGap) {
                    Text(item.title).chapterTextStyle(.body)
                    if let subtitle = item.subtitle, !subtitle.isEmpty {
                      Text(subtitle)
                        .chapterTextStyle(.footnote)
                        .foregroundStyle(FieldTheme.Color.muted)
                    }
                  }
                  .frame(maxWidth: .infinity, alignment: .leading)
                  VStack(alignment: .trailing, spacing: FieldTheme.Metric.rowTitleGap) {
                    if let value = item.valuePrimary {
                      Text(value).chapterTextStyle(.subhead)
                    }
                    if let secondary = item.valueSecondary {
                      Text(secondary)
                        .chapterTextStyle(.mono13)
                        .foregroundStyle(FieldTheme.Color.muted)
                    }
                  }
                  .fixedSize()
                  Chevron()
                }
                .foregroundStyle(FieldTheme.Color.ink)
                // As a two-line row of the list: 50 pt of content, padding 5.
                .frame(maxWidth: .infinity, minHeight: FieldMetric.controlRowHeight)
                .padding(.horizontal, FieldTheme.Metric.rowPadding)
                .padding(.vertical, FieldMetric.controlRowVerticalPadding)
              }
              .buttonStyle(FieldRowButtonStyle())
              .accessibilityElement(children: .combine)
              .accessibilityAddTraits(item.id == entry.editingId ? .isSelected : [])
              .accessibilityIdentifier("entry.recorded.\(item.id)")
            }
          }
        }
      }
    }

    // MARK: Words

    @ViewBuilder
    private var wordSections: some View {
      switch entry.kind {
      case .distanceA, .distanceB:
        section("Where") {
          ChapterCard {
            wordRow(label: "From", text: $entry.from, prompt: "Kitchen east wall", field: .from)
            wordRow(label: "To", text: $entry.to, prompt: "Living west wall", field: .to)
          }
        }
      case .ceilingHeight:
        section("Room") {
          roomPicker
          ChapterCard {
            wordRow(
              label: "Where in the room", text: $entry.location, prompt: "Optional",
              field: .location)
          }
          .padding(.top, 2)
        }
      case .opening:
        section("Room") { roomPicker }
        section("Which opening") {
          ChapterCard {
            plainField(
              text: $entry.label, prompt: "Entry door", accessibilityLabel: "Which opening",
              field: .label)
          }
        }
      case .floorToFloor:
        section("Where") {
          ChapterCard {
            plainField(
              text: $entry.location, prompt: "At the stair", accessibilityLabel: "Where measured",
              field: .location)
          }
        }
      case .landmark:
        section("What it is") {
          ChapterCard {
            plainField(
              text: $entry.label, prompt: "Stair newel post", accessibilityLabel: "What it is",
              field: .label)
          }
        }
        section("Visible from") {
          FlowLayout {
            ForEach(entry.floors) { floor in
              ChoiceChip(floor.label, isSelected: entry.landmarkFloors.contains(floor.id)) {
                entry.toggleLandmarkFloor(floor.id)
              }
              .accessibilityIdentifier("entry.floor.\(floor.ref.areaKey)")
            }
          }
          .padding(.horizontal, 0)
          footnote
        }
      }
    }

    /// The floor's rooms as one row of chips (single select), or a text field when the capture
    /// has none.
    @ViewBuilder
    private var roomPicker: some View {
      if entry.rooms.isEmpty {
        ChapterCard {
          plainField(text: $entry.room, prompt: "Room", accessibilityLabel: "Room", field: .room)
        }
      } else {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: FieldMetric.chipGap) {
            ForEach(entry.rooms, id: \.self) { room in
              ChoiceChip(room, isSelected: PhotoCoverage.key(entry.room) == PhotoCoverage.key(room)) {
                entry.room = room
                if entry.kind == .ceilingHeight { focus = firstValueField }
              }
              .accessibilityIdentifier("entry.room.\(room)")
            }
          }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Room")
      }
    }

    /// A label and a right-aligned field in a 52 pt card row ("From · Kitchen east wall"). The
    /// words wrap onto more lines rather than being cut; at accessibility text sizes the field
    /// goes under its label.
    private func wordRow(
      label: String, text: Binding<String>, prompt: String, field: ControlEntryModel.Field
    ) -> some View {
      let stacked = dynamicTypeSize.isAccessibilitySize
      let layout =
        stacked
        ? AnyLayout(VStackLayout(alignment: .leading, spacing: FieldTheme.Metric.rowTitleGap))
        : AnyLayout(HStackLayout(spacing: FieldTheme.Metric.rowGap))
      return layout {
        Text(label)
          .chapterTextStyle(.body)
          .foregroundStyle(FieldTheme.Color.ink)
          .fixedSize(horizontal: !stacked, vertical: true)
          .accessibilityHidden(true)
        TextField(
          text: oneLine(text, field: field),
          prompt: Text(prompt).foregroundStyle(FieldTheme.Color.muted), axis: .vertical
        ) {
          Text(label)
        }
        .font(FieldTheme.Font.body)
        .foregroundStyle(FieldTheme.Color.ink)
        .multilineTextAlignment(stacked ? .leading : .trailing)
        .textInputAutocapitalization(.words)
        .submitLabel(.next)
        .focused($focus, equals: .word(field))
        .accessibilityIdentifier("entry.\(field)")
      }
      .padding(.horizontal, FieldTheme.Metric.rowPadding)
      .padding(.vertical, FieldMetric.wordFieldVerticalPadding)
      .frame(minHeight: FieldTheme.Metric.navigationRowHeight)
    }

    /// A field filling a 52 pt card row; the words wrap onto more lines rather than being cut.
    private func plainField(
      text: Binding<String>, prompt: String, accessibilityLabel: String,
      field: ControlEntryModel.Field
    ) -> some View {
      TextField(
        text: oneLine(text, field: field),
        prompt: Text(prompt).foregroundStyle(FieldTheme.Color.muted), axis: .vertical
      ) {
        Text(accessibilityLabel)
      }
      .font(FieldTheme.Font.body)
      .foregroundStyle(FieldTheme.Color.ink)
      .textInputAutocapitalization(.words)
      .submitLabel(.next)
      .focused($focus, equals: .word(field))
      .accessibilityIdentifier("entry.\(field)")
      .padding(.horizontal, FieldTheme.Metric.rowPadding)
      .padding(.vertical, FieldMetric.wordFieldVerticalPadding)
      .frame(minHeight: FieldTheme.Metric.navigationRowHeight)
    }

    /// The text of a wrapping word field. Return types a line break in a field that wraps; here
    /// it is "Next" instead: the line break is dropped (the words are one line in
    /// field-controls.json) and the focus moves on (`ControlEntryModel.focus(after:)`).
    private func oneLine(
      _ text: Binding<String>, field: ControlEntryModel.Field
    ) -> Binding<String> {
      Binding(
        get: { text.wrappedValue },
        set: { newValue in
          guard newValue.contains(where: \.isNewline) else {
            text.wrappedValue = newValue
            return
          }
          text.wrappedValue = ControlEntryModel.oneLine(newValue)
          switch entry.focus(after: field) {
          case .firstValue: focus = firstValueField
          case .some(let next): focus = .word(next)
          case nil: focus = nil
          }
        })
    }

    // MARK: Measurement

    private var measurementSection: some View {
      VStack(alignment: .leading, spacing: FieldMetric.sheetSectionGap) {
        section(entry.measurementCaption) {
          ChapterCard {
            ChapterSegmented(
              "Units",
              selection: Binding(get: { entry.value.unit }, set: { entry.chooseUnit($0) }),
              options: UnitChoice.offered.map {
                .init(
                  $0, UnitChoice.title($0), accessibilityIdentifier: "entry.unit.\(unitKey($0))",
                  accessibilityLabel: UnitChoice.spokenTitle($0))
              }
            )
            .padding(.vertical, 8)
            .padding(.horizontal, FieldTheme.Metric.rowPadding)
            valueFields(
              $entry.value, fields: (.feet, .inches, .value),
              identifiers: ("entry.feet", "entry.inches", "entry.value"))
            ChapterSegmented(
              "Method",
              selection: Binding(get: { entry.value.method }, set: { entry.chooseMethod($0) }),
              options: [
                .init(MeasurementMethod.tape, "Tape", accessibilityIdentifier: "entry.method.tape"),
                .init(.laser, "Laser", accessibilityIdentifier: "entry.method.laser"),
              ]
            )
            .padding(.vertical, 8)
            .padding(.horizontal, FieldTheme.Metric.rowPadding)
          }
          if entry.kind != .opening { footnote }
        }
        if entry.kind == .opening {
          section("Height \u{00B7} optional") {
            ChapterCard {
              valueFields(
                $entry.height, fields: (.heightFeet, .heightInches, .heightValue),
                identifiers: ("entry.height.feet", "entry.height.inches", "entry.height.value"))
            }
            footnote
          }
        }
      }
    }

    private func unitKey(_ unit: EnteredUnit) -> String {
      unit == .ftIn ? "ftIn" : UnitChoice.title(unit)
    }

    /// Feet and inches side by side, or one millimetre or metre field.
    private func valueFields(
      _ draft: Binding<MeasurementEntryDraft>,
      fields: (feet: FocusField, inches: FocusField, value: FocusField),
      identifiers: (feet: String, inches: String, value: String)
    ) -> some View {
      let unit = draft.wrappedValue.unit
      let errorField = Self.errorField(draft.wrappedValue)
      return HStack(spacing: FieldMetric.valueFieldGap) {
        if unit == .ftIn {
          EntryValueField(
            text: draft.feet, suffix: "ft", accessibilityLabel: "Feet",
            identifier: identifiers.feet, focus: $focus, field: fields.feet,
            isError: errorField == .feet)
          EntryValueField(
            text: draft.inches, suffix: "in", accessibilityLabel: "Inches",
            identifier: identifiers.inches, focus: $focus, field: fields.inches,
            isError: errorField == .inches)
        } else {
          EntryValueField(
            text: draft.value, suffix: UnitChoice.title(unit),
            accessibilityLabel: unit == .mm ? "Millimetres" : "Metres",
            identifier: identifiers.value, focus: $focus, field: fields.value,
            isError: errorField == .value)
        }
      }
      .padding(.horizontal, FieldTheme.Metric.rowPadding)
      .padding(.vertical, 12)
    }

    /// Which value field the error is about: whole feet → feet; anything else in feet and
    /// inches → the inches (or the feet when no inches are typed); mm and m → the one field.
    private static func errorField(_ draft: MeasurementEntryDraft) -> FocusField? {
      guard let message = draft.errorMessage else { return nil }
      guard draft.unit == .ftIn else { return .value }
      if message == "Enter whole feet. Put the rest in inches." { return .feet }
      return draft.inches.trimmingCharacters(in: .whitespaces).isEmpty ? .feet : .inches
    }

    @ViewBuilder
    private var footnote: some View {
      let note = entry.footnote
      Text(note.text)
        .chapterTextStyle(.footnote)
        .foregroundStyle(note.isError ? FieldTheme.Color.blocked : FieldTheme.Color.muted)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, FieldTheme.Metric.sectionInset)
        .accessibilityIdentifier("entry.footnote")
    }

    /// A caption (13, uppercase) and its content, 6 pt apart.
    private func section<Content: View>(_ caption: String, @ViewBuilder content: () -> Content)
      -> some View
    {
      VStack(alignment: .leading, spacing: FieldTheme.Metric.sectionHeaderGap) {
        SectionCaption(caption)
        content()
      }
    }
  }

  /// A value field of the entry sheet: 56 pt, radius 12, ground fill, the number in Inter 26 and
  /// the unit after it in subhead muted. Border 1 line; 1.5 ink while focused, 1.5 blocked in
  /// error. The decimal pad (a comma is read as a decimal point).
  struct EntryValueField: View {
    @Binding var text: String
    let suffix: String
    let accessibilityLabel: String
    let identifier: String
    var focus: FocusState<ControlEntrySheet.FocusField?>.Binding
    let field: ControlEntrySheet.FocusField
    let isError: Bool

    var body: some View {
      let isFocused = focus.wrappedValue == field
      HStack(spacing: 8) {
        TextField("", text: $text)
          .font(FieldTheme.Font.entryValue)
          .foregroundStyle(FieldTheme.Color.ink)
          .keyboardType(.decimalPad)
          .focused(focus, equals: field)
          .accessibilityLabel(accessibilityLabel)
          .accessibilityIdentifier(identifier)
        Text(suffix)
          .chapterTextStyle(.subhead)
          .foregroundStyle(FieldTheme.Color.muted)
          .accessibilityHidden(true)
      }
      .padding(.horizontal, FieldMetric.valueFieldPadding)
      .frame(maxWidth: .infinity, minHeight: FieldMetric.valueFieldHeight)
      .background(
        FieldTheme.Color.ground,
        in: RoundedRectangle(cornerRadius: FieldTheme.Metric.cardRadius)
      )
      .overlay(
        RoundedRectangle(cornerRadius: FieldTheme.Metric.cardRadius)
          .strokeBorder(
            isError
              ? FieldTheme.Color.blocked : isFocused ? FieldTheme.Color.ink : FieldTheme.Color.line,
            lineWidth: isError || isFocused ? 1.5 : 1)
      )
      .contentShape(Rectangle())
      .onTapGesture { focus.wrappedValue = field }
    }
  }
#endif

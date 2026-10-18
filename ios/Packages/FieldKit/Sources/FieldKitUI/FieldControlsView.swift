#if canImport(SwiftUI) && canImport(UIKit)
  import CaptureContract
  import FieldRules
  import SwiftUI

  /// Field controls (design screen-field, 2): the list of required controls with their values
  /// (or "■ Missing"), the "New measurement" card with a unit menu, and "Save measurement".
  public struct FieldControlsView: View {
    @Bindable var model: FieldControlsModel

    public init(model: FieldControlsModel) {
      self.model = model
    }

    public var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          Text("Field controls")
            .font(FieldTheme.title30())
          Text(
            model.measurementsFromScan
              ? "Measured by the LiDAR scan. Tap a row to add an optional tape or laser check."
              : "Tape or laser only. Never copy numbers from the scan.")
            .font(.system(size: 15))
            .foregroundStyle(FieldTheme.muted)

          if model.floors.count > 1 { floorPicker }

          if model.floors.isEmpty {
            Text("No floor has been captured yet.")
              .font(.system(size: 15))
              .foregroundStyle(FieldTheme.muted)
          } else {
            list
          }

          if let kind = model.activeKind { entryCard(kind) }
        }
      }
      .safeAreaInset(edge: .bottom) {
        // Shown only while a measurement is being entered: with the scan's values, entering
        // one is optional and "Continue" (top right) moves on.
        if model.activeKind != nil {
          PrimaryButton(title: "Save measurement", isEnabled: model.canSave) {
            model.saveEntry()
          }
          .padding(.top, FieldTheme.space8)
        }
      }
      .fieldScreen()
    }

    private var floorPicker: some View {
      FlowLayout {
        ForEach(Array(model.floors.enumerated()), id: \.element.id) { index, floor in
          ChoiceChip(title: floor.label, isSelected: model.selectedFloorIndex == index) {
            model.selectedFloorIndex = index
            model.cancelEntry()
          }
        }
      }
    }

    private var list: some View {
      let rows = model.rows
      return VStack(spacing: 0) {
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
          Button {
            model.beginEntry(row.kind)
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(FieldTheme.rowTitle)
                Text(row.subtitle).font(FieldTheme.caption).foregroundStyle(FieldTheme.muted)
              }
              Spacer(minLength: FieldTheme.space8)
              valueView(row)
            }
            .padding(.horizontal, FieldTheme.space16)
            .padding(.vertical, 14)
            .frame(minHeight: FieldTheme.chipHeight)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          if index < rows.count - 1 {
            Rectangle().fill(FieldTheme.nude).frame(height: 1)
          }
        }
      }
      .background(FieldTheme.surface)
      .clipShape(RoundedRectangle(cornerRadius: FieldTheme.cardRadius))
      .overlay(
        RoundedRectangle(cornerRadius: FieldTheme.cardRadius)
          .stroke(FieldTheme.line, lineWidth: 1))
    }

    @ViewBuilder
    private func valueView(_ row: ControlRowContent) -> some View {
      if row.isMissing {
        Text("\u{25A0} Missing")
          .font(.system(size: 15))
          .foregroundStyle(FieldTheme.blocked)
      } else if row.valueLines.isEmpty {
        Text("Optional")
          .font(.system(size: 15))
          .foregroundStyle(FieldTheme.muted)
      } else {
        VStack(alignment: .trailing, spacing: 0) {
          ForEach(Array(row.valueLines.enumerated()), id: \.offset) { index, line in
            Text(line)
              .font(.system(size: 15))
              .foregroundStyle(index == 0 ? FieldTheme.ink : FieldTheme.muted)
          }
        }
        .multilineTextAlignment(.trailing)
      }
    }

    // MARK: New measurement card

    private func entryCard(_ kind: ControlKind) -> some View {
      VStack(alignment: .leading, spacing: FieldTheme.space8) {
        FieldCaption(text: "New measurement \u{00B7} \(kind.entryTitle)")

        switch kind {
        case .distanceA, .distanceB:
          wordField("From (for example Kitchen east wall)", text: $model.fromText)
          wordField("To (for example Living west wall)", text: $model.toText)
        case .ceilingHeight:
          wordField("Room", text: $model.roomText)
          wordField("Where in the room (optional)", text: $model.locationText)
        case .opening:
          wordField("Room", text: $model.roomText)
          wordField("Which opening (for example Entry door)", text: $model.labelText)
        case .floorToFloor:
          wordField("Where measured (for example At stair)", text: $model.locationText)
          if model.floors.count > 2 { upperFloorPicker }
        case .landmark:
          wordField("What it is (for example Stair newel post)", text: $model.labelText)
          FieldCaption(text: "Visible from")
          FlowLayout {
            ForEach(model.floors) { floor in
              ChoiceChip(
                title: floor.label, isSelected: model.landmarkFloorIDs.contains(floor.ref.captureId)
              ) {
                model.toggleLandmarkFloor(floor.ref.captureId)
              }
            }
          }
        }

        if kind != .landmark {
          valueRow(label: kind == .opening ? "Width" : "Value", text: $model.entry.text)
          if kind == .opening {
            TextField("Height (optional)", text: $model.heightText)
              .keyboardType(.numbersAndPunctuation)
              .fieldBox(fontSize: 20)
          }
          methodRow
          Text(hint)
            .font(FieldTheme.caption)
            .foregroundStyle(
              model.entry.errorMessage == nil ? FieldTheme.muted : FieldTheme.blocked)
        }

        if let message = model.errorMessage {
          Text(message).font(FieldTheme.caption).foregroundStyle(FieldTheme.blocked)
        }
      }
      .padding(FieldTheme.space16)
      .overlay(
        RoundedRectangle(cornerRadius: FieldTheme.cardRadius)
          .stroke(FieldTheme.ink, lineWidth: 1))
    }

    private var hint: String {
      if let message = model.entry.errorMessage { return message }
      if let both = model.entry.bothUnits { return "Stored in mm. \(both)" }
      return "Stored in mm. Shown in both units."
    }

    private func wordField(_ placeholder: String, text: Binding<String>) -> some View {
      TextField(placeholder, text: text)
        .fieldBox(fontSize: 15)
    }

    private func valueRow(label: String, text: Binding<String>) -> some View {
      HStack(spacing: FieldTheme.space8) {
        TextField(label, text: text)
          .keyboardType(.numbersAndPunctuation)
          .fieldBox(fontSize: 20)
        Menu {
          ForEach(UnitChoice.offered, id: \.self) { unit in
            Button(UnitChoice.title(unit)) { model.entry.unit = unit }
          }
        } label: {
          Text("\(UnitChoice.title(model.entry.unit)) \u{25BE}")
            .font(FieldTheme.chip)
            .foregroundStyle(FieldTheme.ink)
            .frame(width: 88, height: FieldTheme.fieldHeight)
            .background(FieldTheme.nude)
            .clipShape(RoundedRectangle(cornerRadius: FieldTheme.cardRadius))
        }
        .accessibilityLabel("Unit")
      }
    }

    /// Records which instrument was used (the contract requires it). Manual entry only.
    private var methodRow: some View {
      HStack(spacing: FieldTheme.space8) {
        ChoiceChip(title: "Tape", isSelected: model.entry.method == .tape) {
          model.entry.method = .tape
        }
        ChoiceChip(title: "Laser", isSelected: model.entry.method == .laser) {
          model.entry.method = .laser
        }
      }
    }

    private var upperFloorPicker: some View {
      VStack(alignment: .leading, spacing: FieldTheme.space8) {
        FieldCaption(text: "Upper floor")
        FlowLayout {
          ForEach(Array(model.floors.enumerated()), id: \.element.id) { index, floor in
            if index != model.selectedFloorIndex {
              ChoiceChip(title: floor.label, isSelected: model.upperFloorIndex == index) {
                model.upperFloorIndex = index
              }
            }
          }
        }
      }
    }
  }
#endif

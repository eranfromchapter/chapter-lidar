#if canImport(SwiftUI) && canImport(UIKit)
  import ChapterUI
  import FieldRules
  import SwiftUI

  /// The room picker behind the `More` chip (phone-field §3.3, not drawn): every room of the
  /// capture (the selected one checked, the ones without a photo marked), a room not in the
  /// list, and "Rename rooms". Choosing a room closes the sheet.
  struct RoomPickerSheet: View {
    @Bindable var model: PhotoLabelingModel
    /// "Rename rooms"; nil hides the row. The caller closes this sheet, then opens the rename
    /// sheet.
    let onRenameRooms: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    private var rooms: [String] { PhotoCoverage.rooms(model.capture.rooms) }

    private var canUseOtherRoom: Bool {
      !model.otherRoom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
      VStack(spacing: 0) {
        SheetBar(title: "Rooms on \(model.capture.label)", onCancel: { dismiss() })
        ScrollView {
          VStack(alignment: .leading, spacing: FieldMetric.sheetSectionGap) {
            if !rooms.isEmpty {
              ChapterCard {
                ForEach(rooms, id: \.self) { room in roomRow(room) }
              }
            }
            VStack(alignment: .leading, spacing: FieldTheme.Metric.sectionHeaderGap) {
              SectionCaption("Other room")
              ChapterCard { otherRoomRow }
            }
            if let onRenameRooms {
              ChapterCard {
                Button(action: onRenameRooms) {
                  HStack(spacing: FieldTheme.Metric.rowGap) {
                    Image(systemName: "pencil")
                      .foregroundStyle(FieldTheme.Color.ink)
                      .accessibilityHidden(true)
                    Text("Rename rooms")
                      .chapterTextStyle(.body)
                      .foregroundStyle(FieldTheme.Color.ink)
                      .frame(maxWidth: .infinity, alignment: .leading)
                    Chevron()
                  }
                  .padding(.horizontal, FieldTheme.Metric.rowPadding)
                  .frame(minHeight: FieldTheme.Metric.navigationRowHeight)
                }
                .buttonStyle(FieldRowButtonStyle())
                .accessibilityIdentifier("photo.renameRooms")
              }
            }
          }
          .padding(.horizontal, FieldTheme.Metric.screenPadding)
          .padding(.top, 8)
          .padding(.bottom, FieldTheme.Metric.screenPadding)
        }
        .scrollDismissesKeyboard(.interactively)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .foregroundStyle(FieldTheme.Color.ink)
      .background(FieldTheme.Color.ground.ignoresSafeArea())
      .presentationDetents([.medium, .large])
      .chapterSheet()
    }

    private func roomRow(_ room: String) -> some View {
      let selected = model.isSelected(room)
      return Button {
        model.chooseRoom(room)
        dismiss()
      } label: {
        HStack(spacing: FieldTheme.Metric.rowGap) {
          Text(room)
            .chapterTextStyle(.body)
            .foregroundStyle(FieldTheme.Color.ink)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
          if model.needsPhoto(room) { NoPhotoYetLabel() }
          if selected {
            Image(systemName: "checkmark")
              .font(.system(size: 17, weight: .semibold))
              .foregroundStyle(FieldTheme.Color.ink)
              .accessibilityHidden(true)
          }
        }
        .padding(.horizontal, FieldTheme.Metric.rowPadding)
        .padding(.vertical, 4)
        .frame(minHeight: FieldTheme.Metric.navigationRowHeight)
      }
      .buttonStyle(FieldRowButtonStyle())
      .accessibilityElement(children: .combine)
      .accessibilityAddTraits(selected ? .isSelected : [])
      .accessibilityIdentifier("photo.picker.\(room)")
    }

    private var otherRoomRow: some View {
      HStack(spacing: FieldTheme.Metric.rowGap) {
        TextField(
          text: $model.otherRoom,
          prompt: Text("Room not in the list").foregroundStyle(FieldTheme.Color.muted)
        ) {
          Text("Other room")
        }
        .font(FieldTheme.Font.body)
        .foregroundStyle(FieldTheme.Color.ink)
        .textInputAutocapitalization(.words)
        .submitLabel(.done)
        .onSubmit(useOtherRoom)
        .onChange(of: model.otherRoom) { _, text in
          if text.count > PhotoLabelDraft.maximumRoomLength {
            model.otherRoom = String(text.prefix(PhotoLabelDraft.maximumRoomLength))
          }
        }
        .accessibilityIdentifier("photo.otherRoom")
        Button("Use", action: useOtherRoom)
          .buttonStyle(.chapter(.rowAction))
          .disabled(!canUseOtherRoom)
          .accessibilityIdentifier("photo.useOtherRoom")
      }
      .padding(.horizontal, FieldTheme.Metric.rowPadding)
      .padding(.vertical, 4)
      .frame(minHeight: FieldTheme.Metric.navigationRowHeight)
    }

    private func useOtherRoom() {
      if model.useOtherRoom() { dismiss() }
    }
  }
#endif

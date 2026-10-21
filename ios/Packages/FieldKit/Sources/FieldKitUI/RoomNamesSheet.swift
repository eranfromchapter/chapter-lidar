#if canImport(SwiftUI) && canImport(UIKit)
  import ChapterUI
  import FieldRules
  import SwiftUI
  import UIKit

  /// "Rename rooms" in the v2 sheet pattern (phone-field §7): every room of the capture (or of
  /// each capture, from the checklist) with a field prefilled with its name and quick names under
  /// it (Shower, Closet, Bathroom…). RoomPlan has no shower: a small room the scan called
  /// "Closet" can be named what it is.
  ///
  /// A room the checklist still asks a photo of says "No photo yet". The sheet opens at the
  /// room `RoomNamingDraft.focusRoomId` names (the Closet of "Closet has no photo"), and the room
  /// being typed in is kept above the keyboard with its quick names in view.
  ///
  /// `onSave` gets the renamed rooms and returns an error message to show, or nil when the
  /// names were saved (the sheet then closes). `isReadOnly` (a sealed visit) hides Save.
  public struct RoomNamesSheet: View {
    @State private var draft: RoomNamingDraft
    @State private var error: String?
    @FocusState private var focused: String?
    @Environment(\.dismiss) private var dismiss
    let isReadOnly: Bool
    let onSave: ([RoomRename]) -> String?

    public init(
      draft: RoomNamingDraft, isReadOnly: Bool = false, onSave: @escaping ([RoomRename]) -> String?
    ) {
      _draft = State(initialValue: draft)
      self.isReadOnly = isReadOnly
      self.onSave = onSave
    }

    public var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        SheetBar(
          title: "Rename rooms", cancelTitle: isReadOnly ? "Close" : "Cancel", onCancel: { dismiss() },
          actionTitle: isReadOnly ? nil : "Save", isActionEnabled: draft.canSave, onAction: save,
          cancelAccessibilityIdentifier: "rooms.cancel", actionAccessibilityIdentifier: "rooms.save")
        VStack(alignment: .leading, spacing: 4) {
          Text(
            "The new name goes on the floor plan, the report and the photos already labeled with the old name."
          )
          .chapterTextStyle(.footnote)
          .foregroundStyle(FieldTheme.Color.muted)
          .fixedSize(horizontal: false, vertical: true)
          if let error {
            Text(error)
              .chapterTextStyle(.footnote)
              .foregroundStyle(FieldTheme.Color.blocked)
              .fixedSize(horizontal: false, vertical: true)
              .accessibilityIdentifier("rooms.error")
          }
        }
        .padding(.horizontal, FieldTheme.Metric.screenPadding)
        .padding(.bottom, 10)

        ScrollViewReader { proxy in
          ScrollView {
            VStack(alignment: .leading, spacing: FieldTheme.Metric.sectionGap) {
              ForEach(draft.captures) { capture in
                VStack(alignment: .leading, spacing: FieldMetric.sheetSectionGap) {
                  if draft.captures.count > 1 {
                    SectionCaption(capture.label)
                  }
                  ForEach(capture.rooms) { room in
                    editor(room).id(room.id)
                  }
                }
              }
            }
            .disabled(isReadOnly)
            .padding(.horizontal, FieldTheme.Metric.screenPadding)
            .padding(.bottom, FieldTheme.Metric.screenPadding)
          }
          .scrollDismissesKeyboard(.interactively)
          .onAppear {
            // Opened from "Closet has no photo": start at the Closet.
            guard let target = draft.focusRoomId else { return }
            DispatchQueue.main.async { proxy.scrollTo(target, anchor: .top) }
          }
          .onChange(of: focused) { _, room in
            // SwiftUI scrolls the field itself only to the keyboard's edge, with its quick
            // names hidden: scroll the room's whole block above the keyboard once it is up.
            guard let room else { return }
            Task { @MainActor in
              try? await Task.sleep(for: .milliseconds(350))
              guard focused == room else { return }
              withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(room, anchor: .bottom) }
            }
          }
          .onReceive(
            NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)
          ) { _ in
            guard let room = focused else { return }
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(room, anchor: .bottom) }
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .foregroundStyle(FieldTheme.Color.ink)
      .background(FieldTheme.Color.ground.ignoresSafeArea())
      .presentationDetents([.large])
      .chapterSheet()
    }

    /// One room: what the scan called it (and "No photo yet"), then a card with the name field
    /// and a row of quick names; what is wrong with the name under the card.
    private func editor(_ room: RoomNamingDraft.Room) -> some View {
      let issue = draft.issue(room: room.id)
      let name = room.name.trimmingCharacters(in: .whitespacesAndNewlines)
      let shape = RoundedRectangle(cornerRadius: FieldTheme.Metric.cardRadius)
      return VStack(alignment: .leading, spacing: FieldTheme.Metric.sectionHeaderGap) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(room.caption)
            .chapterTextStyle(.footnote)
            .foregroundStyle(FieldTheme.Color.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
          if room.needsPhoto {
            // The chips' dot: the checklist still asks a photo of this room.
            NoPhotoYetLabel()
              .accessibilityIdentifier("rooms.needsPhoto.\(room.roomId)")
          }
        }
        .padding(.horizontal, FieldTheme.Metric.sectionInset)
        ChapterCard {
          TextField(
            text: Binding(get: { room.name }, set: { draft.setName($0, room: room.id) }),
            prompt: Text(room.scannedLabel).foregroundStyle(FieldTheme.Color.muted)
          ) {
            Text("Name of \(room.currentLabel)")
          }
          .font(FieldTheme.Font.body)
          .foregroundStyle(FieldTheme.Color.ink)
          .focused($focused, equals: room.id)
          .textInputAutocapitalization(.words)
          .submitLabel(.done)
          .padding(.horizontal, FieldTheme.Metric.rowPadding)
          .frame(minHeight: FieldTheme.Metric.navigationRowHeight)
          .accessibilityLabel("Name of \(room.currentLabel)")
          .accessibilityIdentifier("rooms.name.\(room.roomId)")
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: FieldMetric.chipGap) {
              ForEach(RoomNamingDraft.suggestions, id: \.self) { suggestion in
                ChoiceChip(suggestion, isSelected: name == suggestion, kind: .subject) {
                  draft.setName(suggestion, room: room.id)
                  focused = nil
                  error = nil
                }
                .accessibilityIdentifier("rooms.suggest.\(room.roomId).\(suggestion)")
              }
            }
            .padding(.horizontal, FieldTheme.Metric.rowPadding)
            .padding(.vertical, 8)
          }
        }
        .overlay {
          if issue != nil { shape.strokeBorder(FieldTheme.Color.blocked, lineWidth: 1.5) }
        }
        if let issue {
          Text(issue.text)
            .chapterTextStyle(.footnote)
            .foregroundStyle(FieldTheme.Color.blocked)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, FieldTheme.Metric.sectionInset)
            .accessibilityIdentifier("rooms.issue.\(room.roomId)")
        }
      }
    }

    private func save() {
      focused = nil
      if let message = onSave(draft.changes) {
        error = message
      } else {
        dismiss()
      }
    }
  }
#endif

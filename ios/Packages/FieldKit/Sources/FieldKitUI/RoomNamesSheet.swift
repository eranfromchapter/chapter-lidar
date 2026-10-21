#if canImport(SwiftUI) && canImport(UIKit)
  import FieldRules
  import SwiftUI
  import UIKit

  /// "Rename rooms": every room of the capture (or of each capture, from the checklist) with a
  /// text field prefilled with its name and quick names under it (Shower, Closet, Bathroom…).
  /// RoomPlan has no shower: a small room the scan called "Closet" can be named what it is.
  ///
  /// A room the checklist still asks a photo of says "No photo yet". The sheet opens at the
  /// room `RoomNamingDraft.focusRoomId` names (the Closet of "Closet has no photo"), and the room
  /// being typed in is kept above the Save bar with its quick names in view.
  ///
  /// `onSave` gets the renamed rooms and returns an error message to show, or nil when the
  /// names were saved (the sheet then closes).
  public struct RoomNamesSheet: View {
    @State private var draft: RoomNamingDraft
    @State private var error: String?
    @FocusState private var focused: String?
    @Environment(\.dismiss) private var dismiss
    let onSave: ([RoomRename]) -> String?

    public init(draft: RoomNamingDraft, onSave: @escaping ([RoomRename]) -> String?) {
      _draft = State(initialValue: draft)
      self.onSave = onSave
    }

    /// The screen's side margin; the rows of quick names scroll from edge to edge past it.
    private let margin: CGFloat = 20

    public var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        VStack(alignment: .leading, spacing: 0) {
          HStack(alignment: .firstTextBaseline) {
            Text("Rename rooms")
              .font(FieldTheme.title30())
              .accessibilityAddTraits(.isHeader)
            Spacer()
            Button("Cancel") { dismiss() }
              .font(FieldTheme.chip)
              .foregroundStyle(FieldTheme.ink)
              .frame(minWidth: FieldTheme.chipHeight, minHeight: FieldTheme.chipHeight)
              .accessibilityIdentifier("rooms.cancel")
          }
          Text(
            "The new name goes on the floor plan, the report and the photos already labeled with the old name."
          )
          .font(FieldTheme.caption)
          .foregroundStyle(FieldTheme.muted)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.bottom, FieldTheme.space16)
        }
        .padding(.horizontal, margin)

        ScrollViewReader { proxy in
          ScrollView {
            VStack(alignment: .leading, spacing: FieldTheme.space24) {
              ForEach(draft.captures) { capture in
                VStack(alignment: .leading, spacing: FieldTheme.space16) {
                  if draft.captures.count > 1 {
                    Text(capture.label).font(FieldTheme.rowTitle)
                  }
                  ForEach(capture.rooms) { room in
                    editor(room)
                      .id(room.id)
                    if room.id != capture.rooms.last?.id {
                      Rectangle().fill(FieldTheme.nude).frame(height: 1)
                    }
                  }
                }
              }
            }
            .padding(.horizontal, margin)
            .padding(.bottom, FieldTheme.space16)
          }
          .scrollDismissesKeyboard(.interactively)
          .onAppear {
            // Opened from "Closet has no photo": start at the Closet.
            guard let target = draft.focusRoomId else { return }
            DispatchQueue.main.async { proxy.scrollTo(target, anchor: .top) }
          }
          .onChange(of: focused) { _, room in
            // SwiftUI scrolls the field itself only to the keyboard's edge, under the Save bar
            // and with its quick names hidden: scroll the room's whole block above the bar
            // once the keyboard is up.
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

        VStack(alignment: .leading, spacing: FieldTheme.space8) {
          if let error {
            Text(error).font(FieldTheme.caption).foregroundStyle(FieldTheme.blocked)
          }
          PrimaryButton(title: "Save names", isEnabled: draft.canSave) { save() }
            .accessibilityIdentifier("rooms.save")
        }
        .padding(.top, FieldTheme.space8)
        .padding(.horizontal, margin)
      }
      .padding(.top, FieldTheme.space24)
      .padding(.bottom, FieldTheme.space16)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .background(FieldTheme.ground.ignoresSafeArea())
      .foregroundStyle(FieldTheme.ink)
      .presentationDetents([.large])
      .presentationDragIndicator(.visible)
    }

    private func editor(_ room: RoomNamingDraft.Room) -> some View {
      let issue = draft.issue(room: room.id)
      let name = room.name.trimmingCharacters(in: .whitespacesAndNewlines)
      return VStack(alignment: .leading, spacing: FieldTheme.space8) {
        HStack(alignment: .firstTextBaseline, spacing: FieldTheme.space8) {
          FieldCaption(text: room.caption)
          Spacer(minLength: 0)
          if room.needsPhoto {
            // The chips' dot: the checklist still asks a photo of this room.
            Label {
              Text("No photo yet")
            } icon: {
              Circle().fill(FieldTheme.blocked).frame(width: 7, height: 7)
            }
            .font(FieldTheme.caption)
            .foregroundStyle(FieldTheme.blocked)
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("No photo yet")
            .accessibilityIdentifier("rooms.needsPhoto.\(room.roomId)")
          }
        }
        TextField(
          room.scannedLabel,
          text: Binding(get: { room.name }, set: { draft.setName($0, room: room.id) })
        )
        .fieldBox()
        .focused($focused, equals: room.id)
        .textInputAutocapitalization(.words)
        .submitLabel(.done)
        .overlay(
          RoundedRectangle(cornerRadius: FieldTheme.cardRadius)
            .stroke(issue == nil ? Color.clear : FieldTheme.blocked, lineWidth: 2))
        .accessibilityLabel("Name of \(room.currentLabel)")
        .accessibilityIdentifier("rooms.name.\(room.roomId)")
        if let issue {
          Text(issue.text)
            .font(FieldTheme.caption)
            .foregroundStyle(FieldTheme.blocked)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("rooms.issue.\(room.roomId)")
        }
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: FieldTheme.space8) {
            ForEach(RoomNamingDraft.suggestions, id: \.self) { suggestion in
              ChoiceChip(title: suggestion, isSelected: name == suggestion, horizontalPadding: 12) {
                draft.setName(suggestion, room: room.id)
                focused = nil
                error = nil
              }
              .accessibilityIdentifier("rooms.suggest.\(room.roomId).\(suggestion)")
            }
          }
          .padding(.horizontal, margin)
        }
        // Edge to edge: the row starts in line with the field and scrolls under the margins,
        // so a chip cut by the screen edge shows there are more.
        .padding(.horizontal, -margin)
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

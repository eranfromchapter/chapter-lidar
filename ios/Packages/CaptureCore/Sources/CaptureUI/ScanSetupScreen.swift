#if canImport(SwiftUI) && canImport(Observation) && os(iOS)
  import CaptureContract
  import CaptureCore
  import SwiftUI

  private typealias Palette = ChapterTokens.Palette
  private typealias Space = ChapterTokens.Space
  private typealias Radius = ChapterTokens.Radius
  private typealias Control = ChapterTokens.Control
  private typealias Typo = ChapterTokens.Typography

  /// Step 2 of 3: floor or area, mode, rooms you will not scan, coverage notes
  /// (docs/waves/design/snapshot.html#screen-capture, panel 2).
  struct ScanSetupScreen: View {
    @Bindable var model: CaptureFlowModel
    @State private var showAddRoom = false
    @State private var newRoomName = ""
    @State private var newRoomReason = ""

    var body: some View {
      VStack(alignment: .leading, spacing: 18) {
        HStack {
          Button {
            model.back()
          } label: {
            Text("‹ Back").font(Typo.body).foregroundStyle(Palette.ink)
              .frame(minHeight: Control.minTouch)
          }
          .buttonStyle(.plain)
          Spacer()
          Text("Step 2 of 3").font(Typo.caption).foregroundStyle(Palette.muted)
        }
        Text("What are you scanning?").font(Typo.display).foregroundStyle(Palette.ink)
          .accessibilityAddTraits(.isHeader)

        VStack(alignment: .leading, spacing: Space.s2) {
          FieldLabel("Floor or area")
          TextField("Floor 1", text: $model.draft.floorLabel)
            .font(Typo.body)
            .padding(.horizontal, Space.s4)
            .frame(height: Control.fieldHeight)
            .fieldBackground()
            .submitLabel(.done)
        }

        VStack(alignment: .leading, spacing: Space.s2) {
          FieldLabel("Mode")
          HStack(spacing: 6) {
            ForEach(CaptureMode.allCases, id: \.self) { mode in
              let selected = model.draft.mode == mode
              Button {
                model.draft.mode = mode
              } label: {
                Text(CaptureFlowModel.modeTitle(mode))
                  .font(Typo.sans(15, weight: selected ? .semibold : .regular))
                  .foregroundStyle(Palette.ink)
                  .frame(maxWidth: .infinity, minHeight: Control.segmentHeight)
                  .background(
                    selected ? Palette.surface : Color.clear,
                    in: RoundedRectangle(cornerRadius: Radius.segment))
              }
              .buttonStyle(.plain)
              .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
          }
          .padding(Space.s1)
          .background(Palette.nude, in: RoundedRectangle(cornerRadius: Radius.card))
        }

        VStack(alignment: .leading, spacing: Space.s2) {
          FieldLabel("Rooms you will not scan")
          WrapLayout(spacing: Space.s2) {
            ForEach(Array(model.draft.omittedRooms.enumerated()), id: \.offset) { index, room in
              Button {
                model.removeOmittedRoom(at: index)
              } label: {
                Text(chipText(room))
                  .font(Typo.sans(15)).foregroundStyle(Palette.ink)
                  .padding(.horizontal, 14).padding(.vertical, 10)
                  .background(Palette.nude, in: RoundedRectangle(cornerRadius: Radius.chip))
              }
              .buttonStyle(.plain)
              .accessibilityLabel("\(room.name), not scanned. Remove")
            }
            Button {
              newRoomName = ""
              newRoomReason = ""
              showAddRoom = true
            } label: {
              Text("+ Add room")
                .font(Typo.sans(15)).foregroundStyle(Palette.ink)
                .padding(.horizontal, 14)
                .frame(minHeight: Control.minTouch)
                .overlay(
                  RoundedRectangle(cornerRadius: Radius.chip)
                    .strokeBorder(Palette.muted, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }
            .buttonStyle(.plain)
          }
        }

        VStack(alignment: .leading, spacing: Space.s2) {
          FieldLabel("Coverage notes")
          TextEditor(text: $model.draft.coverageNotes)
            .font(Typo.sans(15))
            .scrollContentBackground(.hidden)
            .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
            .frame(height: 96)
            .fieldBackground()
        }

        if let message = model.errorMessage {
          Text("■ \(message)").font(Typo.caption).foregroundStyle(Palette.blocked)
        }

        Spacer(minLength: 0)
        PrimaryButton(title: "Start scan", isEnabled: model.canStartScan) {
          Task { await model.startScan() }
        }
        .accessibilityHint(
          model.canStartScan ? "" : model.draft.validate().map(\.description).joined(separator: " "))
      }
      .padding(.horizontal, 20)
      .padding(.top, Space.s2)
      .padding(.bottom, Space.s4)
      .alert("Add room", isPresented: $showAddRoom) {
        TextField("Room name", text: $newRoomName)
        TextField("Reason (optional)", text: $newRoomReason)
        Button("Add") {
          if !newRoomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            model.addOmittedRoom(name: newRoomName, reason: newRoomReason)
          }
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("A room you will not scan, for example a locked closet.")
      }
    }

    /// "Primary closet · locked ✕".
    private func chipText(_ room: CaptureRecord.RoomNote) -> String {
      if let reason = room.reason, !reason.isEmpty {
        return "\(room.name) · \(reason) ✕"
      }
      return "\(room.name) ✕"
    }
  }
#endif

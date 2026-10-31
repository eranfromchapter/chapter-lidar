#if canImport(SwiftUI) && os(iOS)
  import CaptureContract
  import ChapterUI
  import SketchEntry
  import SwiftUI

  /// Step 3 of 4, Rooms and measurements (spec F14 2.1, 2.4): the sketch on top, pinch to
  /// zoom; the floor's ceiling height; the rooms as a list, each opening its guided entry
  /// (`SketchRoomSheet`); "Add a room". A form, not a drawing editor: the operator enters the
  /// topology by tapping. Check moves the model on (`model.step == .check`), which the host
  /// pushes.
  public struct SketchRoomsScreen: View {
    @Bindable var model: SketchEntryModel
    let caption: String
    @State private var editingRoom: EditingRoom?

    struct EditingRoom: Identifiable {
      let id: String
    }

    public init(model: SketchEntryModel, caption: String = "Step 3 of 4") {
      self.model = model
      self.caption = caption
    }

    public var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: ChapterTheme.Metric.sectionGapCompact) {
          if let image = model.image {
            SketchImageCard(selection: image)
          }
          ChapterSection(
            header: "Ceiling height",
            footer: "Once for the floor. A room with a different ceiling has its own in its entry."
          ) {
            SketchLengthRow(
              title: "Floor to ceiling", field: $model.ceilingHeight, identifier: "sketch.ceiling")
          }
          rooms
        }
        .sketchContent()
      }
      .scrollDismissesKeyboard(.interactively)
      .navigationTitle("Rooms and measurements")
      .navigationBarTitleDisplayMode(.large)
      .sketchNavigationCaption(caption)
      .chapterBackChevronOnly()
      .chapterScreenBackground()
      .chapterActionBar {
        Button("Check") { model.continueToCheck() }
          .buttonStyle(.chapter(.primary))
          .disabled(!model.canContinueToCheck)
          .accessibilityIdentifier("sketch.check")
      }
      .sheet(item: $editingRoom) { room in
        SketchRoomSheet(model: model, roomId: room.id)
      }
    }

    private var rooms: some View {
      ChapterSection(
        header: "Rooms",
        footer:
          "Walls go around each room counter-clockwise as drawn. Two adjacent walls, the ceiling "
          + "and each door or window are required; the other walls and a diagonal check them."
      ) {
        ForEach(Array(model.rooms.enumerated()), id: \.element.id) { index, room in
          let missing = missingCount(of: room, position: index + 1)
          NavigationRow(
            title: room.displayName(position: index + 1),
            subtitle: SketchText.roomSummary(walls: room.walls.count, openings: room.openings.count),
            status: missing == 0
              ? RowStatus(.done, "Entered")
              : RowStatus(.missing, "\(missing) missing"),
            isPlaceholder: room.cleanedLabel.isEmpty
          ) {
            editingRoom = EditingRoom(id: room.id)
          }
          .accessibilityIdentifier("sketch.room.\(room.id)")
        }
        AddRow(title: "Add a room") {
          let id = model.addRoom()
          editingRoom = EditingRoom(id: id)
        }
        .accessibilityIdentifier("sketch.room.add")
      }
    }

    /// How many required values this room still lacks (its lines of `missingRequired`).
    private func missingCount(of room: SketchRoomDraft, position: Int) -> Int {
      let prefix = "\(room.displayName(position: position)): "
      return model.missingRequired.filter { $0.hasPrefix(prefix) }.count
    }
  }
#endif

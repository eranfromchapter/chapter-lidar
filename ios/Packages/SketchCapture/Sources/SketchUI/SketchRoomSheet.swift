#if canImport(SwiftUI) && os(iOS)
  import CaptureContract
  import ChapterUI
  import SketchEntry
  import SwiftUI

  /// One room's guided entry (spec F14 2.1), over Rooms and measurements: name and type;
  /// shape (rectangle, L-shape, other with a corner count); "Are all corners square?"; the
  /// walls in order (length with Measured / About, exterior, shared with an earlier room's
  /// wall, the corner at its end when not all are square); the diagonals (one per unsquare
  /// corner, and the squareness check as "Also measured"); the openings per wall (kind, width,
  /// from which corner and how far, a window's sill and height, a door's height as "Also
  /// measured"); and the room's own ceiling height when it differs from the floor's.
  struct SketchRoomSheet: View {
    @Bindable var model: SketchEntryModel
    let roomId: String
    @Environment(\.dismiss) private var dismiss
    @State private var removesRoom = false

    private var room: SketchRoomDraft? { model.room(roomId) }

    private var title: String { model.displayName(of: roomId) }

    var body: some View {
      VStack(spacing: 0) {
        SheetBar(
          title: title, cancelTitle: "Done", onCancel: { dismiss() },
          cancelAccessibilityIdentifier: "sketch.room.done")
        ScrollView {
          if let room {
            VStack(alignment: .leading, spacing: ChapterTheme.Metric.sectionGapCompact) {
              nameSection(room)
              shapeSection(room)
              wallsSection(room)
              diagonalsSection(room)
              openingsSection(room)
              ceilingSection
              Button("Remove this room", role: .destructive) { removesRoom = true }
                .buttonStyle(.chapter(.destructive))
                .accessibilityIdentifier("sketch.room.remove")
            }
            .padding(.horizontal, ChapterTheme.Metric.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, ChapterTheme.Metric.sectionGap)
            .chapterContentWidth()
          }
        }
        .scrollDismissesKeyboard(.interactively)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .chapterScreenBackground()
      .presentationDetents([.large])
      .chapterSheet()
      .confirmationDialog("Remove \(title)?", isPresented: $removesRoom, titleVisibility: .visible) {
        Button("Remove the room", role: .destructive) {
          model.removeRoom(roomId)
          dismiss()
        }
        Button("Keep it", role: .cancel) {}
      } message: {
        Text("Its walls and openings go with it.")
      }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("sketch.room.sheet")
    }

    // MARK: Bindings

    private var label: Binding<String> {
      Binding(
        get: { room?.label ?? "" }, set: { value in model.update(roomId) { $0.label = value } })
    }

    private var type: Binding<RoomType?> {
      Binding(
        get: { room?.type }, set: { value in model.update(roomId) { $0.type = value } })
    }

    private func wallLength(_ index: Int) -> Binding<SketchLengthField> {
      Binding(
        get: {
          guard let room, room.walls.indices.contains(index) else {
            return SketchLengthField(unit: model.units.long)
          }
          return room.walls[index].length
        },
        set: { value in
          model.update(roomId) { room in
            guard room.walls.indices.contains(index) else { return }
            room.walls[index].length = value
          }
        })
    }

    private func wallExterior(_ index: Int) -> Binding<Bool> {
      Binding(
        get: { room?.walls.indices.contains(index) == true ? room!.walls[index].isExterior : false },
        set: { value in
          model.update(roomId) { room in
            guard room.walls.indices.contains(index) else { return }
            room.walls[index].isExterior = value
          }
        })
    }

    private func diagonal(_ pair: (from: Int, to: Int)) -> Binding<SketchLengthField> {
      Binding(
        get: { model.diagonal(roomId, from: pair.from, to: pair.to) },
        set: { model.setDiagonal(roomId, from: pair.from, to: pair.to, $0) })
    }

    private func opening<Value>(
      _ openingId: String, _ path: WritableKeyPath<SketchOpeningDraft, Value>, default value: Value
    ) -> Binding<Value> {
      Binding(
        get: { room?.openings.first { $0.id == openingId }?[keyPath: path] ?? value },
        set: { new in model.updateOpening(roomId, openingId) { $0[keyPath: path] = new } })
    }

    private var ceiling: Binding<SketchLengthField> {
      Binding(
        get: { room?.ceilingHeight ?? SketchLengthField(unit: model.units.long) },
        set: { value in model.update(roomId) { $0.ceilingHeight = value } })
    }

    // MARK: Name and type

    private func nameSection(_ room: SketchRoomDraft) -> some View {
      ChapterSection(header: "Room") {
        TextFieldRow(label: "Name", text: label, prompt: "Bedroom", accessibilityLabel: "Room name")
          .textInputAutocapitalization(.words)
          .submitLabel(.done)
          .accessibilityIdentifier("sketch.room.name")
        SketchChipRow(
          label: "Type",
          options: RoomType.allCases.map {
            .init(value: $0, title: SketchText.roomTypeTitle($0), identifier: "sketch.room.type.\($0.rawValue)")
          },
          selection: type)
      }
    }

    // MARK: Shape

    private func shapeSection(_ room: SketchRoomDraft) -> some View {
      ChapterSection(
        header: "Shape",
        footer: room.allCornersSquare
          ? nil
          : "Mark each corner that is not 90°; a diagonal across it is asked below."
      ) {
        SketchSegmentedRow(
          label: "Outline",
          selection: Binding<SketchRoomShape.Kind?>(
            get: { room.shape.kind },
            set: { kind in
              guard let kind, kind != room.shape.kind else { return }
              model.setShape(roomId, kind.defaultShape)
            }),
          options: SketchRoomShape.Kind.allCases.map {
            .init($0, $0.title, accessibilityIdentifier: "sketch.room.shape.\($0.rawValue)")
          })
        if case .lShape(let inside) = room.shape {
          SketchChipRow(
            label: "Inside corner at the end of",
            options: (0..<6).map {
              .init(value: $0, title: SketchText.wallTitle(index: $0), identifier: "sketch.room.inside.\($0 + 1)")
            },
            selection: Binding(
              get: { inside }, set: { if let wall = $0 { model.setShape(roomId, .lShape(insideWall: wall)) } }))
        }
        if case .other(let corners) = room.shape {
          Stepper(
            value: Binding(
              get: { corners }, set: { model.setShape(roomId, .other(corners: $0)) }),
            in: SketchRoomShape.minimumCorners...SketchRoomShape.maximumCorners
          ) {
            Text("\(corners) corners")
              .chapterTextStyle(.body)
              .foregroundStyle(ChapterTheme.Color.ink)
          }
          .padding(.horizontal, ChapterTheme.Metric.rowPadding)
          .frame(minHeight: ChapterTheme.Metric.navigationRowHeight)
          .accessibilityIdentifier("sketch.room.corners")
        }
        ToggleRow(
          "All corners square",
          isOn: Binding(
            get: { room.allCornersSquare }, set: { model.setAllCornersSquare(roomId, $0) })
        )
        .accessibilityIdentifier("sketch.room.allSquare")
      }
    }

    // MARK: Walls

    private func wallsSection(_ room: SketchRoomDraft) -> some View {
      let choices = model.sharedWallChoices(for: roomId)
      return ChapterSection(
        header: "Walls",
        footer:
          "In order around the room, counter-clockwise as drawn. Leave a wall empty when you did "
          + "not measure it: one per direction is filled from the others."
      ) {
        ForEach(Array(room.walls.enumerated()), id: \.element.id) { index, wall in
          VStack(alignment: .leading, spacing: 0) {
            SketchLengthRow(
              title: SketchText.wallTitle(index: index), field: wallLength(index),
              identifier: "sketch.wall.\(wall.id).length",
              subtitle: wall.sharedWith.map { shared in
                choices.first { $0.shared == shared }.map { "Shared with \($0.title)" } ?? "Shared"
              })
            HStack(spacing: ChapterTheme.Metric.rowGap) {
              Toggle(isOn: wallExterior(index)) {
                Text("Exterior")
                  .chapterTextStyle(.subhead)
                  .foregroundStyle(ChapterTheme.Color.ink)
              }
              .tint(ChapterTheme.Color.ink)
              .fixedSize()
              .accessibilityIdentifier("sketch.wall.\(wall.id).exterior")
              Spacer(minLength: 0)
              if !choices.isEmpty {
                Menu {
                  Button("Not shared") { model.setSharedWall(roomId, wallId: wall.id, nil) }
                  ForEach(choices) { choice in
                    Button(choice.title) { model.setSharedWall(roomId, wallId: wall.id, choice.shared) }
                  }
                } label: {
                  Text(wall.sharedWith == nil ? "Shared with…" : "Shared")
                    .chapterTextStyle(.subhead)
                    .foregroundStyle(ChapterTheme.Color.ink)
                    .padding(.horizontal, ChapterTheme.Metric.rowActionPadding)
                    .frame(minHeight: 32)
                    .background(
                      ChapterTheme.Color.nude,
                      in: RoundedRectangle(cornerRadius: ChapterTheme.Metric.rowActionRadius))
                }
                .accessibilityIdentifier("sketch.wall.\(wall.id).shared")
              }
            }
            .padding(.horizontal, ChapterTheme.Metric.rowPadding)
            .padding(.bottom, 8)
            if let turns = turnOptions(room, wallIndex: index) {
              SketchSegmentedRow(
                label: "Corner at the end of \(SketchText.wallTitle(index: index).lowercased())",
                selection: Binding<SketchTurn?>(
                  get: { wall.turn }, set: { if let turn = $0 { model.setTurn(roomId, wallIndex: index, turn) } }),
                options: turns.map {
                  .init($0, SketchText.turnTitle($0), accessibilityIdentifier: "sketch.wall.\(wall.id).turn.\($0.rawValue)")
                })
            }
          }
        }
      }
    }

    /// The turns the operator may pick at the end of a wall: any of "other"; "not square"
    /// against the shape's own turn when the corners are not all square; nothing otherwise.
    private func turnOptions(_ room: SketchRoomDraft, wallIndex: Int) -> [SketchTurn]? {
      let fixed = room.shape.fixedTurn(atEndOfWall: wallIndex)
      switch (fixed, room.allCornersSquare) {
      case (nil, true): return [.left, .right]
      case (nil, false): return [.left, .right, .unsquare]
      case (.some, true): return nil
      case (.some(let turn), false): return [turn, .unsquare]
      }
    }

    // MARK: Diagonals

    /// The diagonals asked: one across each unsquare corner (required), then the squareness
    /// check of a four-cornered room when it is not one of those.
    private func diagonalPairs(_ room: SketchRoomDraft) -> [(from: Int, to: Int, reason: String)] {
      var pairs: [(from: Int, to: Int, reason: String)] = []
      for corner in room.unsquareCorners {
        if let pair = room.diagonalCorners(across: corner) {
          pairs.append(
            (pair.from, pair.to,
             "Across \(SketchText.cornerTitle(index: corner).lowercased()) \u{00B7} required"))
        }
      }
      if let check = room.checkDiagonalCorners,
        !pairs.contains(where: { $0.from == check.from && $0.to == check.to })
      {
        pairs.append((check.from, check.to, "Also measured \u{00B7} checks the corners are square"))
      }
      return pairs
    }

    @ViewBuilder
    private func diagonalsSection(_ room: SketchRoomDraft) -> some View {
      let pairs = diagonalPairs(room)
      if !pairs.isEmpty {
        ChapterSection(header: "Diagonals", footer: "Corner to corner through the room.") {
          ForEach(pairs, id: \.from) { pair in
            SketchLengthRow(
              title: "\(SketchText.cornerTitle(index: pair.from)) to \(SketchText.cornerTitle(index: pair.to).lowercased())",
              field: diagonal((pair.from, pair.to)),
              identifier: "sketch.diagonal.\(pair.from + 1)-\(pair.to + 1)", subtitle: pair.reason)
          }
        }
      }
    }

    // MARK: Openings

    private func openingsSection(_ room: SketchRoomDraft) -> some View {
      ChapterSection(
        header: "Doors and windows",
        footer: "Width and the distance from the nearest corner to the jamb; a window's sill and height too."
      ) {
        ForEach(room.openings) { opening in
          openingRows(room, opening)
        }
        AddRow(title: "Add a door") { model.addOpening(roomId, kind: .door, wallId: room.walls[0].id) }
          .accessibilityIdentifier("sketch.opening.add.door")
        AddRow(title: "Add a window") { model.addOpening(roomId, kind: .window, wallId: room.walls[0].id) }
          .accessibilityIdentifier("sketch.opening.add.window")
        AddRow(title: "Add an opening without a door") {
          model.addOpening(roomId, kind: .opening, wallId: room.walls[0].id)
        }
        .accessibilityIdentifier("sketch.opening.add.opening")
      }
    }

    private func openingRows(_ room: SketchRoomDraft, _ opening: SketchOpeningDraft) -> some View {
      let id = opening.id
      return VStack(alignment: .leading, spacing: 0) {
        RemovableRow(
          title: opening.title,
          subtitle: room.walls.firstIndex { $0.id == opening.wallId }.map { SketchText.wallTitle(index: $0) },
          removeAccessibilityIdentifier: "sketch.opening.\(id).remove"
        ) {
          model.removeOpening(roomId, id)
        }
        SketchChipRow(
          label: "In wall",
          options: room.walls.enumerated().map { index, wall in
            .init(value: wall.id, title: SketchText.wallTitle(index: index), identifier: "sketch.opening.\(id).wall.\(wall.id)")
          },
          selection: Binding<String?>(
            get: { opening.wallId },
            set: { if let wall = $0 { model.updateOpening(roomId, id) { $0.wallId = wall } } }))
        SketchLengthRow(
          title: "Width", field: self.opening(id, \.width, default: opening.width),
          identifier: "sketch.opening.\(id).width")
        SketchSegmentedRow(
          label: "Measured from the wall's",
          selection: Binding<SketchWallCorner?>(
            get: { opening.fromCorner },
            set: { if let corner = $0 { model.updateOpening(roomId, id) { $0.fromCorner = corner } } }),
          options: [
            .init(SketchWallCorner.start, "Start corner", accessibilityIdentifier: "sketch.opening.\(id).fromCorner.start"),
            .init(.end, "End corner", accessibilityIdentifier: "sketch.opening.\(id).fromCorner.end"),
          ])
        SketchLengthRow(
          title: "Distance to the jamb", field: self.opening(id, \.fromCornerDistance, default: opening.fromCornerDistance),
          identifier: "sketch.opening.\(id).distance")
        if opening.kind == .window {
          SketchLengthRow(
            title: "Sill height", field: self.opening(id, \.sill, default: opening.sill),
            identifier: "sketch.opening.\(id).sill")
          SketchLengthRow(
            title: "Height", field: self.opening(id, \.height, default: opening.height),
            identifier: "sketch.opening.\(id).height")
        } else {
          SketchLengthRow(
            title: "Height", field: self.opening(id, \.height, default: opening.height),
            identifier: "sketch.opening.\(id).height", subtitle: "Also measured")
        }
      }
    }

    // MARK: Ceiling

    private var ceilingSection: some View {
      ChapterSection(header: "Ceiling \u{00B7} also measured") {
        SketchLengthRow(
          title: "This room's ceiling", field: ceiling, identifier: "sketch.room.ceiling",
          subtitle: "Only when it differs from the floor's")
      }
    }
  }
#endif

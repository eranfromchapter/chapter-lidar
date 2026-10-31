#if canImport(SwiftUI) && os(iOS)
  import CaptureContract
  import ChapterUI
  import SketchEntry
  import SwiftUI

  /// Step 3 of 5, Walk the rooms (spec F15 2): full screen like the live scan. The camera with
  /// the tapped corners, walls and openings drawn in AR, a reticle at the centre, the step's
  /// instruction at the top, the live 2D outline with each wall's length in the corner, and at
  /// the bottom Undo, the big + button and Done. Tracking problems disable + and say why.
  /// The host presents it as a full-screen cover while `model.phase == .walking`.
  public struct WalkthroughScreen: View {
    @Bindable var model: WalkthroughModel
    /// "Leave the walkthrough?" confirmed: the host drops the walk.
    let onCancel: @MainActor () -> Void
    @State private var confirmsLeave = false

    public init(model: WalkthroughModel, onCancel: @escaping @MainActor () -> Void) {
      self.model = model
      self.onCancel = onCancel
    }

    public var body: some View {
      ZStack {
        camera
          .ignoresSafeArea()
        reticle
        VStack(spacing: 10) {
          topBar
          HStack(alignment: .top) {
            Spacer(minLength: 0)
            WalkthroughOutlineView(
              rooms: model.outline, reticle: model.target, units: model.displayUnits)
              .frame(width: 180, height: 150)
          }
          Spacer(minLength: 0)
          stepControls
          bottomBar
        }
        .padding(.horizontal, ChapterTheme.Metric.screenPadding)
        .padding(.bottom, 8)
        if model.step == .roomName {
          roomCard
        }
      }
      .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
      .background(ChapterTheme.Color.ink.ignoresSafeArea())
      .preferredColorScheme(.dark)
      .onAppear { model.start() }
      .sensoryFeedback(.impact(weight: .medium), trigger: model.markers.count)
      .alert("Leave the walkthrough?", isPresented: $confirmsLeave) {
        Button("Keep walking", role: .cancel) {}
        Button("Leave", role: .destructive) { onCancel() }
      } message: {
        Text("The rooms walked so far are discarded.")
      }
    }

    // MARK: Camera

    @ViewBuilder
    private var camera: some View {
      #if canImport(ARKit)
        if let live = model.session as? LiveWalkthroughSession, live.isSupported {
          WalkthroughARView(
            session: live, markers: model.markers, lines: model.wallLines, target: model.target,
            canTap: model.canTap)
        } else {
          replayCamera
        }
      #else
        replayCamera
      #endif
    }

    /// The simulator and UI tests: no camera; a scripted session stands in.
    private var replayCamera: some View {
      ZStack {
        LinearGradient(
          colors: [Color(white: 0.30), Color(white: 0.14)], startPoint: .top, endPoint: .bottom)
        Label("Simulator: a scripted walk stands in for the camera", systemImage: "camera")
          .chapterTextStyle(.footnote)
          .foregroundStyle(Color.white.opacity(0.7))
          .offset(y: 56)
      }
      .accessibilityHidden(true)
    }

    private var reticle: some View {
      let colour = model.canTap ? ChapterTheme.Color.surface : ChapterTheme.Color.onDarkCaption
      return ZStack {
        Circle()
          .strokeBorder(colour, lineWidth: 2)
          .frame(width: 36, height: 36)
        Circle()
          .fill(colour)
          .frame(width: 5, height: 5)
      }
      .shadow(color: .black.opacity(0.5), radius: 2)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
    }

    // MARK: Top

    private var topBar: some View {
      HStack(alignment: .top, spacing: 10) {
        Button {
          confirmsLeave = true
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 17, weight: .semibold))
            .frame(width: 44, height: 44)
            .background(ChapterTheme.Color.onDarkPill, in: Circle())
        }
        .foregroundStyle(ChapterTheme.Color.surface)
        .accessibilityLabel(Text("Leave the walkthrough"))
        .accessibilityIdentifier("walkthrough.cancel")
        VStack(alignment: .leading, spacing: 4) {
          if let room = model.currentRoom {
            Text(room.label)
              .chapterTextStyle(.footnoteEmphasis)
              .foregroundStyle(ChapterTheme.Color.onDarkCaption)
              .accessibilityIdentifier("walkthrough.room")
          }
          Text(model.instruction)
            .chapterTextStyle(.bodyEmphasis)
            .foregroundStyle(ChapterTheme.Color.surface)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("walkthrough.instruction")
          if let message = model.trackingMessage {
            Label(message, systemImage: "exclamationmark.triangle.fill")
              .chapterTextStyle(.footnoteEmphasis)
              .foregroundStyle(ChapterTheme.Color.limited)
              .accessibilityIdentifier("walkthrough.tracking")
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(ChapterTheme.Color.onDarkPill, in: RoundedRectangle(cornerRadius: 14))
      }
      .padding(.top, 4)
    }

    // MARK: Step controls

    @ViewBuilder
    private var stepControls: some View {
      switch model.step {
      case .corners, .walls:
        HStack(spacing: 10) {
          if model.canSwitchMethod {
            darkChip(
              model.step == .corners ? "Tap each wall instead" : "Tap the corners instead",
              identifier: "walkthrough.switchMethod"
            ) {
              model.setMethod(model.step == .corners ? .walls : .corners)
            }
          }
          if model.step == .walls {
            darkChip("Close the room", identifier: "walkthrough.closeRoom") { model.closeWalls() }
              .disabled(!model.canCloseWalls)
          }
        }
      case .ceiling:
        if let room = model.sameCeilingRoom {
          darkChip("Same ceiling as \(room)", identifier: "walkthrough.sameCeiling") {
            model.useSameCeiling()
          }
        }
      case .openings:
        VStack(spacing: 10) {
          HStack(spacing: 10) {
            darkChip("Door", identifier: "walkthrough.add.door") { model.addOpening(.door) }
            darkChip("Window", identifier: "walkthrough.add.window") { model.addOpening(.window) }
            darkChip("Opening", identifier: "walkthrough.add.opening") { model.addOpening(.opening) }
          }
          darkChip("Next room", identifier: "walkthrough.nextRoom") { model.nextRoom() }
        }
      case .roomName, .opening:
        EmptyView()
      }
    }

    private func darkChip(
      _ title: String, identifier: String, action: @escaping () -> Void
    ) -> some View {
      Button(title, action: action)
        .buttonStyle(.chapter(.outlineOnDark))
        .accessibilityIdentifier(identifier)
    }

    // MARK: Bottom

    private var bottomBar: some View {
      HStack(alignment: .center, spacing: 16) {
        Button("Undo") { model.undo() }
          .buttonStyle(.chapter(.outlineOnDark))
          .disabled(!model.canUndo)
          .accessibilityIdentifier("walkthrough.undo")
        Button {
          model.tap()
        } label: {
          Image(systemName: "plus")
            .font(.system(size: 34, weight: .semibold))
            .foregroundStyle(ChapterTheme.Color.ink)
            .frame(width: 84, height: 84)
            .background(
              model.canTap ? ChapterTheme.Color.surface : ChapterTheme.Color.onDarkCaption,
              in: Circle())
            .overlay(Circle().strokeBorder(ChapterTheme.Color.surface.opacity(0.5), lineWidth: 4).padding(-6))
        }
        .buttonStyle(.plain)
        .disabled(!model.canTap)
        .accessibilityLabel(Text("Add this point"))
        // How many points are tapped, so VoiceOver (and the UI test) hears each tap land.
        .accessibilityValue(Text(WalkthroughText.pointCount(model.markers.count)))
        .accessibilityIdentifier("walkthrough.tap")
        Button("Done") { model.finishWalking() }
          .buttonStyle(.chapter(.filledOnDark))
          .disabled(!model.canFinishWalking)
          .accessibilityIdentifier("walkthrough.done")
      }
    }

    // MARK: Room card

    private var roomCard: some View {
      VStack(alignment: .leading, spacing: 12) {
        Text(model.rooms.isEmpty ? "First room" : "Next room")
          .chapterTextStyle(.footnoteEmphasis)
          .foregroundStyle(ChapterTheme.Color.muted)
        TextField(
          text: $model.roomName,
          prompt: Text(model.nextRoomPlaceholder).foregroundStyle(ChapterTheme.Color.muted)
        ) {
          Text("Room name")
        }
        .font(ChapterTheme.Font.body)
        .foregroundStyle(ChapterTheme.Color.ink)
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(ChapterTheme.Color.ground, in: RoundedRectangle(cornerRadius: 10))
        .submitLabel(.done)
        .accessibilityIdentifier("walkthrough.room.name")
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(RoomType.allCases, id: \.self) { type in
              ChoiceChip(SketchText.roomTypeTitle(type), isSelected: model.roomType == type, kind: .subject) {
                model.roomType = model.roomType == type ? nil : type
              }
              .accessibilityIdentifier("walkthrough.room.type.\(type.rawValue)")
            }
          }
        }
        ChapterSegmented(
          "How to tap it", selection: $model.roomMethod,
          options: [
            .init(WalkthroughMethod.corners, "Tap the corners", accessibilityIdentifier: "walkthrough.room.method.corners"),
            .init(.walls, "Tap each wall", accessibilityIdentifier: "walkthrough.room.method.walls"),
          ])
        Text(
          model.roomMethod == .corners
            ? "Tap each floor corner in order and close the room on the first one."
            : "Furniture in a corner? Tap two points along the base of each wall, in order.")
          .chapterTextStyle(.footnote)
          .foregroundStyle(ChapterTheme.Color.muted)
          .fixedSize(horizontal: false, vertical: true)
        Button("Start this room") { model.startRoom() }
          .buttonStyle(.chapter(.primary))
          .accessibilityIdentifier("walkthrough.room.start")
        if model.canFinishWalking {
          Button("Done walking") { model.finishWalking() }
            .buttonStyle(.chapter(.tinted))
            .accessibilityIdentifier("walkthrough.room.done")
        }
      }
      .padding(16)
      .background(ChapterTheme.Color.surface, in: RoundedRectangle(cornerRadius: 16))
      .padding(.horizontal, ChapterTheme.Metric.screenPadding)
      .environment(\.colorScheme, .light)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("walkthrough.room.card")
    }
  }

  /// The live 2D outline (spec F15 2): every room's corners so far, the current room's open
  /// wall to the reticle, and each wall's length in the capture's units; plan up is −Z.
  struct WalkthroughOutlineView: View {
    let rooms: [WalkthroughOutlineRoom]
    let reticle: Vec3?
    let units: DisplayUnitSystem

    var body: some View {
      Canvas { context, size in
        var points = rooms.flatMap(\.corners)
        if let reticle, rooms.last?.isCurrent == true { points.append(reticle) }
        guard let frame = OutlineFrame(points: points, size: size) else { return }
        for room in rooms where room.corners.count >= 2 {
          var path = Path()
          path.move(to: frame.point(room.corners[0]))
          for corner in room.corners.dropFirst() { path.addLine(to: frame.point(corner)) }
          if room.isClosed { path.closeSubpath() }
          let colour = room.isCurrent ? ChapterTheme.Color.surface : ChapterTheme.Color.onDarkCaption
          context.stroke(path, with: .color(colour), lineWidth: 2)
          // Each wall's length just inside the room, so the labels stay in the box.
          let lengths = WalkthroughModel.wallLengths(room.corners, closed: room.isClosed)
          let centre = frame.centre(of: room.corners)
          for (index, metres) in lengths.enumerated() {
            let a = frame.point(room.corners[index])
            let b = frame.point(room.corners[(index + 1) % room.corners.count])
            let midX: Double = (Double(a.x) + Double(b.x)) / 2
            let midY: Double = (Double(a.y) + Double(b.y)) / 2
            let dx: Double = Double(centre.x) - midX
            let dy: Double = Double(centre.y) - midY
            let text = Text(WalkthroughText.length(metres * 1000, units: units))
              .font(ChapterTheme.Font.caption)
              .foregroundStyle(ChapterTheme.Color.surface)
            // The label's edge on the wall's inner side, 4 pt in: a side wall's label starts
            // (or ends) at the wall, a top or bottom wall's label hangs under (or sits over) it.
            let sideways = abs(dx) > abs(dy)
            let anchor: UnitPoint =
              sideways ? (dx > 0 ? .leading : .trailing) : (dy > 0 ? .top : .bottom)
            let stepX: Double = sideways ? (dx > 0 ? 4 : -4) : 0
            let stepY: Double = sideways ? 0 : (dy > 0 ? 4 : -4)
            context.draw(text, at: CGPoint(x: midX + stepX, y: midY + stepY), anchor: anchor)
          }
        }
        if let reticle, let current = rooms.last, current.isCurrent, !current.isClosed,
          let last = current.corners.last
        {
          var path = Path()
          path.move(to: frame.point(last))
          path.addLine(to: frame.point(reticle))
          context.stroke(
            path, with: .color(ChapterTheme.Color.onDarkCaption),
            style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        for room in rooms {
          for corner in room.corners {
            let p = frame.point(corner)
            context.fill(
              Path(ellipseIn: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)),
              with: .color(ChapterTheme.Color.surface))
          }
        }
      }
      .padding(8)
      .background(ChapterTheme.Color.onDarkPill, in: RoundedRectangle(cornerRadius: 12))
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Text(accessibilityText))
      .accessibilityIdentifier("walkthrough.outline")
    }

    private var accessibilityText: String {
      guard let room = rooms.last else { return "Outline: nothing tapped yet" }
      let lengths = WalkthroughModel.wallLengths(room.corners, closed: room.isClosed)
        .map { WalkthroughText.length($0 * 1000, units: units) }
      return "Outline of \(room.label): \(room.corners.count) corners"
        + (lengths.isEmpty ? "" : ", walls " + lengths.joined(separator: ", "))
    }

    /// Plan metres to canvas points, scale to fit, centred; −Z up.
    struct OutlineFrame {
      let scale: Double
      let originX: Double
      let originY: Double
      let minX: Double
      let minZ: Double

      init?(points: [Vec3], size: CGSize) {
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
          let minZ = points.map(\.z).min(), let maxZ = points.map(\.z).max()
        else { return nil }
        let width: Double = max(maxX - minX, 1.0)
        let depth: Double = max(maxZ - minZ, 1.0)
        let availableWidth = Double(size.width) - 8
        let availableHeight = Double(size.height) - 8
        let scale: Double = min(availableWidth / width, availableHeight / depth)
        guard scale.isFinite, scale > 0 else { return nil }
        let usedWidth: Double = (maxX - minX) * scale
        let usedDepth: Double = (maxZ - minZ) * scale
        self.scale = scale
        self.originX = (Double(size.width) - usedWidth) / 2
        self.originY = (Double(size.height) - usedDepth) / 2
        self.minX = minX
        self.minZ = minZ
      }

      /// The middle of a room's corners on the canvas.
      func centre(of corners: [Vec3]) -> CGPoint {
        let points = corners.map(point)
        let count = Double(max(points.count, 1))
        let x: Double = points.reduce(0.0) { $0 + Double($1.x) } / count
        let y: Double = points.reduce(0.0) { $0 + Double($1.y) } / count
        return CGPoint(x: x, y: y)
      }

      func point(_ v: Vec3) -> CGPoint {
        let x: Double = originX + (v.x - minX) * scale
        // −Z (the way the phone faced when the walk started) is up.
        let y: Double = originY + (v.z - minZ) * scale
        return CGPoint(x: x, y: y)
      }
    }
  }
#endif

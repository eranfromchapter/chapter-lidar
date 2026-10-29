#if canImport(SwiftUI) && os(iOS)
  import CaptureContract
  import ChapterUI
  import PhotosUI
  import SketchEntry
  import SketchReading
  import SwiftUI
  import UIKit
  import UniformTypeIdentifiers

  // "Photograph a sketch" (spec F16 2): the photo (step 3 of 5), "Reading your sketch…" or why
  // it could not be read, the one length (step 4 of 5) and Check with the 3D preview (step 5
  // of 5). Each screen reads `SketchPhotoModel` and calls its methods; the host pushes the
  // screens from `model.phase`. Identifiers `sketchPhoto.*`.

  /// The bytes the operator chose, kept as they are when they are a JPEG, PNG, HEIC or PDF (by
  /// content, else by the file's extension); any other image is re-encoded as JPEG; nil for
  /// anything else.
  enum SketchImageIntake {
    static func selection(_ data: Data, fallbackExtension: String) -> SketchImageSelection? {
      if let selection = SketchImageSelection(data: data) { return selection }
      if let format = SketchImageFormat(fileExtension: fallbackExtension) {
        return SketchImageSelection(data: data, format: format)
      }
      if let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.92) {
        return SketchImageSelection(data: jpeg, format: .jpeg)
      }
      return nil
    }
  }

  // MARK: Step 3: the photo

  /// Step 3 of 5, Photograph the sketch: the camera, Photos or a file. Choosing one starts the
  /// reading (`model.start`), which the host shows as the next screen.
  public struct SketchPhotoSourceScreen: View {
    let model: SketchPhotoModel
    let options: SketchSourceOptions
    @State private var showsCamera = false
    @State private var showsPhotos = false
    @State private var showsFiles = false
    @State private var photoItem: PhotosPickerItem?
    @State private var problem: String?
    @State private var isLoading = false

    public init(model: SketchPhotoModel, options: SketchSourceOptions = SketchSourceOptions()) {
      self.model = model
      self.options = options
    }

    public var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: ChapterTheme.Metric.sectionGapCompact) {
          if let notice = model.notice {
            Banner(icon: .partly, text: notice)
              .accessibilityIdentifier("sketchPhoto.notice")
          }
          if let problem {
            Banner(icon: .blocked, text: problem)
              .accessibilityIdentifier("sketchPhoto.source.problem")
          }
          ChapterSection(
            header: "\(model.floorLabel) \u{00B7} the sketch",
            footer:
              "Photograph the whole drawing from above, flat and in good light. Claude reads the "
              + "rooms, doors, windows, furniture and any written dimensions. The photo is kept "
              + "in the package as taken."
          ) {
            NavigationRow(
              title: "Take a photo", subtitle: hasCamera ? "The phone's camera" : "No camera on this device"
            ) {
              takePhoto()
            }
            .disabled(!hasCamera || isLoading)
            .accessibilityIdentifier("sketchPhoto.source.camera")
            NavigationRow(title: "Choose from Photos", subtitle: "A photo or scan already on this phone") {
              showsPhotos = true
            }
            .disabled(isLoading)
            .accessibilityIdentifier("sketchPhoto.source.photos")
            NavigationRow(title: "Import a file", subtitle: "An image or PDF from Files") {
              showsFiles = true
            }
            .disabled(isLoading)
            .accessibilityIdentifier("sketchPhoto.source.file")
          }
        }
        .sketchContent()
      }
      .navigationTitle(SketchPhotoText.sourceTitle)
      .navigationBarTitleDisplayMode(.large)
      .sketchNavigationCaption(options.caption)
      .chapterBackChevronOnly()
      .chapterScreenBackground()
      .fullScreenCover(isPresented: $showsCamera) {
        SketchCameraPicker { data in
          showsCamera = false
          if let data { accept(data, kind: .handSketch, fallbackExtension: "jpg") }
        }
        .ignoresSafeArea()
      }
      .photosPicker(isPresented: $showsPhotos, selection: $photoItem, matching: .images)
      .onChange(of: photoItem) { _, item in
        guard let item else { return }
        photoItem = nil
        loadPhoto(item)
      }
      .fileImporter(
        isPresented: $showsFiles, allowedContentTypes: [.image, .pdf], allowsMultipleSelection: false
      ) { result in
        switch result {
        case .success(let urls):
          if let url = urls.first { importFile(url) }
        case .failure(let error):
          problem = "The file could not be opened: \(error.localizedDescription)"
        }
      }
    }

    private var hasCamera: Bool {
      options.fixedPhoto != nil || UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    private func takePhoto() {
      if let fixed = options.fixedPhoto {
        isLoading = true
        Task {
          defer { isLoading = false }
          do {
            accept(try await fixed(), kind: .handSketch, fallbackExtension: "jpg")
          } catch {
            problem = "The photo could not be taken: \(error.localizedDescription)"
          }
        }
      } else {
        showsCamera = true
      }
    }

    private func loadPhoto(_ item: PhotosPickerItem) {
      isLoading = true
      Task {
        defer { isLoading = false }
        do {
          guard let data = try await item.loadTransferable(type: Data.self) else {
            problem = "The photo could not be read."
            return
          }
          let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
          accept(data, kind: .handSketch, fallbackExtension: ext)
        } catch {
          problem = "The photo could not be read: \(error.localizedDescription)"
        }
      }
    }

    private func importFile(_ url: URL) {
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      do {
        accept(try Data(contentsOf: url), kind: .existingPlan, fallbackExtension: url.pathExtension)
      } catch {
        problem = "The file could not be read: \(error.localizedDescription)"
      }
    }

    private func accept(_ data: Data, kind: SketchSourceKind, fallbackExtension: String) {
      guard let selection = SketchImageIntake.selection(data, fallbackExtension: fallbackExtension)
      else {
        problem = "Choose a JPEG, PNG or HEIC image, or a PDF."
        return
      }
      problem = nil
      model.start(selection, kind: kind)
    }
  }

  // MARK: Reading, or why not

  /// Step 4 of 5 while Claude reads the photo: the photo, a spinner, "Reading your sketch…"
  /// and Cancel. When the photo is not a floor plan or could not be read: why, "Retake the
  /// photo" and "Enter it by hand" (`onEnterByHand`: the F14 screens, with this photo).
  public struct SketchPhotoReadingScreen: View {
    let model: SketchPhotoModel
    let caption: String
    let onEnterByHand: @MainActor () -> Void

    public init(
      model: SketchPhotoModel, caption: String = "Step 4 of 5",
      onEnterByHand: @escaping @MainActor () -> Void
    ) {
      self.model = model
      self.caption = caption
      self.onEnterByHand = onEnterByHand
    }

    private var isProblem: Bool { model.phase == .problem }

    public var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: ChapterTheme.Metric.sectionGapCompact) {
          if let notice = model.notice {
            Banner(icon: .partly, text: notice)
              .accessibilityIdentifier("sketchPhoto.notice")
          }
          photo
          if isProblem {
            problemSection
          } else {
            readingSection
          }
        }
        .sketchContent()
      }
      .navigationTitle(isProblem ? "Not read" : "Reading")
      .navigationBarTitleDisplayMode(.large)
      .sketchNavigationCaption(caption)
      .chapterBackChevronOnly()
      .chapterScreenBackground()
      .chapterActionBar {
        if isProblem {
          VStack(spacing: ChapterTheme.Metric.rowGap) {
            Button(SketchPhotoText.retake) { model.retake() }
              .buttonStyle(.chapter(.primary))
              .accessibilityIdentifier("sketchPhoto.retake")
            Button(SketchPhotoText.enterByHand) { onEnterByHand() }
              .buttonStyle(.chapter(.tinted))
              .accessibilityIdentifier("sketchPhoto.enterByHand")
          }
        } else {
          Button("Cancel") { model.cancelReading() }
            .buttonStyle(.chapter(.tinted))
            .accessibilityIdentifier("sketchPhoto.cancel")
        }
      }
    }

    @ViewBuilder
    private var photo: some View {
      if let selection = model.image, let image = SketchImageRendering.image(for: selection) {
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
          .frame(maxWidth: .infinity, maxHeight: 260)
          .background(ChapterTheme.Color.surface)
          .clipShape(RoundedRectangle(cornerRadius: ChapterTheme.Metric.cardRadius))
          .overlay(
            RoundedRectangle(cornerRadius: ChapterTheme.Metric.cardRadius)
              .strokeBorder(ChapterTheme.Color.line, lineWidth: ChapterTheme.Metric.cardBorder))
          .opacity(isProblem ? 1 : 0.85)
          .accessibilityLabel("The sketch photo")
          .accessibilityIdentifier("sketchPhoto.photo")
      }
    }

    private var readingSection: some View {
      ChapterCard {
        HStack(alignment: .top, spacing: ChapterTheme.Metric.rowGap) {
          ProgressView()
            .tint(ChapterTheme.Color.muted)
            .padding(.top, 2)
          VStack(alignment: .leading, spacing: ChapterTheme.Metric.rowTitleGap) {
            Text(SketchPhotoText.readingTitle)
              .chapterTextStyle(.bodyEmphasis)
              .foregroundStyle(ChapterTheme.Color.ink)
              .accessibilityIdentifier("sketchPhoto.reading")
            Text(SketchPhotoText.readingSubtitle)
              .chapterTextStyle(.footnote)
              .foregroundStyle(ChapterTheme.Color.muted)
              .fixedSize(horizontal: false, vertical: true)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, ChapterTheme.Metric.rowPadding)
        .padding(.vertical, 12)
      }
    }

    private var problemSection: some View {
      VStack(alignment: .leading, spacing: ChapterTheme.Metric.sectionGapCompact) {
        Text(model.problemIsNotAPlan ? SketchPhotoText.notAPlanTitle : SketchPhotoText.unreadableTitle)
          .chapterTextStyle(.bodyEmphasis)
          .foregroundStyle(ChapterTheme.Color.ink)
          .padding(.horizontal, ChapterTheme.Metric.sectionInset)
        Banner(icon: .blocked, text: model.problem ?? "")
          .accessibilityIdentifier("sketchPhoto.problem")
        Text(
          "Retake the photo of the whole drawing, or enter the walls, doors and windows by hand "
            + "from the sketch.")
          .chapterTextStyle(.footnote)
          .foregroundStyle(ChapterTheme.Color.muted)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.horizontal, ChapterTheme.Metric.sectionInset)
      }
    }
  }

  // MARK: Step 4: one length

  /// Step 4 of 5, One length (only when the sketch has no written dimensions): the plan as
  /// drawn, a tap selects a wall (or its chip under the plan), and the field takes its length
  /// in the capture's units. Continue converts the reading and opens Check.
  public struct SketchPhotoLengthScreen: View {
    @Bindable var model: SketchPhotoModel
    let caption: String

    public init(model: SketchPhotoModel, caption: String = "Step 4 of 5") {
      self.model = model
      self.caption = caption
    }

    public var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: ChapterTheme.Metric.sectionGapCompact) {
          if let notice = model.notice {
            Banner(icon: .partly, text: notice)
              .accessibilityIdentifier("sketchPhoto.notice")
          }
          SketchDrawnPlanCanvas(
            walls: model.drawnWalls, selectedId: model.selectedWallId,
            select: { model.selectWall($0) }
          )
          .frame(height: 260)
          .frame(maxWidth: .infinity)
          .background(ChapterTheme.Color.surface)
          .clipShape(RoundedRectangle(cornerRadius: ChapterTheme.Metric.cardRadius))
          .overlay(
            RoundedRectangle(cornerRadius: ChapterTheme.Metric.cardRadius)
              .strokeBorder(ChapterTheme.Color.line, lineWidth: ChapterTheme.Metric.cardBorder))
          ChapterSection(header: SketchPhotoText.lengthQuestion, footer: SketchPhotoText.lengthFooter) {
            SketchChipRow(
              label: "Walls",
              options: model.drawnWalls.map { wall in
                .init(
                  value: wall.id, title: Self.title(of: wall),
                  identifier: "sketchPhoto.wall.\(wall.id)")
              },
              selection: Binding(get: { model.selectedWallId }, set: { if let id = $0 { model.selectWall(id) } }))
            SketchLengthRow(
              title: model.selectedWall.map(Self.title(of:)) ?? "Length", field: $model.length,
              identifier: "sketchPhoto.length", showsMeasuredChip: false)
          }
        }
        .sketchContent()
      }
      .scrollDismissesKeyboard(.interactively)
      .navigationTitle(SketchPhotoText.lengthTitle)
      .navigationBarTitleDisplayMode(.large)
      .sketchNavigationCaption(caption)
      .chapterBackChevronOnly()
      .chapterScreenBackground()
      .chapterActionBar {
        Button(model.lengthContinueTitle) { model.continueFromLength() }
          .buttonStyle(.chapter(.primary))
          .disabled(model.lengthBlocker != nil)
          .accessibilityIdentifier("sketchPhoto.length.continue")
      }
    }

    /// "Bedroom · Wall 1".
    static func title(of wall: DrawnWall) -> String {
      "\(wall.roomLabel) \u{00B7} \(SketchText.wallTitle(index: wall.wallIndex))"
    }
  }

  /// The walls as Claude read them, in drawing coordinates (x right, y down) fitted to the
  /// canvas: every wall a line, the selected one thick in the ready colour, wall numbers at the
  /// middles. A tap selects the nearest wall within 32 pt.
  struct SketchDrawnPlanCanvas: View {
    let walls: [DrawnWall]
    let selectedId: String?
    let select: (String) -> Void

    var body: some View {
      GeometryReader { proxy in
        let frame = Self.frame(walls, in: proxy.size)
        Canvas { context, _ in
          guard let frame else { return }
          for wall in walls where wall.id != selectedId {
            var path = Path()
            path.move(to: frame.point(wall.start))
            path.addLine(to: frame.point(wall.end))
            context.stroke(path, with: .color(ChapterTheme.Color.ink), style: StrokeStyle(lineWidth: 3, lineCap: .round))
          }
          if let wall = walls.first(where: { $0.id == selectedId }) {
            var path = Path()
            path.move(to: frame.point(wall.start))
            path.addLine(to: frame.point(wall.end))
            context.stroke(path, with: .color(ChapterTheme.Color.ready), style: StrokeStyle(lineWidth: 8, lineCap: .round))
          }
          // Each wall's number just outside its middle (away from its room's centre).
          for wall in walls {
            let middle = frame.point(
              SketchInterpretation.Point(
                x: (wall.start.x + wall.end.x) / 2, y: (wall.start.y + wall.end.y) / 2))
            let centre = frame.point(Self.centre(of: wall.roomIndex, in: walls))
            let dx: Double = Double(middle.x - centre.x)
            let dy: Double = Double(middle.y - centre.y)
            let length: Double = max((dx * dx + dy * dy).squareRoot(), 1)
            let at = CGPoint(x: Double(middle.x) + dx / length * 13, y: Double(middle.y) + dy / length * 13)
            let label = Text("\(wall.wallIndex + 1)")
              .font(ChapterTheme.Font.footnoteEmphasis)
              .foregroundStyle(wall.id == selectedId ? ChapterTheme.Color.ready : ChapterTheme.Color.muted)
            context.draw(label, at: at, anchor: .center)
          }
        }
        .contentShape(Rectangle())
        .onTapGesture { location in
          guard let frame, let id = Self.nearest(walls, to: location, frame: frame) else { return }
          select(id)
        }
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Text("The sketch as read: \(walls.count) walls"))
      .accessibilityAddTraits(.isImage)
      .accessibilityIdentifier("sketchPhoto.plan")
    }

    /// The mean of a room's wall starts, in drawing coordinates.
    static func centre(of room: Int, in walls: [DrawnWall]) -> SketchInterpretation.Point {
      let starts = walls.filter { $0.roomIndex == room }.map(\.start)
      let count = Double(max(starts.count, 1))
      let x: Double = starts.map(\.x).reduce(0, +) / count
      let y: Double = starts.map(\.y).reduce(0, +) / count
      return SketchInterpretation.Point(x: x, y: y)
    }

    struct Frame {
      let scale: Double
      let offsetX: Double
      let offsetY: Double

      func point(_ p: SketchInterpretation.Point) -> CGPoint {
        CGPoint(x: offsetX + p.x * scale, y: offsetY + p.y * scale)
      }
    }

    static func frame(_ walls: [DrawnWall], in size: CGSize) -> Frame? {
      let points = walls.flatMap { [$0.start, $0.end] }
      guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
        let minY = points.map(\.y).min(), let maxY = points.map(\.y).max()
      else { return nil }
      let margin = 28.0
      let width: Double = max(maxX - minX, 1)
      let height: Double = max(maxY - minY, 1)
      let availableWidth: Double = Double(size.width) - 2 * margin
      let availableHeight: Double = Double(size.height) - 2 * margin
      let scale: Double = min(availableWidth / width, availableHeight / height)
      guard scale.isFinite, scale > 0 else { return nil }
      let usedWidth: Double = width * scale
      let usedHeight: Double = height * scale
      let offsetX: Double = (Double(size.width) - usedWidth) / 2 - minX * scale
      let offsetY: Double = (Double(size.height) - usedHeight) / 2 - minY * scale
      return Frame(scale: scale, offsetX: offsetX, offsetY: offsetY)
    }

    /// The wall nearest to `location` (canvas points), within 32 pt.
    static func nearest(_ walls: [DrawnWall], to location: CGPoint, frame: Frame) -> String? {
      var best: (id: String, distance: Double)?
      let px = Double(location.x)
      let py = Double(location.y)
      for wall in walls {
        let a = frame.point(wall.start)
        let b = frame.point(wall.end)
        let ax = Double(a.x)
        let ay = Double(a.y)
        let dx: Double = Double(b.x) - ax
        let dy: Double = Double(b.y) - ay
        let lengthSquared: Double = dx * dx + dy * dy
        var t: Double = 0
        if lengthSquared > 0 {
          let along: Double = (px - ax) * dx + (py - ay) * dy
          t = min(max(along / lengthSquared, 0), 1)
        }
        let cx: Double = ax + t * dx - px
        let cy: Double = ay + t * dy - py
        let distance: Double = (cx * cx + cy * cy).squareRoot()
        if distance <= 32, distance < (best?.distance ?? .infinity) {
          best = (wall.id, distance)
        }
      }
      return best?.id
    }
  }

  // MARK: Step 5: Check

  /// Step 5 of 5, Check: the F14 Check screen with the 3D preview on top (the model extruded
  /// by `SketchMesh`), the plan under it, the converter's notes (scale, estimates) before the
  /// solver's, Complete or Limited, and Finish floor (`onFinish`).
  public struct SketchPhotoCheckScreen: View {
    let model: SketchPhotoModel
    let caption: String
    let onFinish: @MainActor () -> Void

    public init(
      model: SketchPhotoModel, caption: String = "Step 5 of 5",
      onFinish: @escaping @MainActor () -> Void
    ) {
      self.model = model
      self.caption = caption
      self.onFinish = onFinish
    }

    public var body: some View {
      SketchCheckView(
        result: model.result, solveError: model.solveError, leadingNotes: model.leadingNotes,
        completenessWord: model.completenessWord, caption: caption,
        isFinishing: model.isFinishing, canFinish: model.canFinish,
        mesh3D: model.result.flatMap { SketchModel3DView.mesh(of: $0.model) }, onFinish: onFinish)
    }
  }
#endif

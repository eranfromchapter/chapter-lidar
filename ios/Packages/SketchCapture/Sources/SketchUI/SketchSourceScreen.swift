#if canImport(SwiftUI) && os(iOS)
  import CaptureContract
  import ChapterUI
  import PhotosUI
  import SketchEntry
  import SwiftUI
  import UIKit
  import UniformTypeIdentifiers

  /// What the host gives the source screen besides the model.
  public struct SketchSourceOptions {
    /// Stands in for the camera (UI tests, a simulator): "Take a photo" returns these bytes.
    /// Nil: the phone's camera, when it has one.
    public var fixedPhoto: (@Sendable () async throws -> Data)?
    /// The right-hand caption: "Step 2 of 4", or the project title when adding a floor.
    public var caption: String

    public init(fixedPhoto: (@Sendable () async throws -> Data)? = nil, caption: String = "Step 2 of 4") {
      self.fixedPhoto = fixedPhoto
      self.caption = caption
    }
  }

  /// Step 2 of 4, What are you drawing from? (spec F14 2.1, 2.4): a photo of the sketch
  /// (camera), an image from Photos, an imported image or PDF, or no sketch at all; whether it
  /// is a hand sketch or an existing plan; then the floor or area name, what is drawn (one room
  /// or the whole floor) and the units, as step 2 of a scan asks them. Continue moves the model
  /// to the rooms (`model.step == .rooms`), which the host pushes.
  public struct SketchSourceScreen: View {
    @Bindable var model: SketchEntryModel
    let options: SketchSourceOptions
    @State private var showsCamera = false
    @State private var showsPhotos = false
    @State private var showsFiles = false
    @State private var photoItem: PhotosPickerItem?
    @State private var problem: String?
    @State private var isLoading = false

    public init(model: SketchEntryModel, options: SketchSourceOptions = SketchSourceOptions()) {
      self.model = model
      self.options = options
    }

    public var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: ChapterTheme.Metric.sectionGapCompact) {
          if let problem {
            Banner(icon: .blocked, text: problem)
              .accessibilityIdentifier("sketch.source.problem")
          }
          sourceSection
          floorSection
        }
        .sketchContent()
      }
      .scrollDismissesKeyboard(.interactively)
      .navigationTitle("What are you drawing from?")
      .navigationBarTitleDisplayMode(.large)
      .sketchNavigationCaption(options.caption)
      .chapterBackChevronOnly()
      .chapterScreenBackground()
      .chapterActionBar {
        Button(model.sourceContinueTitle) { model.continueToRooms() }
          .buttonStyle(.chapter(.primary))
          .disabled(!model.canContinueToRooms || isLoading)
          .accessibilityIdentifier("sketch.continue")
      }
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

    // MARK: Sketch

    private var hasCamera: Bool {
      options.fixedPhoto != nil || UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    private var sourceSection: some View {
      ChapterSection(
        header: "Sketch",
        footer:
          "The sketch is kept as the reference original next to the measurements. Nothing is "
          + "traced from it: the walls, doors and windows are what you enter."
      ) {
        if let image = model.image {
          chosenImage(image)
        }
        NavigationRow(
          title: "Take a photo", subtitle: hasCamera ? "The phone's camera" : "No camera on this device"
        ) {
          takePhoto()
        }
        .disabled(!hasCamera || isLoading)
        .accessibilityIdentifier("sketch.source.camera")
        NavigationRow(title: "Choose from Photos", subtitle: "A photo or scan already on this phone") {
          showsPhotos = true
        }
        .disabled(isLoading)
        .accessibilityIdentifier("sketch.source.photos")
        NavigationRow(title: "Import a file", subtitle: "An image or PDF from Files") {
          showsFiles = true
        }
        .disabled(isLoading)
        .accessibilityIdentifier("sketch.source.file")
        NavigationRow(
          title: "No sketch", subtitle: "Measurements only",
          status: model.image == nil ? RowStatus(.done, "Chosen") : nil
        ) {
          model.setImage(nil)
          problem = nil
        }
        .accessibilityIdentifier("sketch.source.none")
      }
    }

    /// The chosen image: a thumbnail, its kind and the hand sketch / existing plan choice.
    private func chosenImage(_ image: SketchImageSelection) -> some View {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: ChapterTheme.Metric.rowGap) {
          Group {
            if let drawn = SketchImageRendering.image(for: image) {
              Image(uiImage: drawn).resizable().scaledToFill()
            } else {
              ChapterTheme.Color.nude
            }
          }
          .frame(width: 64, height: 64)
          .clipShape(RoundedRectangle(cornerRadius: 8))
          .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: ChapterTheme.Metric.rowTitleGap) {
            Text(image.fileName)
              .chapterTextStyle(.body)
              .foregroundStyle(ChapterTheme.Color.ink)
            Text("\(image.format.rawValue.uppercased()) \u{00B7} \(byteText(image.data.count))")
              .chapterTextStyle(.footnote)
              .foregroundStyle(ChapterTheme.Color.muted)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sketch.source.chosen")
        ChapterSegmented(
          "What it is",
          selection: Binding(get: { model.sourceKind }, set: { model.setSourceKind($0) }),
          options: [
            .init(SketchSourceKind.handSketch, "Hand sketch", accessibilityIdentifier: "sketch.kind.handSketch"),
            .init(.existingPlan, "Existing plan", accessibilityIdentifier: "sketch.kind.existingPlan"),
          ]
        )
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
      }
      .padding(.horizontal, ChapterTheme.Metric.rowPadding)
      .padding(.vertical, 10)
    }

    private func byteText(_ count: Int) -> String {
      count >= 1_000_000
        ? String(format: "%.1f MB", Double(count) / 1_000_000)
        : "\(max(count / 1000, 1)) KB"
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
        let data = try Data(contentsOf: url)
        accept(data, kind: .existingPlan, fallbackExtension: url.pathExtension)
      } catch {
        problem = "The file could not be read: \(error.localizedDescription)"
      }
    }

    /// Keeps the bytes as they are when they are a JPEG, PNG, HEIC or PDF (by content, else by
    /// the file's extension); any other image is re-encoded as JPEG; anything else is refused.
    private func accept(_ data: Data, kind: SketchSourceKind, fallbackExtension: String) {
      problem = nil
      if let selection = SketchImageSelection(data: data) {
        model.setImage(selection, kind: selection.format == .pdf ? .existingPlan : kind)
      } else if let format = SketchImageFormat(fileExtension: fallbackExtension) {
        model.setImage(SketchImageSelection(data: data, format: format), kind: kind)
      } else if let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.92) {
        model.setImage(SketchImageSelection(data: jpeg, format: .jpeg), kind: kind)
      } else {
        problem = "Choose a JPEG, PNG or HEIC image, or a PDF."
      }
    }

    // MARK: Floor or area

    private var floorSection: some View {
      ChapterSection(
        header: "Floor or area",
        footer: "Lengths are typed in feet and inches (13' 1.5\") or in millimetres."
      ) {
        TextFieldRow(
          label: "Name", text: $model.floorLabel, prompt: "Floor 1", accessibilityLabel: "Floor or area"
        )
        .submitLabel(.done)
        .accessibilityIdentifier("sketch.floorName")
        SketchSegmentedRow(
          label: "What you are drawing", selection: $model.mode,
          options: [
            .init(CaptureMode.room, SketchText.modeTitle(.room), accessibilityIdentifier: "sketch.mode.room"),
            .init(.floor, SketchText.modeTitle(.floor), accessibilityIdentifier: "sketch.mode.floor"),
          ])
        SketchSegmentedRow(
          label: "Units",
          selection: Binding<DisplayUnitSystem?>(
            get: { model.displayUnits }, set: { if let value = $0 { model.setDisplayUnits(value) } }),
          options: [
            .init(DisplayUnitSystem.imperial, "Feet and inches", accessibilityIdentifier: "sketch.units.imperial"),
            .init(.metric, "Millimetres", accessibilityIdentifier: "sketch.units.metric"),
          ])
      }
    }
  }
#endif

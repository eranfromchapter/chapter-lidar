#if canImport(SwiftUI) && canImport(UIKit)
  import CaptureContract
  import ChapterUI
  import FieldRules
  import PhotoStore
  import SwiftUI
  import UIKit

  /// "Label a photo" (design v2, artboard 2d-1; phone-field §3.2): the photo just taken with its
  /// time, then Room (stays selected for the next photo), Looking toward (pre-filled from the
  /// compass), Subject and the strip of the room's photos; "Save and take next" and "Done with
  /// photos" stay pinned at the bottom.
  ///
  /// Pushed by the app with an inline navigation bar: the title is `Photo 14 · Floor 1`, the
  /// trailing caption the photo's format, and Back asks before the unsaved photo is thrown away
  /// (`Discard this photo?`, then the viewfinder). `More` opens the room picker, which also leads
  /// to "Rename rooms" when `onRenameRooms` is given.
  public struct PhotoLabelingView: View {
    @Bindable var model: PhotoLabelingModel
    let onDone: (() -> Void)?
    let onRenameRooms: (() -> Void)?
    @State private var showsRoomPicker = false
    @State private var renameAfterPicker = false
    @State private var confirmsDiscard = false

    /// - Parameters:
    ///   - onDone: "Done with photos" after the photo was saved (the step closes).
    ///   - onRenameRooms: adds "Rename rooms" to the room picker.
    public init(
      model: PhotoLabelingModel, onDone: (() -> Void)? = nil, onRenameRooms: (() -> Void)? = nil
    ) {
      self.model = model
      self.onDone = onDone
      self.onRenameRooms = onRenameRooms
    }

    public var body: some View {
      // The labels scroll and the actions stay pinned: the buttons must never be pushed off
      // screen by long room names or large text.
      ScrollView {
        VStack(alignment: .leading, spacing: FieldMetric.labelBlockGap) {
          photo
          roomBlock
          directionBlock
          subjectBlock
          PhotoStripView(strip: model.strip, store: model.store)
        }
        .padding(.horizontal, FieldTheme.Metric.screenPadding)
        .padding(.bottom, FieldTheme.Metric.screenPadding)
        .chapterContentWidth()
      }
      .scrollDismissesKeyboard(.interactively)
      .navigationBarTitleDisplayMode(.inline)
      .navigationBarBackButtonHidden(true)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          InterceptedBackButton { confirmsDiscard = true }
        }
        ToolbarItem(placement: .principal) {
          Text(model.title)
            .chapterTextStyle(.navTitle)
            .foregroundStyle(FieldTheme.Color.ink)
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("photo.labelTitle")
        }
        PlainToolbarItem(placement: .topBarTrailing) {
          Text(model.pendingFormat?.rawValue.uppercased() ?? "")
            .chapterTextStyle(.footnote)
            .foregroundStyle(FieldTheme.Color.muted)
            .frame(width: 44, alignment: .trailing)
            .accessibilityLabel(model.pendingFormat.map { "\($0.rawValue.uppercased()) photo" } ?? "")
            .accessibilityIdentifier("photo.format")
        }
      }
      .chapterScreenBackground()
      .safeAreaInset(edge: .bottom, spacing: 0) { actions }
      .sheet(
        isPresented: $showsRoomPicker,
        onDismiss: {
          guard renameAfterPicker else { return }
          renameAfterPicker = false
          onRenameRooms?()
        }
      ) {
        // "Rename rooms" closes the picker first; the rename sheet opens once it is gone.
        RoomPickerSheet(
          model: model,
          onRenameRooms: onRenameRooms == nil
            ? nil
            : {
              renameAfterPicker = true
              showsRoomPicker = false
            })
      }
      .alert("Discard this photo?", isPresented: $confirmsDiscard) {
        Button("Keep", role: .cancel) {}
        Button("Discard", role: .destructive) { model.discardPending() }
      } message: {
        Text("It is not saved yet. You can take it again.")
      }
    }

    // MARK: Photo

    private var photo: some View {
      FieldTheme.Color.line
        .frame(height: FieldMetric.photoHeight)
        .frame(maxWidth: .infinity)
        .overlay {
          if let data = model.pendingOriginal, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill()
          }
        }
        .clipShape(RoundedRectangle(cornerRadius: FieldMetric.photoRadius))
        .overlay(alignment: .bottomLeading) {
          if let time = model.takenAtText {
            Text("\(time) \u{00B7} original kept")
              .chapterTextStyle(.mono11)
              .foregroundStyle(FieldTheme.Color.surface)
              .padding(.vertical, 4)
              .padding(.horizontal, 8)
              .background(FieldTheme.Color.photoPill, in: RoundedRectangle(cornerRadius: 6))
              .padding(.leading, FieldMetric.photoPillInset.width)
              .padding(.bottom, FieldMetric.photoPillInset.height)
          }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
          model.takenAtText.map { "Photo just taken, \($0), original kept" } ?? "Photo just taken")
        .accessibilityAddTraits(.isImage)
    }

    // MARK: Labels

    /// One row of room chips that scrolls sideways, the selected room scrolled into view, then
    /// `More` (the room picker).
    private var roomBlock: some View {
      VStack(alignment: .leading, spacing: FieldMetric.labelCaptionGap) {
        SectionCaption(
          "Room", suffix: "\u{00B7} stays selected for the next photo",
          inset: FieldMetric.labelCaptionInset)
        ScrollViewReader { proxy in
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: FieldMetric.chipGap) {
              ForEach(model.primaryRooms, id: \.self) { room in
                ChoiceChip(
                  room, isSelected: model.isSelected(room), kind: .room,
                  needsPhoto: model.needsPhoto(room)
                ) {
                  model.chooseRoom(room)
                }
                .id(room)
                .accessibilityIdentifier("photo.room.\(room)")
              }
              ChoiceChip("More", isSelected: false, kind: .room) { showsRoomPicker = true }
                .accessibilityIdentifier("photo.moreRooms")
                .accessibilityHint("All rooms of \(model.capture.label)")
            }
          }
          .accessibilityElement(children: .contain)
          .accessibilityLabel("Room")
          .onAppear {
            guard let selected = model.primaryRooms.first(where: model.isSelected) else { return }
            proxy.scrollTo(selected)
          }
        }
      }
    }

    private var directionBlock: some View {
      VStack(alignment: .leading, spacing: FieldMetric.labelCaptionGap) {
        SectionCaption(
          "Looking toward", suffix: model.draft.directionCaptionSuffix,
          inset: FieldMetric.labelCaptionInset)
        ChapterSegmented(
          "Looking toward",
          selection: Binding(
            get: { model.draft.direction },
            set: { direction in if let direction { model.chooseDirection(direction) } }),
          options: PhotoDirection.allCases.map {
            .init(
              $0, $0.chipTitle, accessibilityIdentifier: "photo.direction.\($0.rawValue)",
              accessibilityLabel: $0.spokenTitle)
          })
      }
    }

    /// All seven subjects, wrapping.
    private var subjectBlock: some View {
      VStack(alignment: .leading, spacing: FieldMetric.labelCaptionGap) {
        SectionCaption("Subject", inset: FieldMetric.labelCaptionInset)
        FlowLayout {
          ForEach(PhotoSubject.primaryChoices, id: \.self) { subject in
            ChoiceChip(
              subject.chipTitle, isSelected: model.draft.subject == subject, kind: .subject
            ) {
              model.chooseSubject(subject)
            }
            .accessibilityIdentifier("photo.subject.\(subject.rawValue)")
          }
        }
      }
    }

    // MARK: Actions

    private var actions: some View {
      VStack(alignment: .leading, spacing: 6) {
        if let message = model.errorMessage {
          Text(message)
            .chapterTextStyle(.footnote)
            .foregroundStyle(FieldTheme.Color.blocked)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("photo.error")
        } else if let hint = model.missingHint {
          Text(hint)
            .chapterTextStyle(.footnote)
            .foregroundStyle(FieldTheme.Color.muted)
            .accessibilityIdentifier("photo.missingHint")
        }
        Button("Save and take next") { model.saveAndTakeNext() }
          .buttonStyle(.chapter(.primary))
          .disabled(!model.canSave)
          .accessibilityIdentifier("photo.save")
        Button("Done with photos") {
          if model.saveAndFinish() { onDone?() }
        }
        .buttonStyle(.chapter(.text))
        .disabled(!model.canSave)
        .accessibilityIdentifier("photo.doneWithPhotos")
      }
      .chapterContentWidth()
      .padding(.top, 10)
      .padding(.horizontal, FieldTheme.Metric.screenPadding)
      .padding(.bottom, FieldTheme.Metric.actionBarBottom)
      .background(FieldTheme.Color.ground)
    }
  }
#endif

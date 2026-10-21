#if canImport(SwiftUI) && canImport(UIKit)
  import CaptureContract
  import FieldRules
  import SwiftUI
  import UIKit

  /// Photo labeling (design screen-field, 1): the photo just taken, then Room, Looking toward and
  /// Subject, then "Save and take next".
  public struct PhotoLabelingView: View {
    @Bindable var model: PhotoLabelingModel
    let onRenameRooms: (() -> Void)?

    /// `onRenameRooms`, when given, adds "Rename rooms" next to the Room caption.
    public init(model: PhotoLabelingModel, onRenameRooms: (() -> Void)? = nil) {
      self.model = model
      self.onRenameRooms = onRenameRooms
    }

    // The labels scroll and "Save and take next" stays pinned at the bottom: with "More…" open,
    // a plain VStack pushed the button off screen and the photo could not be saved.
    public var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: FieldTheme.space16) {
          HStack {
            Text(model.title).font(FieldTheme.headline)
            Spacer()
            Text("Original kept").font(FieldTheme.caption).foregroundStyle(FieldTheme.muted)
          }

          photo
          roomSection
          directionSection
          subjectSection

          Text("Keep personal items and people out of the frame.")
            .font(FieldTheme.caption)
            .foregroundStyle(FieldTheme.muted)
        }
      }
      .scrollDismissesKeyboard(.interactively)
      .safeAreaInset(edge: .bottom, spacing: 0) {
        VStack(alignment: .leading, spacing: FieldTheme.space8) {
          if let message = model.errorMessage {
            Text(message).font(FieldTheme.caption).foregroundStyle(FieldTheme.blocked)
          } else if let hint = model.missingHint {
            Text(hint).font(FieldTheme.caption).foregroundStyle(FieldTheme.muted)
              .accessibilityIdentifier("photo.missingHint")
          }
          PrimaryButton(title: "Save and take next", isEnabled: model.canSave) {
            model.saveAndTakeNext()
          }
        }
        .padding(.top, FieldTheme.space8)
        .background(FieldTheme.ground)
      }
      .fieldScreen()
    }

    private var photo: some View {
      FieldTheme.line
        .frame(height: 260)
        .frame(maxWidth: .infinity)
        .overlay {
          if let data = model.pendingOriginal, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill()
          }
        }
        .clipShape(RoundedRectangle(cornerRadius: FieldTheme.sheetRadius))
        .accessibilityLabel("Photo just taken")
    }

    /// Room chips, a dot on each room that still needs a photo (the checklist's rule), and
    /// "Rename rooms" for a room the scan named wrong ("Closet" that is a shower).
    private var roomSection: some View {
      VStack(alignment: .leading, spacing: FieldTheme.space8) {
        HStack(alignment: .center) {
          FieldCaption(text: "Room")
          Spacer()
          if let onRenameRooms {
            InlineAction(title: "Rename rooms", action: onRenameRooms)
              .accessibilityIdentifier("photo.renameRooms")
          }
        }
        .frame(minHeight: onRenameRooms == nil ? nil : FieldTheme.chipHeight)
        FlowLayout {
          ForEach(model.primaryRooms, id: \.self) { room in
            ChoiceChip(
              title: room, isSelected: model.draft.room == room, needsPhoto: model.needsPhoto(room)
            ) {
              model.chooseRoom(room)
            }
          }
          ChoiceChip(title: "More\u{2026}", isSelected: false) {
            model.showsAllRooms.toggle()
          }
        }
        if model.showsAllRooms {
          FlowLayout {
            ForEach(model.otherRooms, id: \.self) { room in
              ChoiceChip(
                title: room, isSelected: model.draft.room == room,
                needsPhoto: model.needsPhoto(room)
              ) {
                model.chooseRoom(room)
              }
            }
          }
          TextField("Other room", text: $model.otherRoom)
            .fieldBox(fontSize: 15)
            .submitLabel(.done)
            .onSubmit { model.useOtherRoom() }
        }
        if !model.coverage.rooms.isEmpty {
          coverageLine
        }
      }
    }

    /// "Still needs a photo: Shower" under the chips, its dot the chips' dot.
    private var coverageLine: some View {
      Label {
        Text(model.coverage.text)
      } icon: {
        if model.coverage.isComplete {
          Image(systemName: "checkmark.circle")
        } else {
          Circle().fill(FieldTheme.blocked).frame(width: 7, height: 7)
        }
      }
      .font(FieldTheme.caption)
      .foregroundStyle(FieldTheme.muted)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(model.coverage.text)
      .accessibilityIdentifier("photo.labelCoverage")
    }

    private var directionSection: some View {
      VStack(alignment: .leading, spacing: FieldTheme.space8) {
        FieldCaption(text: "Looking toward")
        HStack(spacing: FieldTheme.space8) {
          ForEach(PhotoDirection.allCases, id: \.self) { direction in
            Button {
              model.draft.direction = direction
            } label: {
              Text(direction.chipTitle)
                .font(FieldTheme.chip)
                .frame(maxWidth: .infinity)
                .frame(height: FieldTheme.chipHeight)
                .foregroundStyle(
                  model.draft.direction == direction ? FieldTheme.surface : FieldTheme.ink
                )
                .background(
                  model.draft.direction == direction ? FieldTheme.ink : FieldTheme.nude
                )
                .clipShape(RoundedRectangle(cornerRadius: FieldTheme.chipRadius))
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(model.draft.direction == direction ? .isSelected : [])
          }
        }
      }
    }

    private var subjectSection: some View {
      VStack(alignment: .leading, spacing: FieldTheme.space8) {
        FieldCaption(text: "Subject")
        FlowLayout {
          ForEach(PhotoSubject.primaryChoices, id: \.self) { subject in
            ChoiceChip(
              title: subject.chipTitle, isSelected: model.draft.subject == subject,
              horizontalPadding: 12
            ) {
              model.draft.subject = subject
            }
          }
          if model.showsMoreSubjects {
            ForEach(PhotoSubject.moreChoices, id: \.self) { subject in
              ChoiceChip(
                title: subject.chipTitle, isSelected: model.draft.subject == subject,
                horizontalPadding: 12
              ) {
                model.draft.subject = subject
              }
            }
          } else {
            ChoiceChip(title: "More\u{2026}", isSelected: false, horizontalPadding: 12) {
              model.showsMoreSubjects = true
            }
          }
        }
      }
    }
  }
#endif

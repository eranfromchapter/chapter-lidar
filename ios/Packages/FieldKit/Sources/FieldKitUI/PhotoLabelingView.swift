#if canImport(SwiftUI) && canImport(UIKit)
  import CaptureContract
  import FieldRules
  import SwiftUI
  import UIKit

  /// Photo labeling (design screen-field, 1): the photo just taken, then Room, Looking toward and
  /// Subject, then "Save and take next".
  public struct PhotoLabelingView: View {
    @Bindable var model: PhotoLabelingModel

    public init(model: PhotoLabelingModel) {
      self.model = model
    }

    public var body: some View {
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

        if let message = model.errorMessage {
          Text(message).font(FieldTheme.caption).foregroundStyle(FieldTheme.blocked)
        }

        Spacer(minLength: 0)

        PrimaryButton(title: "Save and take next", isEnabled: model.canSave) {
          model.saveAndTakeNext()
        }
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

    private var roomSection: some View {
      VStack(alignment: .leading, spacing: FieldTheme.space8) {
        FieldCaption(text: "Room")
        FlowLayout {
          ForEach(model.primaryRooms, id: \.self) { room in
            ChoiceChip(title: room, isSelected: model.draft.room == room) {
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
              ChoiceChip(title: room, isSelected: model.draft.room == room) {
                model.chooseRoom(room)
              }
            }
          }
          TextField("Other room", text: $model.otherRoom)
            .fieldBox(fontSize: 15)
            .submitLabel(.done)
            .onSubmit { model.useOtherRoom() }
        }
      }
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

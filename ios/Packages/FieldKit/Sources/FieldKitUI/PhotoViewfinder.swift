#if canImport(SwiftUI) && canImport(UIKit)
  import FieldRules
  import SwiftUI

  /// The photo step's camera screen: the live preview, a header with the title ("Shower · Photo
  /// 16 of Room Mexico"), "Rooms" (rename the capture's rooms) and "Done", the rooms that still
  /// need a photo, and the shutter. The viewfinder is not part of the frozen design (the design
  /// shows only the labeling screen), so it uses the plain tokens and nothing else.
  ///
  /// `preview` is what the camera sees: the app's camera preview, or a stand-in in UI tests.
  public struct PhotoViewfinder<Preview: View>: View {
    let model: PhotoLabelingModel
    let cameraError: String?
    let onDone: () -> Void
    let onRenameRooms: (() -> Void)?
    let preview: Preview

    public init(
      model: PhotoLabelingModel, cameraError: String? = nil, onDone: @escaping () -> Void,
      onRenameRooms: (() -> Void)? = nil, @ViewBuilder preview: () -> Preview
    ) {
      self.model = model
      self.cameraError = cameraError
      self.onDone = onDone
      self.onRenameRooms = onRenameRooms
      self.preview = preview()
    }

    public var body: some View {
      ZStack {
        FieldTheme.ink.ignoresSafeArea()
        preview.ignoresSafeArea()
        VStack(spacing: 0) {
          header
            .padding(.horizontal, 20)
            .padding(.top, FieldTheme.space8)
            .padding(.bottom, FieldTheme.space16)
            .background(alignment: .top) { headerScrim }

          Spacer()

          if let message = cameraError ?? model.errorMessage {
            Text(message)
              .font(FieldTheme.caption)
              .padding(FieldTheme.space12)
              .foregroundStyle(FieldTheme.blocked)
              .background(FieldTheme.surface)
              .clipShape(RoundedRectangle(cornerRadius: FieldTheme.chipRadius))
              .padding(.horizontal, 20)
              .padding(.bottom, FieldTheme.space8)
          }

          // On the coverage line's dark pill, and the shutter with a soft shadow: both stay
          // visible over a bright scene.
          Text("Keep personal items and people out of the frame.")
            .font(FieldTheme.caption)
            .foregroundStyle(FieldTheme.surface)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(FieldTheme.ink.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: FieldTheme.chipRadius))
            .padding(.bottom, FieldTheme.space8)

          Button {
            Task { await model.takePhoto() }
          } label: {
            Circle()
              .fill(FieldTheme.surface)
              .frame(width: 72, height: 72)
              .overlay(Circle().stroke(FieldTheme.line, lineWidth: 4))
              .shadow(color: FieldTheme.ink.opacity(0.35), radius: 6, y: 1)
          }
          .buttonStyle(.plain)
          .disabled(model.isCapturing || cameraError != nil)
          .accessibilityLabel("Take photo")
          .padding(.bottom, FieldTheme.space24)
        }
      }
    }

    private var header: some View {
      VStack(alignment: .leading, spacing: FieldTheme.space8) {
        HStack(alignment: .center, spacing: FieldTheme.space8) {
          Text(model.headerTitle)
            .font(FieldTheme.headline)
            .foregroundStyle(FieldTheme.surface)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("photo.title")
          if let onRenameRooms {
            // Light text on its own dark fill, like the coverage pill, so it reads over white
            // shower tiles as well as in a dark room.
            Button("Rooms", action: onRenameRooms)
              .font(FieldTheme.chip)
              .padding(.horizontal, 14)
              .frame(minHeight: FieldTheme.chipHeight)
              .foregroundStyle(FieldTheme.surface)
              .background(FieldTheme.ink.opacity(0.72))
              .clipShape(RoundedRectangle(cornerRadius: FieldTheme.chipRadius))
              .overlay(
                RoundedRectangle(cornerRadius: FieldTheme.chipRadius)
                  .stroke(FieldTheme.surface, lineWidth: 1))
              .contentShape(Rectangle())
              .accessibilityHint("Rename the rooms of \(model.capture.label)")
              .accessibilityIdentifier("photo.rooms")
          }
          Button("Done", action: onDone)
            .font(FieldTheme.chip)
            .padding(.horizontal, 14)
            .frame(minHeight: FieldTheme.chipHeight)
            .foregroundStyle(FieldTheme.ink)
            .background(FieldTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: FieldTheme.chipRadius))
        }
        coverageLine
      }
    }

    /// A dark band behind the header, from the top of the screen, fading out below it: the
    /// light title ("Shower · Photo 16 of Room Mexico") reads over a bright scene, such as the
    /// white tiles of the shower the operator is standing in.
    private var headerScrim: some View {
      LinearGradient(
        stops: [
          .init(color: FieldTheme.ink.opacity(0.78), location: 0),
          .init(color: FieldTheme.ink.opacity(0.66), location: 0.7),
          .init(color: FieldTheme.ink.opacity(0), location: 1),
        ],
        startPoint: .top, endPoint: .bottom
      )
      .ignoresSafeArea(edges: .top)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
    }

    /// "Still needs a photo: Shower" or "Every room has a photo", on a dark pill so it reads
    /// over any camera image.
    private var coverageLine: some View {
      let coverage = model.coverage
      return Label {
        Text(coverage.text)
      } icon: {
        Image(systemName: coverage.isComplete ? "checkmark.circle.fill" : "camera.circle")
      }
      .font(FieldTheme.caption)
      .foregroundStyle(FieldTheme.surface)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(FieldTheme.ink.opacity(0.72))
      .clipShape(RoundedRectangle(cornerRadius: FieldTheme.chipRadius))
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(coverage.text)
      .accessibilityIdentifier("photo.coverage")
    }
  }
#endif

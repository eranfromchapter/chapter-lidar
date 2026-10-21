#if canImport(SwiftUI) && canImport(UIKit)
  import ChapterUI
  import FieldRules
  import SwiftUI

  /// The photo step's camera screen (phone-field §3.1; not drawn in v1 or v2, so it keeps its
  /// layout in the v2 type): the live preview, a header with the title (`Shower · Photo 16 ·
  /// Floor 1`), "Rooms" (rename the capture's rooms) and "Done", the rooms that still need a
  /// photo, and the shutter. The navigation bar is hidden while it shows. The camera heading
  /// provider runs while it is on screen, so the shutter can sample where the camera points.
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
        FieldTheme.Color.ink.ignoresSafeArea()
        preview.ignoresSafeArea()
        VStack(spacing: 0) {
          header
            .padding(.horizontal, FieldTheme.Metric.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, FieldTheme.Metric.screenPadding)
            .background(alignment: .top) { headerScrim }

          Spacer()

          if let message = cameraError ?? model.errorMessage {
            Text(message)
              .chapterTextStyle(.footnote)
              .padding(FieldTheme.Metric.rowGap)
              .foregroundStyle(FieldTheme.Color.blocked)
              .background(FieldTheme.Color.surface)
              .clipShape(RoundedRectangle(cornerRadius: FieldTheme.Metric.chipRadius))
              .padding(.horizontal, FieldTheme.Metric.screenPadding)
              .padding(.bottom, 8)
          }

          // On the coverage line's dark pill, and the shutter with a soft shadow: both stay
          // visible over a bright scene.
          Text("Keep people and personal items out of the frame.")
            .chapterTextStyle(.footnote)
            .foregroundStyle(FieldTheme.Color.surface)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(FieldTheme.Color.ink.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: FieldTheme.Metric.chipRadius))
            .padding(.bottom, 8)

          Button {
            Task { await model.takePhoto() }
          } label: {
            Circle()
              .fill(FieldTheme.Color.surface)
              .frame(width: 72, height: 72)
              .overlay(Circle().stroke(FieldTheme.Color.line, lineWidth: 4))
              .shadow(color: FieldTheme.Color.ink.opacity(0.35), radius: 6, y: 1)
          }
          .buttonStyle(.plain)
          .disabled(model.isCapturing || cameraError != nil)
          .accessibilityLabel("Take photo")
          .accessibilityIdentifier("photo.shutter")
          .padding(.bottom, 24)
        }
      }
      .toolbar(.hidden, for: .navigationBar)
      .onAppear { model.startHeading() }
      .onDisappear { model.stopHeading() }
    }

    private var header: some View {
      VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .center, spacing: 8) {
          Text(model.headerTitle)
            .chapterTextStyle(.navTitle)
            .foregroundStyle(FieldTheme.Color.surface)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("photo.title")
          if let onRenameRooms {
            // Light text on its own dark fill, like the coverage pill, so it reads over white
            // shower tiles as well as in a dark room.
            Button(action: onRenameRooms) {
              Text("Rooms")
                .chapterTextStyle(.subhead)
                .foregroundStyle(FieldTheme.Color.surface)
                .padding(.horizontal, 14)
                .frame(minHeight: FieldTheme.Metric.touchTarget)
                .background(FieldTheme.Color.ink.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: FieldTheme.Metric.chipRadius))
                .overlay(
                  RoundedRectangle(cornerRadius: FieldTheme.Metric.chipRadius)
                    .stroke(FieldTheme.Color.surface, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Rename the rooms of \(model.capture.label)")
            .accessibilityIdentifier("photo.rooms")
          }
          Button(action: onDone) {
            Text("Done")
              .chapterTextStyle(.subhead)
              .foregroundStyle(FieldTheme.Color.ink)
              .padding(.horizontal, 14)
              .frame(minHeight: FieldTheme.Metric.touchTarget)
              .background(FieldTheme.Color.surface)
              .clipShape(RoundedRectangle(cornerRadius: FieldTheme.Metric.chipRadius))
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("photo.done")
        }
        coverageLine
      }
    }

    /// A dark band behind the header, from the top of the screen, fading out below it: the
    /// light title reads over a bright scene, such as the white tiles of the shower the operator
    /// is standing in.
    private var headerScrim: some View {
      LinearGradient(
        stops: [
          .init(color: FieldTheme.Color.ink.opacity(0.78), location: 0),
          .init(color: FieldTheme.Color.ink.opacity(0.66), location: 0.7),
          .init(color: FieldTheme.Color.ink.opacity(0), location: 1),
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
      .chapterTextStyle(.footnote)
      .foregroundStyle(FieldTheme.Color.surface)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(FieldTheme.Color.ink.opacity(0.72))
      .clipShape(RoundedRectangle(cornerRadius: FieldTheme.Metric.chipRadius))
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(coverage.text)
      .accessibilityIdentifier("photo.coverage")
    }
  }
#endif

#if canImport(SwiftUI) && canImport(UIKit) && canImport(AVFoundation)
  import CaptureContract
  import FieldRules
  import PhotoStore
  import SwiftUI

  extension PhotoLabelingModel {
    /// Model wired to the app's own camera.
    public convenience init(
      capture: FieldCaptureOption, store: PhotoRecordStore, camera: CameraEngine,
      initialRoom: String? = nil
    ) {
      self.init(
        capture: capture, store: store, initialRoom: initialRoom,
        capturePhoto: { try await camera.capture() })
    }
  }

  /// The photo step: a live viewfinder with a shutter button, then the labeling screen for the
  /// photo just taken. The viewfinder is not part of the frozen design (the design shows only
  /// the labeling screen), so it uses the plain tokens and nothing else.
  public struct PhotoCaptureFlowView: View {
    let model: PhotoLabelingModel
    let camera: CameraEngine
    let onDone: () -> Void
    @State private var cameraError: String?

    public init(model: PhotoLabelingModel, camera: CameraEngine, onDone: @escaping () -> Void) {
      self.model = model
      self.camera = camera
      self.onDone = onDone
    }

    public var body: some View {
      Group {
        if model.pendingOriginal == nil {
          viewfinder
        } else {
          PhotoLabelingView(model: model)
        }
      }
      .task {
        do {
          try await camera.start()
        } catch {
          cameraError = userMessage(for: error)
        }
      }
      .onDisappear { camera.stop() }
    }

    private var viewfinder: some View {
      ZStack {
        FieldTheme.ink.ignoresSafeArea()
        CameraPreview(session: camera.session).ignoresSafeArea()
        VStack {
          HStack {
            Text(model.title)
              .font(FieldTheme.headline)
              .foregroundStyle(FieldTheme.surface)
            Spacer()
            Button("Done", action: onDone)
              .font(FieldTheme.chip)
              .padding(.horizontal, 14)
              .frame(minHeight: FieldTheme.chipHeight)
              .foregroundStyle(FieldTheme.ink)
              .background(FieldTheme.surface)
              .clipShape(RoundedRectangle(cornerRadius: FieldTheme.chipRadius))
          }
          .padding(.horizontal, 20)
          .padding(.top, FieldTheme.space8)

          Spacer()

          if let message = cameraError ?? model.errorMessage {
            Text(message)
              .font(FieldTheme.caption)
              .padding(FieldTheme.space12)
              .foregroundStyle(FieldTheme.blocked)
              .background(FieldTheme.surface)
              .clipShape(RoundedRectangle(cornerRadius: FieldTheme.chipRadius))
              .padding(.horizontal, 20)
          }

          Text("Keep personal items and people out of the frame.")
            .font(FieldTheme.caption)
            .foregroundStyle(FieldTheme.surface)
            .padding(.bottom, FieldTheme.space8)

          Button {
            Task { await model.takePhoto() }
          } label: {
            Circle()
              .fill(FieldTheme.surface)
              .frame(width: 72, height: 72)
              .overlay(Circle().stroke(FieldTheme.line, lineWidth: 4))
          }
          .buttonStyle(.plain)
          .disabled(model.isCapturing || cameraError != nil)
          .accessibilityLabel("Take photo")
          .padding(.bottom, FieldTheme.space24)
        }
      }
    }
  }
#endif

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

  /// The photo step: a live viewfinder with a shutter button (`PhotoViewfinder`), then the
  /// labeling screen for the photo just taken. `onRenameRooms`, when given, adds "Rooms" to the
  /// viewfinder and "Rename rooms" above the Room chips.
  public struct PhotoCaptureFlowView: View {
    let model: PhotoLabelingModel
    let camera: CameraEngine
    let onDone: () -> Void
    let onRenameRooms: (() -> Void)?
    @State private var cameraError: String?

    public init(
      model: PhotoLabelingModel, camera: CameraEngine, onDone: @escaping () -> Void,
      onRenameRooms: (() -> Void)? = nil
    ) {
      self.model = model
      self.camera = camera
      self.onDone = onDone
      self.onRenameRooms = onRenameRooms
    }

    public var body: some View {
      Group {
        if model.pendingOriginal == nil {
          PhotoViewfinder(
            model: model, cameraError: cameraError, onDone: onDone, onRenameRooms: onRenameRooms
          ) {
            CameraPreview(session: camera.session)
          }
        } else {
          PhotoLabelingView(model: model, onRenameRooms: onRenameRooms)
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
  }
#endif

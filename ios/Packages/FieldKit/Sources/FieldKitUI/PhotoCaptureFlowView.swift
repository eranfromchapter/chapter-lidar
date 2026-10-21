#if canImport(SwiftUI) && canImport(UIKit) && canImport(AVFoundation)
  import CaptureContract
  import FieldRules
  import PhotoStore
  import SwiftUI

  extension PhotoLabelingModel {
    /// Model wired to the app's own camera, and to the camera heading for the "Looking toward"
    /// pre-fill (the app's adapter over its compass service).
    public convenience init(
      capture: FieldCaptureOption, store: PhotoRecordStore, camera: CameraEngine,
      initialRoom: String? = nil, heading: PhotoHeadingProviding? = nil
    ) {
      self.init(
        capture: capture, store: store, initialRoom: initialRoom, heading: heading,
        capturePhoto: { try await camera.capture() })
    }
  }

  /// The photo step: a live viewfinder with a shutter button (`PhotoViewfinder`, navigation bar
  /// hidden), then "Label a photo" for the photo just taken (inline navigation bar). "Done" on
  /// the viewfinder and "Done with photos" call `onDone`; the app pops the step. The heading
  /// provider runs with the viewfinder. `onRenameRooms`, when given, adds "Rooms" to the
  /// viewfinder and "Rename rooms" to the room picker.
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
          PhotoLabelingView(model: model, onDone: onDone, onRenameRooms: onRenameRooms)
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

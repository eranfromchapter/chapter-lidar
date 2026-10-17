#if canImport(RoomPlan) && canImport(ARKit) && canImport(SwiftUI) && os(iOS)
  import ARKit
  import SwiftUI

  /// The camera feed of the capture's `ARSession`, for the live scan screen. It only displays the
  /// session; `LiveCaptureSession` owns and runs it.
  public struct LiveCameraPreview: UIViewRepresentable {
    public let session: ARSession

    public init(session: ARSession) {
      self.session = session
    }

    public func makeUIView(context: Context) -> ARSCNView {
      let view = ARSCNView(frame: .zero)
      view.session = session
      view.automaticallyUpdatesLighting = false
      return view
    }

    public func updateUIView(_ uiView: ARSCNView, context: Context) {}
  }
#endif

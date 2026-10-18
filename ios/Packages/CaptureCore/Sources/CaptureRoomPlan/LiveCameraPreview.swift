#if canImport(RoomPlan) && canImport(ARKit) && canImport(SwiftUI) && os(iOS)
  import ARKit
  import SwiftUI

  /// The camera feed of the capture's `ARSession`, for the live scan screen. It only displays the
  /// session; `LiveCaptureSession` owns and runs it. In the capture flow use
  /// `CaptureSessionPreview`, which picks the current session of a `CaptureFlowModel`.
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

    /// Follows a new session if SwiftUI reuses the view. Display only: it never runs the session.
    public func updateUIView(_ uiView: ARSCNView, context: Context) {
      if uiView.session !== session {
        uiView.session = session
      }
    }
  }
#endif

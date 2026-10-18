#if canImport(RoomPlan) && canImport(ARKit) && canImport(SwiftUI) && canImport(Observation) && os(iOS)
  import CaptureCore
  import SwiftUI

  /// The live scan panel's content for `CaptureFlowView(model:preview:)`: the camera feed of the
  /// model's current session when it is a `LiveCaptureSession`, otherwise nothing, so the panel
  /// keeps the design's dark placeholder (`ReplaySession`, or no scan in progress).
  ///
  /// It reads `CaptureFlowModel.currentSession`, so it follows the scan: the feed appears when Start
  /// scan made the session and goes when Finish floor or Cancel drops it. It only displays the
  /// session's `ARSession`; the session itself runs and stops it.
  ///
  ///     CaptureFlowView(model: model, preview: { CaptureSessionPreview(model: model) })
  public struct CaptureSessionPreview: View {
    public let model: CaptureFlowModel

    public init(model: CaptureFlowModel) {
      self.model = model
    }

    public var body: some View {
      if let live = model.currentSession as? LiveCaptureSession {
        LiveCameraPreview(session: live.arSession)
          // A new scan gets a fresh view rather than the previous scan's ARSCNView.
          .id(ObjectIdentifier(live))
      } else {
        Color.clear
      }
    }
  }
#endif

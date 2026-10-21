#if canImport(RoomPlan) && canImport(ARKit) && canImport(SwiftUI) && canImport(Observation) && os(iOS)
  import CaptureCore
  import RoomPlan
  import SwiftUI

  /// The camera well's content for `LiveScanScreen(model:preview:)`: Apple's RoomPlan view
  /// (camera feed, live outline and coaching) of the model's current session when it is a
  /// `LiveCaptureSession`, otherwise nothing, so the panel
  /// keeps the design's plain well (`ReplaySession`, or no scan in progress).
  ///
  /// It reads `CaptureFlowModel.currentSession`, so it follows the scan: the view appears when Start
  /// scan made the session and goes when Finish floor or Cancel drops it. It only displays the
  /// session's `RoomCaptureView`; the session itself runs and stops it.
  ///
  ///     LiveScanScreen(model: model) { CaptureSessionPreview(model: model) }
  public struct CaptureSessionPreview: View {
    public let model: CaptureFlowModel

    public init(model: CaptureFlowModel) {
      self.model = model
    }

    public var body: some View {
      if let live = model.currentSession as? LiveCaptureSession {
        RoomCapturePreview(view: live.captureView)
          // A new scan gets its own RoomCaptureView rather than the previous scan's.
          .id(ObjectIdentifier(live))
      } else {
        Color.clear
      }
    }
  }

  /// Hosts a session's `RoomCaptureView`. Display only: the session runs and stops RoomPlan.
  struct RoomCapturePreview: UIViewRepresentable {
    let view: RoomCaptureView

    func makeUIView(context: Context) -> RoomCaptureView { view }
    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}
  }
#endif

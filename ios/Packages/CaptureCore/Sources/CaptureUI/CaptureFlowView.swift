#if canImport(SwiftUI) && canImport(Observation) && os(iOS)
  import CaptureCore
  import SwiftUI

  /// The three capture screens of docs/waves/design/snapshot.html#screen-capture, driven by a
  /// `CaptureFlowModel`: 1 New capture, 2 What are you scanning?, 3 Live scan.
  ///
  /// `preview` is shown inside the live scan panel (use `LiveCameraPreview` from `CaptureRoomPlan`
  /// for the camera feed). `finished` is shown after Finish floor; the design ends at the live
  /// scan screen, so the host app (F5, F6) supplies what comes next.
  public struct CaptureFlowView<Preview: View, Finished: View>: View {
    @Bindable var model: CaptureFlowModel
    let preview: () -> Preview
    let finished: (CaptureFlowResult) -> Finished

    public init(
      model: CaptureFlowModel, @ViewBuilder preview: @escaping () -> Preview,
      @ViewBuilder finished: @escaping (CaptureFlowResult) -> Finished
    ) {
      self.model = model
      self.preview = preview
      self.finished = finished
    }

    public var body: some View {
      ZStack {
        (model.step == .scanning ? ChapterTokens.Palette.ink : ChapterTokens.Palette.ground)
          .ignoresSafeArea()
        switch model.step {
        case .newCapture:
          NewCaptureScreen(model: model)
        case .scanSetup:
          ScanSetupScreen(model: model)
        case .scanning:
          LiveScanScreen(model: model, preview: preview)
        case .finished:
          if let result = model.result {
            finished(result)
          }
        }
      }
      .task { await model.loadProjects() }
    }
  }

  extension CaptureFlowView where Finished == EmptyView {
    public init(model: CaptureFlowModel, @ViewBuilder preview: @escaping () -> Preview) {
      self.init(model: model, preview: preview, finished: { _ in EmptyView() })
    }
  }

  extension CaptureFlowView where Preview == EmptyView, Finished == EmptyView {
    public init(model: CaptureFlowModel) {
      self.init(model: model, preview: { EmptyView() }, finished: { _ in EmptyView() })
    }
  }
#endif

#if canImport(SwiftUI) && canImport(Observation) && os(iOS)
  import CaptureCore
  import ChapterUI
  import SwiftUI

  /// The three capture screens in a NavigationStack of their own, driven by a
  /// `CaptureFlowModel`: New capture, What are you scanning? (pushed) and the live scan (full
  /// screen while `model.step == .scanning`).
  ///
  /// Kept for the v1 app shell only. In v2 the app's own NavigationStack hosts
  /// `NewCaptureScreen`, `ScanSetupScreen` and `LiveScanScreen` next to the Captures home and
  /// the Capture overview (phone-capture §3.0); remove this view once the app no longer uses it.
  ///
  /// `preview` is shown inside the live scan's camera well (`CaptureSessionPreview(model:)` from
  /// `CaptureRoomPlan`). `finished` is shown after Finish floor.
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
      if model.step == .finished, let result = model.result {
        finished(result)
      } else {
        NavigationStack(path: path) {
          NewCaptureScreen(model: model)
            .navigationDestination(for: CaptureFlowStep.self) { _ in
              ScanSetupScreen(model: model)
            }
        }
        .fullScreenCover(isPresented: isScanning) {
          LiveScanScreen(model: model, preview: preview)
        }
      }
    }

    /// Step 2 is pushed on step 1; going back pops it.
    private var path: Binding<[CaptureFlowStep]> {
      Binding(
        get: { model.step == .newCapture ? [] : [.scanSetup] },
        set: { path in
          if path.isEmpty { model.back() }
        })
    }

    private var isScanning: Binding<Bool> {
      Binding(get: { model.step == .scanning }, set: { _ in })
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

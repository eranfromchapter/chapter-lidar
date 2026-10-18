import AppCore
import CaptureCore
import CaptureRoomPlan
import CaptureUI
import FieldKitUI
import SwiftUI

private typealias Palette = ChapterTokens.Palette
private typealias Typo = ChapterTokens.Typography
private typealias Control = ChapterTokens.Control
private typealias Radius = ChapterTokens.Radius

/// The visit's screens in the order of the frozen design.
struct VisitView: View {
  let visit: VisitModel

  var body: some View {
    ZStack {
      Palette.ground.ignoresSafeArea()
      content
    }
    .overlay(alignment: .bottom) {
      if let message = visit.message {
        Text("\u{25A0} \(message)")
          .font(Typo.caption).foregroundStyle(Palette.blocked)
          .padding(12)
          .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.chip))
          .padding(.bottom, 96)
          .padding(.horizontal, 20)
      }
    }
  }

  @ViewBuilder
  private var content: some View {
    if let upload = visit.upload {
      UploadingView(snapshot: upload, onNewCapture: { visit.startNewCapture() })
    } else {
      switch visit.flow.step {
      case .captureRecord, .scan:
        if let model = visit.captureModel {
          CaptureFlowView(model: model, preview: { ScanPreview(services: visit.services) })
            .onChange(of: model.step) { _, step in visit.captureStepChanged(step) }
        }
      case .photos:
        if let model = visit.photoModel {
          PhotoStep(model: model, source: visit.services.photoSource) { visit.photosDone() }
        }
      case .controls:
        if let model = visit.controlsModel {
          FieldControlsView(model: model)
            .overlay(alignment: .topTrailing) {
              Button("Continue") { visit.controlsDone() }
                .font(Typo.sans(15, weight: .semibold)).foregroundStyle(Palette.ink)
                .frame(minHeight: Control.minTouch)
                .padding(.horizontal, 20)
                .accessibilityIdentifier("controls.continue")
            }
        }
      case .checklist:
        if let report = visit.checklist {
          BeforeYouLeaveView(
            report: report, onTakePhoto: { visit.checklistTakePhoto($0) },
            onAddControls: { _ in visit.checklistAddControls() },
            onFinish: { visit.checklistFinished() })
        }
      case .packageReady:
        PackageReadyView(visit: visit)
      case .uploading:
        ProgressView()
      }
    }
  }
}

/// The camera panel of the live scan: the RoomPlan/ARKit camera feed, or nothing in replay.
private struct ScanPreview: View {
  let services: AppServices

  var body: some View {
    // The live session object is created by the capture model; the panel shows the design's
    // dark placeholder while RoomPlan draws its own coaching. (LiveCameraPreview needs the
    // session's ARSession, which CaptureFlowModel does not expose.)
    Color.clear
  }
}

/// Photos: the app's camera (viewfinder, then labeling) or, in UI tests, the fixture photo.
private struct PhotoStep: View {
  let model: PhotoLabelingModel
  let source: PhotoSource
  let onDone: () -> Void

  var body: some View {
    switch source {
    case .camera(let camera):
      PhotoCaptureFlowView(model: model, camera: camera, onDone: onDone)
    case .fixed:
      #if DEBUG
        UITestViewfinder(model: model, onDone: onDone)
      #else
        EmptyView()
      #endif
    }
  }
}

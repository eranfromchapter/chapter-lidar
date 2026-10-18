import AppCore
import CaptureCore
import CaptureRoomPlan
import CaptureUI
import FieldKitUI
import SwiftUI

private typealias Palette = ChapterTokens.Palette
private typealias Space = ChapterTokens.Space
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
          CaptureFlowView(model: model, preview: { CaptureSessionPreview(model: model) })
            .onChange(of: model.step) { _, step in visit.captureStepChanged(step) }
            .safeAreaInset(edge: .bottom, spacing: 0) {
              if visit.canSignOut {
                AccountFooter(visit: visit)
              }
            }
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
            onConfirmNoRoomsSkipped: { visit.checklistConfirmNoRoomsSkipped() },
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

/// "Signed in as <name> · Sign out" under New capture (caption 13, muted; the link in ink with a
/// 44 pt touch target). Shown only before the visit's first capture (`VisitModel.canSignOut`).
/// Sign-out deletes no file: sealed packages the station has not confirmed stay on the phone and
/// their uploads resume after the next sign-in.
private struct AccountFooter: View {
  let visit: VisitModel

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: Space.s1) {
        Text(signedInText)
          .font(Typo.caption).foregroundStyle(Palette.muted)
          .lineLimit(1).truncationMode(.middle)
        Button {
          visit.signOut()
        } label: {
          Text("Sign out").font(Typo.caption).foregroundStyle(Palette.ink)
            .frame(minWidth: Control.minTouch, minHeight: Control.minTouch)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("account.signOut")
      }
      if visit.hasPendingUploads {
        Text("Uploads resume after you sign in again.")
          .font(Typo.caption).foregroundStyle(Palette.muted)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 20)
    .padding(.bottom, Space.s2)
    .background(Palette.ground)
  }

  private var signedInText: String {
    let name = visit.signedInName
    return name.isEmpty ? "Signed in \u{00B7}" : "Signed in as \(name) \u{00B7}"
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

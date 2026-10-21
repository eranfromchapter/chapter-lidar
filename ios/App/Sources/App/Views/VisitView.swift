import AppCore
import CaptureContract
import CaptureCore
import CaptureRoomPlan
import CaptureUI
import FieldKitUI
import FieldRules
import SwiftUI

private typealias Palette = ChapterTokens.Palette
private typealias Space = ChapterTokens.Space
private typealias Typo = ChapterTokens.Typography
private typealias Control = ChapterTokens.Control
private typealias Radius = ChapterTokens.Radius

/// The visit's screens in the order of the frozen design.
struct VisitView: View {
  let visit: VisitModel
  /// "Rename rooms", from the photo step (that capture) or the checklist (every capture).
  @State private var renaming: RoomNamingDraft?

  var body: some View {
    ZStack {
      Palette.ground.ignoresSafeArea()
      content
    }
    .sheet(item: $renaming) { draft in
      RoomNamesSheet(draft: draft) { visit.renameRooms($0) }
    }
    .overlay(alignment: .bottom) {
      // The package screens show their errors inline (phone-package §3.2).
      if let message = visit.message, visit.upload == nil, visit.flow.step != .packageReady {
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
      // Package status and Verdict received (phone-package §4, §5), in a stack of their own
      // until the app's navigation pushes them; "New capture" stands in for the Captures home.
      NavigationStack {
        PackageStatusView(
          packageId: upload.packageId, snapshot: upload,
          actions: PackageStatusActions(openInHub: { UIApplication.shared.open($0) })
        )
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Button("New capture") { visit.startNewCapture() }
              .accessibilityIdentifier("package.newCapture")
          }
        }
      }
    } else {
      switch visit.flow.step {
      case .captureRecord, .scan:
        if let model = visit.captureModel {
          // The footer goes inside CaptureFlowView's NavigationStack, under New capture's
          // Continue button (an outer inset does not reach into the stack).
          CaptureFlowView(model: model, preview: { CaptureSessionPreview(model: model) }) {
            if visit.canSignOut {
              AccountFooter(visit: visit)
            }
          }
          .onChange(of: model.step) { _, step in visit.captureStepChanged(step) }
        }
      // The photo step (viewfinder, then Label a photo with an inline bar), Field controls and
      // Before you leave set their own titles and toolbars (pushed screens, phone-field §2), each
      // in a stack of its own until the app's navigation pushes them.
      case .photos:
        if let model = visit.photoModel {
          NavigationStack {
            PhotoStep(
              model: model, source: visit.services.photoSource,
              onDone: { visit.photosDone() },
              onRenameRooms: renameAction(captureId: model.capture.ref.captureId))
          }
        }
      case .controls:
        if let model = visit.controlsModel {
          NavigationStack {
            FieldControlsView(model: model)
              .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                  Button("Continue") { visit.controlsDone() }
                    .accessibilityIdentifier("controls.continue")
                }
              }
          }
        }
      case .checklist:
        if let report = visit.checklist {
          NavigationStack {
            BeforeYouLeaveView(
              report: report, onTakePhoto: { visit.checklistTakePhoto($0) },
              onAddControls: { _ in visit.checklistAddControls() },
              onConfirmNoRoomsSkipped: { visit.checklistConfirmNoRoomsSkipped() },
              onRenameRooms: renameAction(captureId: nil),
              onFinish: { visit.checklistFinished() })
          }
        }
      case .packageReady:
        NavigationStack {
          PackageReadyView(
            state: packageReadyState,
            actions: PackageReadyActions(
              scanAnother: { visit.addMoreRooms() }, seal: { visit.sealAndUpload() }))
        }
      case .uploading:
        ProgressView()
      }
    }
  }

  /// Package ready's state from the visit: the plan's review once built, the build or seal error
  /// inline.
  private var packageReadyState: PackageReadyState {
    let record = visit.flow.record
    return PackageReadyState(
      buildingSubtitle: PackageReview.buildingSubtitle(
        address: record?.address.formatted ?? "",
        captureCountText: record.map(CaptureCountText.make) ?? "", revision: 1),
      review: visit.plan?.review,
      buildError: visit.plan == nil && !visit.isBuilding ? visit.message : nil,
      isSealing: visit.isSealing,
      sealError: visit.plan == nil ? nil : visit.message.map { SealFailureText.make(reason: $0) })
  }

  /// Opens "Rename rooms" for one capture, or every capture when `captureId` is nil; nil (no
  /// button) when there is no room to rename.
  private func renameAction(captureId: LowercaseUUID?) -> (() -> Void)? {
    guard visit.roomNamingDraft(captureId: captureId) != nil else { return nil }
    return { renaming = visit.roomNamingDraft(captureId: captureId) }
  }
}

/// "Signed in as <name> · Sign out" under New capture (caption 13, muted; the link in ink with a
/// 44 pt touch target). Shown only before the visit's first capture (`VisitModel.canSignOut`).
/// Sign-out deletes no file: sealed packages the station has not confirmed stay on the phone and
/// their uploads resume after the next sign-in.
private struct AccountFooter: View {
  let visit: VisitModel
  @State private var showScans = false

  var body: some View {
    VStack(spacing: 0) {
      if let root = visit.visitsRoot {
        Button { showScans = true } label: {
          Label("My scans", systemImage: "square.stack.3d.up")
            .font(Typo.sans(15, weight: .semibold)).foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, minHeight: Control.minTouch)
            .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("account.myScans")
        .padding(.bottom, Space.s2)
        .sheet(isPresented: $showScans) { MyScansView(visitsRoot: root) }
      }
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
  let onRenameRooms: (() -> Void)?

  var body: some View {
    switch source {
    case .camera(let camera):
      PhotoCaptureFlowView(
        model: model, camera: camera, onDone: onDone, onRenameRooms: onRenameRooms)
    case .fixed:
      #if DEBUG
        UITestViewfinder(model: model, onDone: onDone, onRenameRooms: onRenameRooms)
      #else
        EmptyView()
      #endif
    }
  }
}

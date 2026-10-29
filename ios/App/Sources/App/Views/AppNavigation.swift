import AppCore
import CaptureContract
import CaptureCore
import CaptureRoomPlan
import CaptureUI
import ChapterUI
import FieldKitUI
import FieldRules
import SketchEntry
import SketchUI
import SwiftUI
import UIKit

/// The app's one NavigationStack (phone-capture §3.0, critique R-18c): the Captures home at the
/// root, the open visit's screens pushed from its flow (`VisitModel.routes`), a floor's scan or a
/// v1 visit's scans on top (`HomeModel.extra`), and the live scan as a full-screen cover. Every
/// screen uses the system navigation bar and back chevron.
struct AppNavigation: View {
  let home: HomeModel

  var body: some View {
    NavigationStack(path: Binding(get: { home.path }, set: { home.setPath($0) })) {
      CapturesHomeScreen(state: home.state, actions: homeActions)
        .navigationDestination(for: AppRoute.self) { route in
          destination(route)
        }
        // The back of every screen pushed on the home says where it goes (phone-capture §3.5).
        .background(BackButtonTitle(title: "Back to captures"))
    }
    .fullScreenCover(
      isPresented: Binding(get: { home.visit?.isScanning ?? false }, set: { _ in })
    ) {
      if let model = home.visit?.captureModel {
        LiveScanScreen(model: model) { CaptureSessionPreview(model: model) }
      }
    }
    .onChange(of: home.visit?.captureModel?.step) { _, step in
      home.visit?.captureStepChanged(step)
      #if DEBUG
        UITestHooks.captureStepChanged(step, home: home)
      #endif
    }
    .onChange(of: home.visit?.sketchModel?.step) { _, step in
      home.visit?.sketchStepChanged(step)
    }
    .sheet(
      item: Binding(
        get: { home.visit?.renaming }, set: { draft in home.visit?.renaming = draft })
    ) { draft in
      RoomNamesSheet(draft: draft) { home.visit?.renameRooms($0) }
    }
    .alert(
      "Capture",
      isPresented: Binding(
        get: { home.alertMessage != nil }, set: { if !$0 { home.alertMessage = nil } })
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(home.alertMessage ?? "")
    }
    .overlay(alignment: .bottom) {
      if let message = home.visit?.message, showsMessage {
        MessageToast(text: message)
      }
    }
  }

  /// The Captures home's actions. "Delete all photos" only in the field-test and UI-test modes
  /// of a Debug build.
  private var homeActions: CapturesHomeActions {
    var actions = CapturesHomeActions(
      newCapture: { home.newCapture() }, sketchCapture: { home.sketchCapture() },
      open: { home.open($0) }, signOut: { home.signOut() }, refresh: { await home.refresh() })
    #if DEBUG
      if home.offersPhotoDeletion {
        actions.deletePhotos = { await home.deleteAllPhotos() }
      }
    #endif
    return actions
  }

  /// The capture and field screens show their errors at the bottom; the package screens show
  /// theirs inline.
  private var showsMessage: Bool {
    switch home.path.last {
    case .packageReady?, .revisionReady?, .packageStatus?: return false
    default: return true
    }
  }

  @ViewBuilder
  private func destination(_ route: AppRoute) -> some View {
    let visit = home.visit
    switch route {
    case .newCapture:
      if let model = visit?.captureModel {
        NewCaptureScreen(model: model, onDiscard: { visit?.discardNewCapture() })
      }
    case .scanSetup:
      if let model = visit?.captureModel {
        ScanSetupScreen(model: model)
      }
    case .sketchSource:
      if let visit, let model = visit.sketchModel {
        SketchSourceScreen(
          model: model,
          options: SketchSourceOptions(fixedPhoto: visit.fixedPhoto, caption: visit.sketchCaption(step: 2)))
      }
    case .sketchRooms:
      if let visit, let model = visit.sketchModel {
        SketchRoomsScreen(model: model, caption: visit.sketchCaption(step: 3))
      }
    case .sketchCheck:
      if let visit, let model = visit.sketchModel {
        SketchCheckScreen(model: model, caption: visit.sketchCaption(step: 4)) {
          visit.finishSketchFloor()
        }
      }
    case .overview:
      if let visit {
        OverviewRoute(visit: visit)
      }
    case .photos:
      if let visit, let model = visit.photoModel {
        PhotoStep(
          model: model, source: visit.services.photoSource,
          onDone: { visit.photosDone() },
          onRenameRooms: renameAction(visit, captureId: model.capture.ref.captureId))
          // Each saved photo is a change of revision n (its notice, §10.4).
          .onChange(of: model.savedCount) { visit.revisionChanged() }
      }
    case .controls:
      if let model = visit?.controlsModel {
        FieldControlsView(model: model)
      }
    case .checklist:
      if let visit, let report = visit.checklist {
        BeforeYouLeaveView(
          report: report, headerCaption: visit.checklistCaption, focus: visit.checklistFocus,
          isReadOnly: visit.flow.isReadOnly, sealedRevision: visit.flow.revision,
          onTakePhoto: { visit.checklistTakePhoto($0) },
          onAddControls: { visit.checklistAddControls($0) },
          // "Read" is hidden: a reading after the scan cannot be tied to it (critique R-22).
          onReadCompass: nil,
          onConfirmNoRoomsSkipped: visit.flow.isReadOnly
            ? nil : { visit.checklistConfirmNoRoomsSkipped() },
          onRenameRooms: renameAction(visit, captureId: nil),
          onFinish: { visit.reviewPackage() })
      }
    case .packageReady:
      if let visit {
        PackageReadyView(
          state: visit.packageReadyState,
          actions: PackageReadyActions(
            scanAnother: { visit.addFloor() }, seal: { visit.seal() },
            tryAgain: { visit.buildPlan() }))
      }
    case .revisionReady:
      if let visit {
        RevisionRoute(visit: visit)
      }
    case .packageStatus(let packageId):
      PackageRoute(home: home, packageId: packageId)
    case .floor(let areaKey):
      if let item = visit?.scanItem(areaKey: areaKey) {
        ScanViewer(item: item)
      }
    case .legacyScans(let workspaceId):
      LegacyScansView(
        title: home.legacyTitle(workspaceId: workspaceId),
        items: home.legacyScans(workspaceId: workspaceId),
        open: { home.openLegacyScan($0, workspaceId: workspaceId) })
    case .legacyScan(let workspaceId, let path):
      if let item = home.legacyScans(workspaceId: workspaceId).first(where: {
        $0.folder.path == path
      }) {
        ScanViewer(item: item)
      }
    }
  }

  /// Opens "Rename rooms" for one capture, or every capture when `captureId` is nil; nil (no
  /// button) when there is no room to rename.
  private func renameAction(_ visit: VisitModel, captureId: LowercaseUUID?) -> (() -> Void)? {
    guard visit.roomNamingDraft(captureId: captureId) != nil else { return nil }
    return { visit.renaming = visit.roomNamingDraft(captureId: captureId) }
  }
}

/// The Capture overview of the open visit.
private struct OverviewRoute: View {
  let visit: VisitModel

  var body: some View {
    if let state = visit.overviewState {
      CaptureOverviewScreen(
        state: state,
        actions: CaptureOverviewActions(
          openFloor: { visit.openFloor(areaKey: $0) }, addFloor: { visit.addFloor() },
          openCheck: { visit.openCheck($0) }, review: { visit.review() }))
    } else {
      ProgressView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .chapterScreenBackground()
    }
  }
}

/// Revision n, once its plan is built; until then its title and a spinner (or the error).
private struct RevisionRoute: View {
  let visit: VisitModel

  var body: some View {
    if let state = visit.revisionReviewState {
      RevisionReviewView(
        state: state,
        actions: RevisionReviewActions(
          keepEditing: { visit.backToOverview() }, seal: { visit.seal() }))
    } else {
      VStack(alignment: .leading, spacing: ChapterTheme.Metric.sectionGap) {
        if let error = visit.buildError {
          Banner(icon: .blocked, text: SealFailureText.make(reason: error))
          Button("Try again") { visit.buildPlan() }
            .buttonStyle(.chapter(.tinted))
        } else {
          ProgressView()
            .frame(maxWidth: .infinity, minHeight: 200)
        }
        Spacer()
      }
      .padding(.horizontal, ChapterTheme.Metric.screenPadding)
      .padding(.top, ChapterTheme.Metric.contentTop)
      .navigationTitle("Revision \(visit.flow.revision)")
      .navigationBarTitleDisplayMode(.large)
      .chapterBackChevronOnly()
      .chapterScreenBackground()
    }
  }
}

/// Package status, then Verdict received, of one package: the coordinator's snapshot, and what
/// the open visit can do with it (Try again, Re-seal as revision n+1, Add to this capture). A
/// package pushed on top of the visit's own screens (`HomeModel.openPackage`) only closes again:
/// "Continue revision n" goes back to the revision under it.
private struct PackageRoute: View {
  let home: HomeModel
  let packageId: LowercaseUUID
  @Environment(\.openURL) private var openURL

  var body: some View {
    let visit = home.visit
    let owned = visit?.packages.contains { $0.packageId == packageId } == true ? visit : nil
    let inFlow = owned?.routes.contains(.packageStatus(packageId)) == true ? owned : nil
    PackageStatusView(
      packageId: packageId, snapshot: home.snapshot(for: packageId),
      options: owned?.packageOptions(for: packageId, notificationsAllowed: home.notificationsAllowed)
        ?? standaloneOptions,
      actions: PackageStatusActions(
        // A package whose photos were erased cannot be uploaded again: no "Try again".
        retry: home.snapshot(for: packageId)?.photosErased == true
          ? nil : { home.runningCoordinator(for: packageId)?.retry() },
        reseal: inFlow.map { visit in { visit.resealAfterFailure() } },
        addToCapture: owned.map { visit -> () -> Void in
          guard inFlow != nil else { return { home.closePackageOnTop(packageId) } }
          return { visit.addToCapture() }
        },
        openInHub: { openURL($0) }))
      .task(id: packageId) { home.preparePackage(packageId) }
      .onAppear { PackageRouter.shared.visiblePackageId = packageId }
      .onDisappear {
        if PackageRouter.shared.visiblePackageId == packageId {
          PackageRouter.shared.visiblePackageId = nil
        }
      }
  }

  private var standaloneOptions: PackageStatusOptions {
    var options = PackageStatusOptions()
    options.notificationsAllowed = home.notificationsAllowed
    options.canReseal = false
    options.revision = .hidden
    return options
  }
}

/// The scans of a v1 visit that kept no capture record: each opens its Floorplan.
private struct LegacyScansView: View {
  let title: String
  let items: [ScanItem]
  let open: (ScanItem) -> Void

  var body: some View {
    ScrollView {
      ChapterSection(
        header: "Scans",
        footer: "This visit was scanned before the app kept its capture record (HUB project, "
          + "address and operator), so it cannot be packaged. Its files stay on this phone."
      ) {
        ForEach(items) { item in
          NavigationRow(
            title: item.title,
            subtitle: item.scanDate.formatted(date: .abbreviated, time: .shortened)
          ) {
            open(item)
          }
          .accessibilityIdentifier("legacy.scan.\(item.folder.lastPathComponent)")
        }
      }
      .padding(.horizontal, ChapterTheme.Metric.screenPadding)
      .padding(.top, ChapterTheme.Metric.contentTop)
      .chapterContentWidth()
    }
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.large)
    .chapterBackChevronOnly()
    .chapterScreenBackground()
  }
}

/// An error of the capture or field screens: ■ and the text, at the bottom.
private struct MessageToast: View {
  let text: String

  var body: some View {
    HStack(alignment: .top, spacing: ChapterTheme.Metric.statusGlyphGap) {
      StatusGlyph(.missing).padding(.top, 3)
      Text(text)
        .chapterTextStyle(.footnote)
        .foregroundStyle(ChapterTheme.Color.blocked)
    }
    .padding(12)
    .background(
      ChapterTheme.Color.surface, in: RoundedRectangle(cornerRadius: ChapterTheme.Metric.chipRadius))
    .padding(.bottom, 96)
    .padding(.horizontal, ChapterTheme.Metric.screenPadding)
    .accessibilityElement(children: .combine)
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

/// The title of the home's back item: what VoiceOver says for the system back chevron of every
/// screen pushed on the Captures home ("Back to captures", phone-capture §3.5 and Appendix A).
/// The chevron-only style (`chapterBackChevronOnly`) keeps it off the screen; the system back
/// stays (one header pattern, critique R-18c). SwiftUI has no modifier for it, so it is set on
/// the home's own navigation item.
private struct BackButtonTitle: UIViewControllerRepresentable {
  let title: String

  func makeUIViewController(context: Context) -> Controller {
    Controller(backTitle: title)
  }

  func updateUIViewController(_ controller: Controller, context: Context) {
    controller.backTitle = title
    controller.apply()
  }

  final class Controller: UIViewController {
    var backTitle: String

    init(backTitle: String) {
      self.backTitle = backTitle
      super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
      view = UIView()
      view.isUserInteractionEnabled = false
      view.isAccessibilityElement = false
    }

    override func didMove(toParent parent: UIViewController?) {
      super.didMove(toParent: parent)
      apply()
    }

    override func viewWillAppear(_ animated: Bool) {
      super.viewWillAppear(animated)
      apply()
    }

    /// The navigation item of the stack's root: the home's hosting controller.
    func apply() {
      guard let root = navigationController?.viewControllers.first else { return }
      if root.navigationItem.backButtonTitle != backTitle {
        root.navigationItem.backButtonTitle = backTitle
      }
    }
  }
}

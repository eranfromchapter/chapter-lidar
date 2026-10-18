import AppCore
import CaptureContract
import CaptureCore
import CaptureRoomPlan
import FieldKitUI
import Foundation
import Observation
import PackageCore
import PackageTransport
import StationClient

/// What the app runs on: the station client, the project list, the blob transport, the scan
/// session factory and the camera. `live` is the real phone; the UI-test variant (Debug only)
/// is built in UITestEnvironment.swift.
struct AppServices {
  var station: StationAPI
  var projects: ProjectStore
  var blobTransport: any BlobTransport
  /// Nil in the UI-test mode (stub token, no MSAL).
  var signIn: EntraSignIn?
  var capabilities: DeviceCapabilities
  var device: DeviceInfo
  var makeSession: @MainActor (CaptureSessionConfiguration) throws -> any CaptureSession
  var photoSource: PhotoSource
  /// Fixed operator for the UI-test mode; nil means "the signed-in Entra account".
  var fixedOperator: SignedInOperator?
}

/// Where photos come from: the app's own camera, or (UI tests) the fixture's photo bytes.
enum PhotoSource {
  case camera(CameraEngine)
  case fixed(@Sendable () async throws -> Data)
}

/// App-wide state: configuration, sign-in, the current visit and background uploads.
@MainActor
@Observable
final class AppModel {
  enum Screen {
    case notConfigured([ConfigurationIssue])
    case signIn
    case visit(VisitModel)
  }

  private(set) var screen: Screen
  private(set) var isSigningIn = false
  private(set) var signInMessage: String? = nil
  /// Sealed packages whose upload the station has not confirmed yet (they stay on disk and
  /// resume after sign-in; sign-out deletes nothing).
  private(set) var pendingUploadCount = 0

  @ObservationIgnored private var services: AppServices? = nil
  @ObservationIgnored private var signedIn: SignedInOperator? = nil
  @ObservationIgnored private var uploads: [String: UploadCoordinator] = [:]
  /// The visit on screen when the station asked for sign-in again; shown again after sign-in.
  @ObservationIgnored private var suspendedVisit: VisitModel? = nil
  @ObservationIgnored let visitsRoot: URL

  private init(screen: Screen, services: AppServices?, visitsRoot: URL) {
    self.screen = screen
    self.services = services
    self.visitsRoot = visitsRoot
  }

  /// Reads the launch mode and the configuration. A missing or placeholder value shows "App is
  /// not configured" and nothing is created that could send a request.
  static func make() -> AppModel {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let mode = LaunchModeResolver.resolve(
      arguments: ProcessInfo.processInfo.arguments, isDebugBuild: AppBuild.isDebug)
    switch mode {
    case .uiTestReplay(let fixture):
      #if DEBUG
        let root = support.appendingPathComponent("UITestVisits-\(UUID().uuidString)", isDirectory: true)
        let services = UITestEnvironment.services(fixture: fixture, cacheRoot: root)
        let model = AppModel(screen: .signIn, services: services, visitsRoot: root)
        model.signedIn = services.fixedOperator
        model.startNewVisit()
        return model
      #else
        // Unreachable: LaunchModeResolver returns .live for Release builds.
        break
      #endif
    case .live:
      break
    }

    let visitsRoot = support.appendingPathComponent("Visits", isDirectory: true)
    guard
      case .configured(let configuration) = ConfigurationLoader.load(
        infoDictionary: Bundle.main.infoDictionary)
    else {
      if case .notConfigured(let issues) = ConfigurationLoader.load(
        infoDictionary: Bundle.main.infoDictionary)
      {
        return AppModel(screen: .notConfigured(issues), services: nil, visitsRoot: visitsRoot)
      }
      return AppModel(screen: .notConfigured([]), services: nil, visitsRoot: visitsRoot)
    }
    let signIn: EntraSignIn
    do {
      signIn = try EntraSignIn(configuration: configuration)
    } catch {
      return AppModel(
        screen: .notConfigured([.invalid(.entraClientId, "MSAL refused the configuration.")]),
        services: nil, visitsRoot: visitsRoot)
    }
    let station = StationAPI(
      configuration: configuration.station, tokenProvider: EntraTokenProvider(signIn: signIn))
    let services = AppServices(
      station: station,
      projects: ProjectStore(
        source: station,
        cacheDirectory: support.appendingPathComponent("StationCache", isDirectory: true)),
      blobTransport: BackgroundUploads.shared.transport, signIn: signIn,
      capabilities: DeviceCapabilities.current(), device: DeviceInfo.current(),
      makeSession: { _ in LiveCaptureSession() }, photoSource: .camera(CameraEngine()),
      fixedOperator: nil)
    let model = AppModel(screen: .signIn, services: services, visitsRoot: visitsRoot)
    if let current = signIn.currentOperator() {
      model.signedIn = current
      model.startNewVisit()
    }
    return model
  }

  // MARK: Sign-in

  func signIn() async {
    guard let signIn = services?.signIn, !isSigningIn else { return }
    isSigningIn = true
    signInMessage = nil
    defer { isSigningIn = false }
    do {
      signedIn = try await signIn.signIn()
      if let visit = suspendedVisit {
        suspendedVisit = nil
        screen = .visit(visit)
      } else {
        startNewVisit()
      }
      for upload in uploads.values { upload.retry() }
    } catch is SignInRequired {
      signInMessage = "Sign-in was not completed."
    } catch {
      signInMessage = String(describing: error)
    }
  }

  /// Removes the account from MSAL's Keychain cache and the offline project list, then shows the
  /// sign-in screen. Deletes no file: sealed packages not yet confirmed by the station stay in
  /// `visitsRoot` and their uploads resume after the next sign-in.
  func signOut() async {
    services?.signIn?.signOut()
    try? await services?.projects.clearCache()
    signedIn = nil
    suspendedVisit = nil
    screen = .signIn
  }

  /// A station call said the token is no longer accepted.
  func requireSignIn() {
    guard services?.signIn != nil else { return }
    if case .visit(let visit) = screen {
      suspendedVisit = visit
    }
    signInMessage = "Sign in again to continue."
    screen = .signIn
  }

  func handleOpenURL(_ url: URL) {
    _ = EntraSignIn.handle(url)
  }

  func didBecomeActive() {
    for upload in uploads.values { upload.retry() }
  }

  // MARK: Visits

  /// A new visit starts at "New capture". If a sealed package is still waiting for the
  /// station's confirmation, its upload resumes and its status is shown first.
  func startNewVisit(showPendingUpload: Bool = true) {
    guard let services, let signedIn else { return }
    let pending = PendingUploads.find(visitsRoot: visitsRoot)
    for item in pending { _ = coordinator(for: item.package, dealId: item.dealId) }
    do {
      let workspace = try VisitWorkspace.create(in: visitsRoot)
      let visit = try VisitModel(
        services: services, workspace: workspace, operatorInfo: signedIn, app: self)
      if showPendingUpload, let newest = pending.first,
        let coordinator = uploads[newest.package.packageId.rawValue]
      {
        visit.showUpload(of: newest.package, coordinator: coordinator)
      }
      screen = .visit(visit)
    } catch {
      signInMessage = "The visit folder could not be created: \(error.localizedDescription)"
      screen = .signIn
    }
  }

  /// One coordinator per sealed package for the app's lifetime; started at once.
  func coordinator(for package: SealedPackage, dealId: String) -> UploadCoordinator {
    let key = package.packageId.rawValue
    if let existing = uploads[key] { return existing }
    guard let services else { fatalError("uploads need configured services") }
    let coordinator = UploadCoordinator(
      package: package, dealId: dealId,
      service: StationUploadService(client: services.station),
      transport: services.blobTransport,
      statusSource: StationStatusSource(client: services.station),
      onChange: { [weak self] snapshot in
        Task { @MainActor in self?.uploadChanged(snapshot) }
      })
    uploads[key] = coordinator
    coordinator.start()
    countPendingUploads()
    return coordinator
  }

  private func countPendingUploads() {
    pendingUploadCount = uploads.values.filter { !$0.snapshot.isConfirmedByStation }.count
  }

  private func uploadChanged(_ snapshot: UploadSnapshot) {
    countPendingUploads()
    if case .visit(let visit) = screen {
      visit.uploadChanged(snapshot)
    }
    if snapshot.activity == .signInRequired {
      requireSignIn()
    }
  }
}

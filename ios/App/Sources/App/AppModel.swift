import AppCore
import CaptureCompass
import CaptureContract
import CaptureCore
import CaptureRoomPlan
import FieldKitUI
import Foundation
import Observation
import PackageCore
import PackageTransport
import StationClient
import WalkthroughUI

/// What the app runs on: the station client, the project list, the blob transport, the scan
/// session factory, the compass and the camera. `live` is the real phone; the UI-test and
/// field-test variants (Debug only) are built in Debug/.
struct AppServices {
  var station: StationAPI
  var projects: ProjectStore
  var blobTransport: any BlobTransport
  /// Nil in the UI-test and field-test modes (stub token, no MSAL).
  var signIn: EntraSignIn?
  var capabilities: DeviceCapabilities
  var device: DeviceInfo
  var makeSession: @MainActor @Sendable (CaptureSessionConfiguration) throws -> any CaptureSession
  var photoSource: PhotoSource
  /// The app's one compass (compass §3.5): `CompassService` on the phone, `FakeCompass` in UI
  /// tests. It reads the step 2 pre-check and, through `CompassPhotoHeading`, the photo heading;
  /// the scan session reads it too (`LiveCaptureSession(compass:)`). Nil: no compass row.
  var compass: (any CompassProviding)?
  /// Fixed operator for the UI-test and field-test modes; nil means "the signed-in Entra
  /// account".
  var fixedOperator: SignedInOperator?
  /// Ask for the verdict notification after the first seal (phone-package Q10). Off in UI tests,
  /// where the system's permission alert would cover the screens under test.
  var asksForNotifications = true
  /// Seconds without a change before revision n's notice is rebuilt and sent (phone-package
  /// §10.4: 10 s; shorter in UI tests).
  var revisionNoticeDelay: TimeInterval = 10
  /// Erases the photo blobs the in-process stub station holds ("Delete all photos"); set by the
  /// field-test and UI-test environments only. Returns how many were removed.
  var stationPhotoBlobs: (@Sendable () -> Int)? = nil
  /// The AR walkthrough's session (spec F15): ARKit world tracking on the phone, a scripted
  /// replay in UI tests.
  var makeWalkthroughSession: @MainActor () -> any WalkthroughSession = { LiveWalkthroughSession() }
  /// The phone runs ARKit world tracking (every iPhone with iOS 17): "Walk the rooms with the
  /// camera" can be chosen. The LiDAR gate (`DeviceGate`) is for scans only.
  var canWalk: Bool = LiveWalkthroughSession.isSupported

  /// The photo step's heading provider over `compass`.
  @MainActor var photoHeading: PhotoHeadingProviding? {
    compass.map { CompassPhotoHeading(compass: $0) }
  }
}

/// Where photos come from: the app's own camera, or (UI tests) the fixture's photo bytes.
enum PhotoSource {
  case camera(CameraEngine)
  case fixed(@Sendable () async throws -> Data)
}

/// App-wide state: configuration, sign-in, the Captures home and the background uploads (one
/// coordinator per sealed package for the app's lifetime).
@MainActor
@Observable
final class AppModel {
  enum Screen {
    case notConfigured([ConfigurationIssue])
    case signIn
    case home(HomeModel)
  }

  private(set) var screen: Screen
  private(set) var isSigningIn = false
  private(set) var signInMessage: String? = nil
  /// Sealed packages whose upload the station has not confirmed yet (they stay on disk and
  /// resume after sign-in; sign-out deletes nothing).
  private(set) var pendingUploadCount = 0

  @ObservationIgnored private(set) var services: AppServices? = nil
  @ObservationIgnored private(set) var signedIn: SignedInOperator? = nil
  @ObservationIgnored private var uploads: [String: UploadCoordinator] = [:]
  /// The home shown when the station asked for sign-in again; shown again after sign-in, with
  /// whatever visit was open.
  @ObservationIgnored private var suspendedHome: HomeModel? = nil
  @ObservationIgnored let visitsRoot: URL
  #if DEBUG
    /// "Delete all photos": where the photos are. Set in the field-test and UI-test modes only,
    /// so a live (and every Release) build never offers it.
    @ObservationIgnored private(set) var photoDeletion: PhotoDeletion? = nil
  #endif

  private init(screen: Screen, services: AppServices?, visitsRoot: URL) {
    self.screen = screen
    self.services = services
    self.visitsRoot = visitsRoot
  }

  /// Reads the launch mode and the configuration. A missing or placeholder value shows "App is
  /// not configured" and nothing is created that could send a request.
  static func make() -> AppModel {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let arguments = ProcessInfo.processInfo.arguments
    let mode = LaunchModeResolver.resolve(
      arguments: arguments, isDebugBuild: AppBuild.isDebug,
      fieldTestFlag: Bundle.main.object(forInfoDictionaryKey: LaunchModeResolver.fieldTestKey)
        as? String)
    switch mode {
    case .fieldTest:
      #if DEBUG
        // The visits of the field-test builds before v2 are here too: the Captures home lists
        // them (VisitStore migrates each to visit.json on the first read).
        let root = support.appendingPathComponent("FieldTestVisits", isDirectory: true)
        let services = FieldTestEnvironment.services(cacheRoot: root)
        let model = signedInModel(services: services, visitsRoot: root)
        // The visits of a live build on this phone, if any, hold photos too.
        model.photoDeletion = PhotoDeletion(
          visitsRoots: [root, support.appendingPathComponent("Visits", isDirectory: true)],
          stationPhotoBlobs: services.stationPhotoBlobs)
        return model
      #else
        break
      #endif
    case .uiTestReplay(let fixture):
      #if DEBUG
        let options = UITestLaunchOptions(arguments: arguments)
        let root = support.appendingPathComponent(options.visitsFolderName(), isDirectory: true)
        if options.seedsV1Visits {
          let fixture = Bundle.main.resourceURL!.appendingPathComponent("package", isDirectory: true)
          try? UITestV1Visits.seed(in: root, fixture: fixture)
        }
        let services = UITestEnvironment.services(
          fixture: fixture, cacheRoot: root, options: options)
        let model = signedInModel(services: services, visitsRoot: root)
        model.photoDeletion = PhotoDeletion(
          visitsRoots: [root], stationPhotoBlobs: services.stationPhotoBlobs)
        return model
      #else
        // Unreachable: LaunchModeResolver returns .live for Release builds.
        break
      #endif
    case .live:
      break
    }

    let visitsRoot = support.appendingPathComponent("Visits", isDirectory: true)
    let configuration: AppConfiguration
    switch ConfigurationLoader.load(infoDictionary: Bundle.main.infoDictionary) {
    case .configured(let loaded):
      configuration = loaded
    case .notConfigured(let issues):
      return AppModel(screen: .notConfigured(issues), services: nil, visitsRoot: visitsRoot)
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
    let compass = CompassService()
    let services = AppServices(
      station: station,
      projects: ProjectStore(
        source: station,
        cacheDirectory: support.appendingPathComponent("StationCache", isDirectory: true)),
      blobTransport: BackgroundUploads.shared.transport, signIn: signIn,
      capabilities: DeviceCapabilities.current(), device: DeviceInfo.current(),
      makeSession: { _ in LiveCaptureSession(compass: compass) },
      photoSource: .camera(CameraEngine()), compass: compass, fixedOperator: nil)
    let model = AppModel(screen: .signIn, services: services, visitsRoot: visitsRoot)
    model.configureBackgroundRefresh()
    if let current = signIn.currentOperator() {
      model.signedIn = current
      model.showHome()
    }
    return model
  }

  /// The UI-test and field-test modes: the stub operator is signed in from the start.
  private static func signedInModel(services: AppServices, visitsRoot: URL) -> AppModel {
    let model = AppModel(screen: .signIn, services: services, visitsRoot: visitsRoot)
    model.configureBackgroundRefresh()
    model.signedIn = services.fixedOperator
    model.showHome()
    return model
  }

  private func configureBackgroundRefresh() {
    guard let services else { return }
    VerdictRefresh.shared.configure(
      visitsRoot: visitsRoot, source: StationStatusSource(client: services.station))
  }

  // MARK: Sign-in

  func signIn() async {
    if services?.signIn == nil, let fixed = services?.fixedOperator {
      // UI-test and field-test modes: the stub operator signs straight back in.
      signedIn = fixed
      showHome()
      return
    }
    guard let signIn = services?.signIn, !isSigningIn else { return }
    isSigningIn = true
    signInMessage = nil
    defer { isSigningIn = false }
    do {
      signedIn = try await signIn.signIn()
      showHome()
      for upload in uploads.values { upload.retry() }
    } catch is SignInRequired {
      signInMessage = "Sign-in was not completed."
    } catch {
      signInMessage = String(describing: error)
    }
  }

  /// Removes the account from MSAL's Keychain cache and the offline project list, then shows the
  /// sign-in screen. Deletes no file: captures in progress and sealed packages not yet
  /// confirmed by the station stay in `visitsRoot`; their uploads resume after the next sign-in.
  func signOut() async {
    services?.signIn?.signOut()
    try? await services?.projects.clearCache()
    signedIn = nil
    suspendedHome = nil
    PackageRouter.shared.onOpenPackage = nil
    screen = .signIn
  }

  /// A station call said the token is no longer accepted.
  func requireSignIn() {
    guard services?.signIn != nil else { return }
    if case .home(let home) = screen {
      suspendedHome = home
    }
    signInMessage = "Sign in again to continue."
    screen = .signIn
  }

  func handleOpenURL(_ url: URL) {
    _ = EntraSignIn.handle(url)
  }

  /// The app is in the foreground again: the uploads retry and the next-revision notices go
  /// again (phone-package §10.4).
  func didBecomeActive() {
    for upload in uploads.values { upload.retry() }
    if case .home(let home) = screen { home.appBecameActive() }
  }

  // MARK: Home

  /// The Captures home (the app's root): the uploads of sealed packages still waiting for the
  /// station resume first. After a sign-in that the station asked for, the home comes back as
  /// it was (with its open visit).
  func showHome() {
    guard let services, let signedIn else { return }
    for item in PendingUploads.find(visitsRoot: visitsRoot) {
      _ = coordinator(for: item.package, dealId: item.dealId)
    }
    let home: HomeModel
    if let suspended = suspendedHome {
      home = suspended
      suspendedHome = nil
    } else {
      home = HomeModel(app: self, services: services, operatorInfo: signedIn)
    }
    screen = .home(home)
    PackageRouter.shared.onOpenPackage = { [weak home] id in home?.openPackage(id: id) }
  }

  // MARK: Delete all photos

  #if DEBUG
    /// Where "Delete all photos" erases (field-test and UI-test modes).
    struct PhotoDeletion {
      var visitsRoots: [URL]
      var stationPhotoBlobs: (@Sendable () -> Int)?

      /// Every place on the phone that can hold photo bytes (`PhotoEraser`): the visits, the
      /// background uploads' scratch copies and the app switcher's snapshots, the temporary
      /// folder and the caches.
      var eraser: PhotoEraser {
        let fileManager = FileManager.default
        let library = fileManager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return PhotoEraser(
          visitsRoots: visitsRoots,
          scratchFolders: [
            caches.appendingPathComponent("upload-scratch", isDirectory: true),
            library.appendingPathComponent("SplashBoard/Snapshots", isDirectory: true),
            caches.appendingPathComponent("Snapshots", isDirectory: true),
          ],
          sweptFolders: [fileManager.temporaryDirectory, caches])
      }
    }

    /// "Delete all photos" (field-test and UI-test modes): every site photo the app holds goes,
    /// on disk, in the stub station and in memory; scans, plans, field controls, room names and
    /// capture records stay. The open visit is closed first (its photo store and a photo being
    /// labeled go with it) and no upload runs while the files go; afterwards the uploads go on
    /// (a package the station had not confirmed stops: "Photos erased on this phone").
    /// Returns the line the home shows ("Deleted 3 photos").
    func deleteAllPhotos() async -> String {
      guard let photoDeletion else { return DeletePhotosText.result(deleted: 0) }
      if case .home(let home) = screen { home.closeVisit() }
      suspendedHome?.closeVisit()
      PhotoThumbnails.removeAll()
      let running = Array(uploads.values)
      for upload in running { await upload.cancelAndWait() }
      let eraser = photoDeletion.eraser
      var result = await Task.detached(priority: .userInitiated) { eraser.eraseAll() }.value
      result.stationBlobs = photoDeletion.stationPhotoBlobs?() ?? 0
      for upload in running { upload.retry() }
      countPendingUploads()
      return result.message
    }
  #endif

  // MARK: Uploads

  /// One coordinator per sealed package for the app's lifetime; started at once (a package the
  /// station confirmed only follows its verdict; a superseded one never runs).
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
      },
      onVerdict: { notification in VerdictNotifier.shared.post(notification) })
    uploads[key] = coordinator
    coordinator.start()
    countPendingUploads()
    return coordinator
  }

  /// The running coordinator of a package, if any.
  func runningCoordinator(for packageId: LowercaseUUID) -> UploadCoordinator? {
    uploads[packageId.rawValue]
  }

  /// The latest snapshots of every coordinator, by package (the Captures home rows).
  var liveSnapshots: [LowercaseUUID: UploadSnapshot] {
    Dictionary(
      uploads.values.map { ($0.package.packageId, $0.snapshot) }, uniquingKeysWith: { a, _ in a })
  }

  private func countPendingUploads() {
    // A package whose photos were erased before the station confirmed it never uploads.
    pendingUploadCount = uploads.values.filter {
      !$0.snapshot.isConfirmedByStation && !$0.snapshot.isSuperseded && !$0.snapshot.photosErased
    }.count
  }

  private func uploadChanged(_ snapshot: UploadSnapshot) {
    countPendingUploads()
    VerdictRefresh.shared.scheduleIfWaiting(snapshot)
    if case .home(let home) = screen {
      home.uploadChanged(snapshot)
    } else {
      suspendedHome?.uploadChanged(snapshot)
    }
    if snapshot.activity == .signInRequired {
      requireSignIn()
    }
  }
}

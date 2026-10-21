import AppCore
import BackgroundTasks
import CaptureContract
import Foundation
import PackageTransport
import UIKit
import UserNotifications

/// Background uploads: one `BackgroundBlobTransport` per session identifier for the app's
/// lifetime, so iOS can hand back the events of uploads that finished while the app was
/// suspended or killed.
final class BackgroundUploads: @unchecked Sendable {
  static let shared = BackgroundUploads()

  /// Session identifier of the package uploads.
  static let identifier = "com.hellochapter.capture.package-upload"

  /// Created on first use, then only read. (Touched from the main thread only.)
  private(set) lazy var transport: BackgroundBlobTransport = {
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    return BackgroundBlobTransport(
      identifier: Self.identifier,
      scratchDirectory: caches.appendingPathComponent("upload-scratch", isDirectory: true))
  }()

  private init() {}
}

/// Where a tapped "Verdict: …" notification leads (phone-package §7): the entry
/// `openPackage(id:)`, which the app's navigation handles (Package status, or Verdict received
/// once the verdict is known). A tap that arrives before the app can navigate (a cold launch)
/// waits here until `onOpenPackage` is set.
@MainActor
final class PackageRouter {
  static let shared = PackageRouter()

  /// The app's navigation to a package. Setting it delivers a tap that arrived earlier.
  var onOpenPackage: ((LowercaseUUID) -> Void)? {
    didSet {
      if let pending, let onOpenPackage {
        self.pending = nil
        onOpenPackage(pending)
      }
    }
  }

  /// The package whose Package status or Verdict received is on screen: its verdict banner is
  /// not shown while the operator looks at it.
  var visiblePackageId: LowercaseUUID?

  private var pending: LowercaseUUID?

  private init() {}

  /// Opens the package's status or verdict screen.
  func openPackage(id: LowercaseUUID) {
    if let onOpenPackage {
      onOpenPackage(id)
    } else {
      pending = id
    }
  }
}

/// The local notification "Verdict: {Word}" (phone-package §7, addendum C10). Posted once per
/// verdict: callers mark it in the package's status cache (`StationStatusStore.markNotified`,
/// done by `UploadCoordinator` and `VerdictRefresh`).
final class VerdictNotifier: Sendable {
  static let shared = VerdictNotifier()

  private init() {}

  /// Asks for permission after the first successful seal (§3.4 step 2, Q10). iOS remembers the
  /// answer and shows the question only once.
  func requestPermission() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
  }

  /// False when the operator turned the notifications off: the screens then say "Open the app to
  /// see the verdict."
  func notificationsAllowed() async -> Bool {
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    return settings.authorizationStatus != .denied
  }

  func post(_ notification: VerdictNotification) {
    let content = UNMutableNotificationContent()
    content.title = notification.title
    content.body = notification.body
    content.sound = .default
    content.threadIdentifier = notification.threadIdentifier
    content.categoryIdentifier = VerdictNotification.category
    content.userInfo = notification.userInfo
    UNUserNotificationCenter.current().add(
      UNNotificationRequest(
        identifier: notification.requestIdentifier, content: content, trigger: nil))
  }
}

/// The background refresh of phone-package §7: `BGAppRefreshTask`
/// `com.hellochapter.capture.verdict-refresh`, registered at launch, scheduled (earliest 15 min)
/// while a package the station confirmed has no verdict or no final publication. Each run asks
/// the station about those packages (`StationStatusRefresh`), updates their status caches, posts
/// the verdict notifications and schedules the next run while something is still waiting.
final class VerdictRefresh: @unchecked Sendable {
  static let shared = VerdictRefresh()

  /// Guarded by `lock`.
  private let lock = NSLock()
  private var visitsRoot: URL?
  private var source: (any PackageStatusSource)?

  private init() {}

  /// The task can run only when Info.plist permits its identifier (UIBackgroundModes `fetch`,
  /// `BGTaskSchedulerPermittedIdentifiers`); registering another identifier would stop the app.
  static var isPermitted: Bool {
    let permitted =
      Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String]
    return permitted?.contains(StationStatusRefresh.taskIdentifier) == true
  }

  /// Where the packages are and how to ask the station; set by the app once it is configured.
  func configure(visitsRoot: URL, source: any PackageStatusSource) {
    lock.withLock {
      self.visitsRoot = visitsRoot
      self.source = source
    }
  }

  /// Registers the launch handler. Call before the end of `didFinishLaunching`.
  func register() {
    guard Self.isPermitted else { return }
    BGTaskScheduler.shared.register(
      forTaskWithIdentifier: StationStatusRefresh.taskIdentifier, using: nil
    ) { task in
      guard let task = task as? BGAppRefreshTask else {
        task.setTaskCompleted(success: false)
        return
      }
      self.handle(task)
    }
  }

  /// Asks iOS for a run in 15 minutes or later. Call when a package is confirmed by the station
  /// and not settled (`UploadSnapshot`), and after each run that still waits.
  func schedule() {
    guard Self.isPermitted else { return }
    let request = BGAppRefreshTaskRequest(identifier: StationStatusRefresh.taskIdentifier)
    request.earliestBeginDate = Date(timeIntervalSinceNow: StationStatusRefresh.interval)
    try? BGTaskScheduler.shared.submit(request)
  }

  /// Schedules a run when `snapshot` is a package the station confirmed that has not settled.
  func scheduleIfWaiting(_ snapshot: UploadSnapshot) {
    guard snapshot.isConfirmedByStation, !snapshot.isSuperseded else { return }
    if snapshot.verdict == nil || snapshot.station?.publication?.status.isFinal != true {
      schedule()
    }
  }

  /// One refresh of every followed package; true while something still waits.
  func run() async -> Bool {
    guard let (visitsRoot, source) = lock.withLock({ () -> (URL, any PackageStatusSource)? in
      guard let visitsRoot, let source else { return nil }
      return (visitsRoot, source)
    }) else { return false }
    let items = StationStatusRefresh.followed(visitsRoot: visitsRoot)
    let outcome = await StationStatusRefresh.refresh(items, source: source)
    for notification in outcome.notifications {
      VerdictNotifier.shared.post(notification)
      let store = items.first { $0.package.packageId == notification.packageId }?.store
      try? store?.markNotified(notification.verdictId)
    }
    return outcome.stillFollowing
  }

  private func handle(_ task: BGAppRefreshTask) {
    // BGTask is not Sendable; it is only completed from the work below, once.
    let refresh = UncheckedTask(task: task)
    let work = Task {
      let stillWaiting = await self.run()
      if stillWaiting { self.schedule() }
      refresh.task.setTaskCompleted(success: !Task.isCancelled)
    }
    task.expirationHandler = { work.cancel() }
  }

  private struct UncheckedTask: @unchecked Sendable {
    let task: BGAppRefreshTask
  }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    VerdictRefresh.shared.register()
    return true
  }

  /// iOS relaunches the app (or wakes it) when background upload tasks finish. The completion
  /// handler is called by the transport once the session delivered all its events.
  func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    guard identifier == BackgroundUploads.identifier else {
      completionHandler()
      return
    }
    BackgroundUploads.shared.transport.setBackgroundEventsCompletionHandler {
      completionHandler()
    }
  }

  // MARK: Notifications

  /// In the foreground the banner shows unless the package's own screen is on screen.
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    let packageId = VerdictNotification.packageId(from: notification.request.content.userInfo)
    let visible = await MainActor.run {
      packageId != nil && packageId == PackageRouter.shared.visiblePackageId
    }
    return visible ? [] : [.banner, .list, .sound]
  }

  /// A tap opens the package (Verdict received).
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
  ) async {
    let packageId = VerdictNotification.packageId(
      from: response.notification.request.content.userInfo)
    guard let packageId else { return }
    await MainActor.run { PackageRouter.shared.openPackage(id: packageId) }
  }
}

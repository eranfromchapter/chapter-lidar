import Foundation
import PackageTransport
import UIKit

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

final class AppDelegate: NSObject, UIApplicationDelegate {
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
}

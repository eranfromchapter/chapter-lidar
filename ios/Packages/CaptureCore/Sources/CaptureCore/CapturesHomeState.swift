import Foundation

/// The status at the end of a row or a check: shape and word, never colour alone.
public struct RowStatusValue: Hashable, Sendable {
  public enum Kind: String, Hashable, Sendable {
    /// ● Done / Verified / Recorded / Ready.
    case done
    /// ▲ Partly / Approx. / Limited / Not verified.
    case partly
    /// ■ Missing / Open / Blocked / Stopped.
    case missing
    /// ○ Checking.
    case waiting
  }

  public var kind: Kind
  public var word: String

  public init(_ kind: Kind, _ word: String) {
    self.kind = kind
    self.word = word
  }
}

/// What the Captures home shows (phone-capture §3.1 with critique R-28): plain data, so the
/// screen is drawn from fixtures in snapshot tests. The app's `CaptureLibrary` reads the disk and
/// builds it with `Row.inProgress` / `Row.sealed`, which hold the words of the R-28 table.
public struct CapturesHomeState: Hashable, Sendable {
  public static let footnote =
    "Files stay on this phone until the station confirms each one. Verdict details are in the HUB."
  public static let emptyText = "No captures on this phone yet."
  public static let emptyFootnote = "Tap New capture to scan a floor or room."
  /// The account dialog's message while sealed packages wait for the station.
  public static let pendingUploadsMessage = "Uploads resume after you sign in again."

  /// One capture.
  public struct Row: Hashable, Sendable, Identifiable {
    /// Where a tap leads.
    public enum Destination: Hashable, Sendable {
      /// In progress: the Capture overview.
      case overview
      /// Sealed: Verdict received.
      case verdict
    }

    /// The visit workspace's id.
    public var id: String
    /// The project title (R-29).
    public var title: String
    public var subtitle: String
    /// The upload bar's fraction (uploading and paused rows), nil for no bar.
    public var progress: Double?
    public var status: RowStatusValue?
    public var destination: Destination
    /// Newest activity (in progress) or `sealedAt` (sealed): rows are newest first.
    public var sortDate: Date

    public init(
      id: String, title: String, subtitle: String, progress: Double? = nil,
      status: RowStatusValue? = nil, destination: Destination, sortDate: Date
    ) {
      self.id = id
      self.title = title
      self.subtitle = subtitle
      self.progress = progress
      self.status = status
      self.destination = destination
      self.sortDate = sortDate
    }

    /// An "In progress" case of the R-28 table.
    public enum Progress: Hashable, Sendable {
      case notSealed
      /// `bytes` is the upload summary's text, e.g. "512 of 768 MB".
      case uploading(bytes: String, fraction: Double)
      /// Paused offline or by the station.
      case paused(bytes: String, fraction: Double)
      case signInRequired
      /// The upload stopped for good (fatal).
      case uploadStopped
      /// Every file confirmed, no verdict yet (checks running or a check error).
      case checking
      /// Revision `next` started after a verdict and is not sealed yet.
      case revisionStarted(next: Int)
    }

    /// A station verdict.
    public enum Verdict: String, Hashable, Sendable {
      case ready
      case limited
      case blocked
    }

    /// An "In progress" row; `count` is `CaptureCountText` ("2 floors", "1 floor and 1 room").
    public static func inProgress(
      id: String, title: String, count: String, _ progress: Progress, activity: Date
    ) -> Row {
      let subtitle: String
      var fraction: Double?
      var status: RowStatusValue?
      switch progress {
      case .notSealed:
        subtitle = "\(count) · not sealed yet"
      case .uploading(let bytes, let value):
        subtitle = "\(count) · uploading · \(bytes)"
        fraction = value
      case .paused(let bytes, let value):
        subtitle = "\(count) · upload paused · \(bytes)"
        fraction = value
      case .signInRequired:
        subtitle = "\(count) · sign in to upload"
      case .uploadStopped:
        subtitle = "\(count) · upload stopped"
        status = RowStatusValue(.missing, "Stopped")
      case .checking:
        subtitle = "\(count) · uploaded · checks running"
        status = RowStatusValue(.waiting, "Checking")
      case .revisionStarted(let next):
        subtitle = "\(count) · revision \(next) not sealed yet"
      }
      return Row(
        id: id, title: title, subtitle: subtitle, progress: fraction, status: status,
        destination: .overview, sortDate: activity)
    }

    /// A "Sealed" row: revision `revision` has a verdict.
    public static func sealed(
      id: String, title: String, revision: Int, sealedAt: Date, verdict: Verdict,
      timeZone: TimeZone = .current
    ) -> Row {
      let subtitle: String
      let status: RowStatusValue
      switch verdict {
      case .ready:
        subtitle = "Revision \(revision) · sealed \(CaptureText.sealedDate(sealedAt, timeZone: timeZone))"
        status = RowStatusValue(.done, "Ready")
      case .limited:
        subtitle = "Revision \(revision) · sealed \(CaptureText.sealedDate(sealedAt, timeZone: timeZone))"
        status = RowStatusValue(.partly, "Limited")
      case .blocked:
        subtitle = "Revision \(revision) · re-seal needed"
        status = RowStatusValue(.missing, "Blocked")
      }
      return Row(
        id: id, title: title, subtitle: subtitle, status: status, destination: .verdict,
        sortDate: sealedAt)
    }
  }

  /// "In progress" rows, newest activity first.
  public private(set) var inProgress: [Row]
  /// "Sealed" rows, newest `sealedAt` first.
  public private(set) var sealed: [Row]
  /// The signed-in operator (avatar and account dialog).
  public var operatorName: String
  /// Sealed packages wait for the station: the account dialog says uploads resume.
  public var hasPendingUploads: Bool
  /// Reading the disk took longer than 300 ms: a spinner instead of the sections.
  public var isLoading: Bool

  /// Sorts `rows` into the two sections by destination.
  public init(
    rows: [Row], operatorName: String, hasPendingUploads: Bool = false, isLoading: Bool = false
  ) {
    let newestFirst = rows.sorted {
      $0.sortDate != $1.sortDate ? $0.sortDate > $1.sortDate : $0.id < $1.id
    }
    inProgress = newestFirst.filter { $0.destination == .overview }
    sealed = newestFirst.filter { $0.destination == .verdict }
    self.operatorName = operatorName
    self.hasPendingUploads = hasPendingUploads
    self.isLoading = isLoading
  }

  /// No capture on this phone: the empty card and its footnote.
  public var isEmpty: Bool { inProgress.isEmpty && sealed.isEmpty }

  /// The account dialog's title.
  public var accountTitle: String { "Signed in as \(operatorName)" }

  /// The account dialog's message, nil when nothing waits.
  public var accountMessage: String? { hasPendingUploads ? Self.pendingUploadsMessage : nil }
}

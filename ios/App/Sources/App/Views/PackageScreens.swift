import AppCore
import CaptureContract
import ChapterUI
import SwiftUI

// The package screens of design v2 (artboard 2f, build spec phone-package §3–§6): Package ready,
// Package status (Uploading, Paused, Uploaded, Upload stopped), Verdict received and Revision n.
//
// Every screen is a pushed screen of the app's NavigationStack (critique R-18c): the large title
// in Times New Roman, the right caption in the bar, the subtitle as the first content line and
// the buttons in the bottom action bar. The screens only draw state and call actions: the app
// (VisitModel / AppModel) owns the flow, the builders and the uploads. They depend on AppCore,
// CaptureContract and ChapterUI only, so the snapshot tests compile this file on its own
// (ios/App/PackageScreensTests).

// MARK: - Screen A · Package ready

/// What Package ready shows (§3.2).
struct PackageReadyState: Equatable {
  /// "618 Valley Street · 2 floors · revision 1" while the plans are written.
  var buildingSubtitle: String
  /// The draft's review once the plans are written.
  var review: PackageReview?
  /// The builder's error ("The plans of Floor 2 could not be written: …").
  var buildError: String?
  var isSealing = false
  /// "The package could not be sealed: … Nothing was uploaded." (`SealFailureText`).
  var sealError: String?

  var isBuilding: Bool { review == nil && buildError == nil }
}

struct PackageReadyActions {
  /// "Scan another floor or room" (`VisitFlow.addFloor()`).
  var scanAnother: () -> Void = {}
  /// "Seal and upload".
  var seal: () -> Void = {}
  /// "Try again" after the build failed (`VisitModel.rebuildPlan()`); no button when nil.
  var tryAgain: (() -> Void)?
}

/// Screen A (§3): the real file list of revision 1, then seal and upload.
struct PackageReadyView: View {
  let state: PackageReadyState
  let actions: PackageReadyActions
  /// The open "Original Exports" group (accordion); the first capture starts open.
  @State private var expansion: Expansion = .first

  enum Expansion: Equatable {
    case first
    case group(String)
    case none
  }

  init(state: PackageReadyState, actions: PackageReadyActions = PackageReadyActions()) {
    self.state = state
    self.actions = actions
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 10) {
        PackageSubtitle(state.review?.subtitle ?? state.buildingSubtitle)
          .padding(.top, ChapterTheme.Metric.subtitleTop)
        if let review = state.review {
          exports(review)
          ChapterCard {
            SummaryRow(title: "Site Photos", detail: review.photosText)
            SummaryRow(title: "Field Measurements", detail: review.controlsText)
            SummaryRow(title: "Capture record", detail: review.compassText)
            SummaryRow(title: "Source Register", detail: review.manifestText)
          }
          InfoNote(review.sealNote)
          if let error = state.sealError {
            ErrorLine(text: "\(error) Try again.")
          }
        } else if let error = state.buildError {
          buildFailed(error)
        } else {
          ProgressView {
            Text("Writing plans and 3D files\u{2026}")
              .chapterTextStyle(.subhead)
              .foregroundStyle(ChapterTheme.Color.muted)
          }
          .frame(maxWidth: .infinity)
          .padding(.top, 40)
        }
      }
      .padding(.horizontal, ChapterTheme.Metric.screenPadding)
      .padding(.bottom, ChapterTheme.Metric.sectionGap)
      .chapterContentWidth()
    }
    .navigationTitle("Package ready")
    .navigationBarTitleDisplayMode(.large)
    .chapterNavigationCaption("Step 3 of 3")
    .chapterBackChevronOnly()
    .navigationBarBackButtonHidden(state.isSealing)
    .chapterScreenBackground()
    .chapterActionBar {
      Button("Scan another floor or room", action: actions.scanAnother)
        .buttonStyle(.chapter(.tinted))
        .disabled(state.isSealing)
        .accessibilityIdentifier("package.scanAnother")
      Button(state.isSealing ? "Sealing\u{2026}" : "Seal and upload", action: actions.seal)
        .buttonStyle(.chapter(.primary))
        .disabled(state.review == nil || state.isSealing)
        .accessibilityIdentifier("package.seal")
    }
  }

  private func isExpanded(_ group: PackageReview.ExportGroup, in review: PackageReview) -> Bool {
    switch expansion {
    case .first: return group.areaKey == review.exportGroups.first?.areaKey
    case .group(let key): return group.areaKey == key
    case .none: return false
    }
  }

  /// Card 1: one disclosure group per capture, in capture order.
  private func exports(_ review: PackageReview) -> some View {
    ChapterCard {
      ForEach(review.exportGroups, id: \.areaKey) { group in
        let expanded = isExpanded(group, in: review)
        ExportGroupHeader(group: group, isExpanded: expanded) {
          withAnimation(.easeInOut(duration: 0.2)) {
            expansion = expanded ? .none : .group(group.areaKey)
          }
        }
        if expanded {
          ForEach(group.rows, id: \.kind) { row in
            ExportSubRow(row: row, areaKey: group.areaKey)
          }
        }
      }
    }
  }

  private func buildFailed(_ error: String) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      ChapterCard {
        HStack(alignment: .top, spacing: ChapterTheme.Metric.statusGlyphGap) {
          StatusGlyph(.missing).padding(.top, 5)
          Text(error)
            .chapterTextStyle(.subhead)
            .foregroundStyle(ChapterTheme.Color.blocked)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, ChapterTheme.Metric.rowPadding)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
      }
      SectionFooter("Nothing was sealed. Scan the floor again or try again.")
      if let tryAgain = actions.tryAgain {
        Button("Try again", action: tryAgain)
          .buttonStyle(.chapter(.tinted))
          .accessibilityIdentifier("package.tryAgain")
      }
    }
  }
}

/// "Original Exports · Floor 1 · 13 files · 312 MB", the whole row the button.
private struct ExportGroupHeader: View {
  let group: PackageReview.ExportGroup
  let isExpanded: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: ChapterTheme.Metric.rowGap) {
        TitleDetail {
          Text(group.title)
            .chapterTextStyle(.bodyEmphasis)
            .foregroundStyle(ChapterTheme.Color.ink)
            .multilineTextAlignment(.leading)
        } detail: {
          Text(group.countText)
            .chapterTextStyle(.subhead)
            .foregroundStyle(ChapterTheme.Color.muted)
            .monospacedDigit()
        }
        if !isExpanded { Chevron() }
      }
      .padding(.horizontal, ChapterTheme.Metric.rowPadding)
      .padding(.vertical, 4)
      .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(group.accessibilityLabel))
    .accessibilityValue(Text(isExpanded ? "expanded" : "collapsed"))
    .accessibilityHint(Text("Shows the file kinds"))
    .accessibilityIdentifier("package.floor.\(group.areaKey)")
  }
}

/// "Plan DXF · rooms CSV · plan sheet PDF, PNG, SVG  5".
private struct ExportSubRow: View {
  let row: PackageReview.ExportRow
  let areaKey: String

  var body: some View {
    HStack(spacing: ChapterTheme.Metric.rowGap) {
      Text(row.label)
        .chapterTextStyle(.subhead)
        .foregroundStyle(ChapterTheme.Color.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
      Text("\(row.count)")
        .chapterTextStyle(.footnote)
        .foregroundStyle(ChapterTheme.Color.muted)
        .monospacedDigit()
    }
    .padding(.leading, 32)
    .padding(.trailing, ChapterTheme.Metric.rowPadding)
    .padding(.vertical, 4)
    .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("package.floor.\(areaKey).\(row.kind.rawValue)")
  }
}

/// The subtitle under the large title, as the first content line (ChapterUI's `ScreenSubtitle`):
/// subhead 15/20 muted, up to 3 lines, and every line at accessibility text sizes (the Revision n
/// subtitle is three sentences).
private struct PackageSubtitle: View {
  let text: String
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  init(_ text: String) {
    self.text = text
  }

  var body: some View {
    Text(text)
      .chapterTextStyle(.subhead)
      .foregroundStyle(ChapterTheme.Color.muted)
      .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// A title and its detail side by side; at accessibility text sizes the detail goes under the
/// title (as ChapterUI's `ValueRow`), so nothing is clipped.
private struct TitleDetail<Title: View, Detail: View>: View {
  @ViewBuilder let title: Title
  @ViewBuilder let detail: Detail
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: ChapterTheme.Metric.rowTitleGap) {
        title
        detail
      }
      .multilineTextAlignment(.leading)
      .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      HStack(spacing: ChapterTheme.Metric.rowGap) {
        title.frame(maxWidth: .infinity, alignment: .leading)
        detail.multilineTextAlignment(.trailing)
      }
    }
  }
}

/// A row of Package ready's second card: title SemiBold 17, detail 15 muted, min 42.
private struct SummaryRow: View {
  let title: String
  let detail: String

  var body: some View {
    TitleDetail {
      Text(title)
        .chapterTextStyle(.bodyEmphasis)
        .foregroundStyle(ChapterTheme.Color.ink)
    } detail: {
      Text(detail)
        .chapterTextStyle(.subhead)
        .foregroundStyle(ChapterTheme.Color.muted)
    }
    .padding(.horizontal, ChapterTheme.Metric.rowPadding)
    .padding(.vertical, 4)
    .frame(maxWidth: .infinity, minHeight: 42)
    .accessibilityElement(children: .combine)
  }
}

/// ■ and an error in #8B2E2E, footnote 13/17.
private struct ErrorLine: View {
  let text: String

  var body: some View {
    HStack(alignment: .top, spacing: ChapterTheme.Metric.statusGlyphGap) {
      StatusGlyph(.missing).padding(.top, 3)
      Text(text)
        .chapterTextStyle(.footnote)
        .foregroundStyle(ChapterTheme.Color.blocked)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
    .accessibilityElement(children: .combine)
  }
}

// MARK: - Screen B · Package status, Screen C · Verdict received

/// What Package status and Verdict received know besides the upload snapshot.
struct PackageStatusOptions: Equatable {
  /// The footer button of Verdict received (§5.1).
  enum Revision: Equatable {
    /// "Add to this capture": the latest revision, its visit on this phone.
    case add
    /// "Continue revision {n}": a revision is in progress.
    case continueRevision(Int)
    /// Superseded, or the visit is not on this phone.
    case hidden
  }

  /// The operator allowed the verdict notification.
  var notificationsAllowed = true
  /// The visit's originals are on this phone, so Upload stopped can re-seal.
  var canReseal = true
  /// "Sealing…" on the re-seal button.
  var isResealing = false
  /// The re-seal failed (`SealFailureText`).
  var resealError: String?
  var revision: Revision = .add
  /// The newest revision on this phone, for a superseded one ("Revision 2 replaces this
  /// revision.").
  var latestRevision: Int?
  /// "Today" and the time zone of the times (the phone's).
  var now = Date()
  var timeZone = TimeZone.current
}

/// The screens' actions. A button whose action is nil is not shown.
struct PackageStatusActions {
  /// "Try again" (`UploadCoordinator.retry()`).
  var retry: (() -> Void)?
  /// "Re-seal" in the alert (full rebuild as revision n+1).
  var reseal: (() -> Void)?
  /// "Add to this capture" or "Continue revision n".
  var addToCapture: (() -> Void)?
  /// "Open in the HUB", with the station's link (opened in Safari).
  var openInHub: ((URL) -> Void)?
}

/// Screen B (§4) for one package; once the verdict is known, Screen C (§5) on the same route.
struct PackageStatusView: View {
  let packageId: LowercaseUUID
  let snapshot: UploadSnapshot?
  let options: PackageStatusOptions
  let actions: PackageStatusActions
  @State private var confirmReseal = false

  init(
    packageId: LowercaseUUID, snapshot: UploadSnapshot?,
    options: PackageStatusOptions = PackageStatusOptions(),
    actions: PackageStatusActions = PackageStatusActions()
  ) {
    self.packageId = packageId
    self.snapshot = snapshot
    self.options = options
    self.actions = actions
  }

  var body: some View {
    if let snapshot, snapshot.phase == .verdict {
      VerdictView(snapshot: snapshot, options: options, actions: actions)
    } else if let snapshot {
      status(snapshot)
    } else {
      ProgressView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .chapterScreenBackground()
    }
  }

  private func status(_ snapshot: UploadSnapshot) -> some View {
    let isStopped: Bool
    if case .stopped = snapshot.phase { isStopped = true } else { isStopped = false }
    return ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        PackageSubtitle(snapshot.subtitle)
          .padding(.top, ChapterTheme.Metric.subtitleTop)
        ProgressCard(snapshot: snapshot, options: options)
        ChapterSection(header: "Files") {
          ForEach(snapshot.progress.rows, id: \.category) { row in
            CategoryRow(row: row)
          }
        }
        ChapterSection(
          header: "Station", footer: snapshot.footnote(notificationsAllowed: options.notificationsAllowed)
        ) {
          ForEach(snapshot.timeline(now: options.now, timeZone: options.timeZone).rows, id: \.id) {
            StationRow(row: $0, minHeight: 44)
          }
        }
      }
      .padding(.horizontal, ChapterTheme.Metric.screenPadding)
      .padding(.bottom, ChapterTheme.Metric.sectionGap)
      .chapterContentWidth()
    }
    .navigationTitle(snapshot.title)
    .navigationBarTitleDisplayMode(.large)
    .chapterNavigationCaption(snapshot.navigationCaption)
    .chapterBackChevronOnly()
    .chapterScreenBackground()
    .safeAreaInset(edge: .bottom, spacing: 0) {
      if isStopped && (actions.retry != nil || canReseal) {
        ChapterActionBar {
          if let retry = actions.retry {
            Button("Try again", action: retry)
              .buttonStyle(.chapter(.tinted))
              .disabled(options.isResealing)
              .accessibilityIdentifier("upload.retry")
          }
          if canReseal {
            Button(options.isResealing ? "Sealing\u{2026}" : snapshot.resealTitle) {
              confirmReseal = true
            }
            .buttonStyle(.chapter(.primary))
            .disabled(options.isResealing)
            .accessibilityIdentifier("upload.reseal")
          }
        }
      }
    }
    .alert(snapshot.resealAlertTitle, isPresented: $confirmReseal) {
      Button("Cancel", role: .cancel) {}
      Button("Re-seal") { actions.reseal?() }
    } message: {
      Text(snapshot.resealAlertMessage)
    }
  }

  /// Re-seal needs the visit's originals on the phone and an action that does it.
  private var canReseal: Bool { options.canReseal && actions.reseal != nil }
}

/// The progress card: bytes and percent, the 8 pt bar and the state's caption.
private struct ProgressCard: View {
  let snapshot: UploadSnapshot
  let options: PackageStatusOptions

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(snapshot.progress.bytesText)
          .chapterTextStyle(.bodyEmphasis)
        Spacer(minLength: ChapterTheme.Metric.rowGap)
        Text(snapshot.progress.percentText)
          .chapterTextStyle(.body)
      }
      .monospacedDigit()
      .foregroundStyle(ChapterTheme.Color.ink)
      .accessibilityElement(children: .combine)
      ProgressBar(
        fraction: snapshot.progress.fraction, height: ChapterTheme.Metric.progressBarHeightLarge)
      if case .stopped(let message) = snapshot.phase {
        ErrorLine(text: message)
        caption(snapshot.stoppedNote(canReseal: options.canReseal))
        if let error = options.resealError {
          ErrorLine(text: error)
        }
      } else {
        caption(snapshot.caption)
      }
    }
    .padding(.vertical, 14)
    .padding(.horizontal, ChapterTheme.Metric.rowPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(ChapterTheme.Color.surface)
    .clipShape(RoundedRectangle(cornerRadius: ChapterTheme.Metric.cardRadius))
    .overlay(
      RoundedRectangle(cornerRadius: ChapterTheme.Metric.cardRadius)
        .strokeBorder(ChapterTheme.Color.line, lineWidth: ChapterTheme.Metric.cardBorder))
    .accessibilityIdentifier("upload.progress")
  }

  private func caption(_ text: String) -> some View {
    Text(text)
      .chapterTextStyle(.footnote)
      .foregroundStyle(ChapterTheme.Color.muted)
      .frame(maxWidth: .infinity, alignment: .leading)
      .fixedSize(horizontal: false, vertical: true)
  }
}

/// "Meshes · Uploading · 41%": the category and its status, word and shape.
private struct CategoryRow: View {
  let row: UploadProgressSummary.Row

  var body: some View {
    TitleDetail {
      Text(row.category.rawValue)
        .chapterTextStyle(.body)
        .foregroundStyle(ChapterTheme.Color.ink)
    } detail: {
      status
    }
    .padding(.horizontal, ChapterTheme.Metric.rowPadding)
    .padding(.vertical, 4)
    .frame(maxWidth: .infinity, minHeight: 48)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(row.accessibilityLabel))
    .accessibilityIdentifier("upload.category.\(row.category.identifier)")
  }

  @ViewBuilder
  private var status: some View {
    switch row.status {
    case .confirmed: StatusLabel(kind: .done, word: row.status.text)
    case .waiting: StatusLabel(kind: .waiting, word: row.status.text)
    case .stopped: StatusLabel(kind: .missing, word: row.status.text)
    case .uploading:
      Text(row.status.text)
        .chapterTextStyle(.subhead)
        .foregroundStyle(ChapterTheme.Color.ink)
        .monospacedDigit()
    }
  }
}

/// One row of the Station card: shape, title, detail.
private struct StationRow: View {
  let row: StationTimeline.Row
  let minHeight: CGFloat
  /// The glyph grows with the title at larger text sizes (10 pt at the default size).
  @ScaledMetric(relativeTo: .body) private var glyphSize = ChapterTheme.Metric.statusGlyph

  var body: some View {
    HStack(spacing: ChapterTheme.Metric.rowGap) {
      StatusGlyph(kind, size: glyphSize)
      TitleDetail {
        Text(row.title)
          .chapterTextStyle(.body)
          .foregroundStyle(titleColor)
      } detail: {
        Text(row.detail)
          .chapterTextStyle(.subhead)
          .foregroundStyle(row.state == .problem ? kind.textColor : ChapterTheme.Color.muted)
          .monospacedDigit()
      }
    }
    .padding(.horizontal, ChapterTheme.Metric.rowPadding)
    .padding(.vertical, 4)
    .frame(maxWidth: .infinity, minHeight: minHeight)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(row.accessibilityLabel))
    .accessibilityIdentifier("station.\(row.id.rawValue)")
  }

  private var kind: StatusKind {
    switch row.shape {
    case .filled: return .done
    case .triangle: return .partly
    case .square: return .missing
    case .ring: return .waiting
    }
  }

  private var titleColor: Color {
    switch row.state {
    case .done, .problem: return ChapterTheme.Color.ink
    case .pending, .inProgress: return ChapterTheme.Color.muted
    }
  }
}

/// Screen C (§5): the verdict as word and shape, one sentence, the next visit, the station's
/// timeline; details are in the HUB.
struct VerdictView: View {
  let snapshot: UploadSnapshot
  let options: PackageStatusOptions
  let actions: PackageStatusActions

  init(
    snapshot: UploadSnapshot, options: PackageStatusOptions = PackageStatusOptions(),
    actions: PackageStatusActions = PackageStatusActions()
  ) {
    self.snapshot = snapshot
    self.options = options
    self.actions = actions
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 10) {
        if let subtitle = snapshot.verdictSubtitle(timeZone: options.timeZone) {
          PackageSubtitle(subtitle)
            .padding(.top, ChapterTheme.Metric.subtitleTop)
        }
        if let verdict = snapshot.verdict {
          VerdictCard(verdict: verdict, published: snapshot.isPublished)
          if !verdict.shownNextVisit.isEmpty {
            ChapterSection(header: "For the next visit", footer: verdict.moreNextVisitText) {
              ForEach(Array(verdict.shownNextVisit.enumerated()), id: \.offset) { index, next in
                NextVisitRow(next: next, index: index)
              }
            }
          }
        }
        ChapterSection(header: "Station", footer: supersededText) {
          ForEach(snapshot.timeline(now: options.now, timeZone: options.timeZone).rows, id: \.id) {
            StationRow(row: $0, minHeight: 40)
          }
        }
      }
      .padding(.horizontal, ChapterTheme.Metric.screenPadding)
      .padding(.bottom, ChapterTheme.Metric.sectionGap)
      .chapterContentWidth()
    }
    .navigationTitle(snapshot.title)
    .navigationBarTitleDisplayMode(.large)
    .chapterNavigationCaption(snapshot.navigationCaption)
    .chapterBackChevronOnly()
    .chapterScreenBackground()
    .safeAreaInset(edge: .bottom, spacing: 0) {
      if revisionTitle != nil || hubLink != nil {
        ChapterActionBar {
          if let title = revisionTitle, let addToCapture = actions.addToCapture {
            Button(title, action: addToCapture)
              .buttonStyle(.chapter(.tinted))
              .accessibilityIdentifier("verdict.addToCapture")
          }
          if let link = hubLink, let openInHub = actions.openInHub {
            Button("Open in the HUB") { openInHub(link) }
              .buttonStyle(.chapter(.primary))
              .accessibilityIdentifier("verdict.openHub")
          }
        }
      }
    }
  }

  /// "Add to this capture" / "Continue revision n", or nil (superseded, not on this phone, or
  /// no action).
  private var revisionTitle: String? {
    guard !snapshot.isSuperseded, actions.addToCapture != nil else { return nil }
    switch options.revision {
    case .add: return "Add to this capture"
    case .continueRevision(let revision): return "Continue revision \(revision)"
    case .hidden: return nil
    }
  }

  /// The station's HUB page, else its review page (Q2); nil without a link or an action.
  private var hubLink: URL? {
    actions.openInHub == nil ? nil : snapshot.station?.links?.openInHub
  }

  private var supersededText: String? {
    guard snapshot.isSuperseded, let latest = options.latestRevision else { return nil }
    return "Revision \(latest) replaces this revision."
  }
}

/// The verdict card: 14 pt glyph and word in the outcome colour, the sentence, a 2 pt border.
private struct VerdictCard: View {
  let verdict: VerdictStatus
  let published: Bool
  /// The glyph grows with the word at larger text sizes (14 pt at the default size).
  @ScaledMetric(relativeTo: .title3) private var glyphSize = ChapterTheme.Metric.verdictGlyph

  var body: some View {
    let sentence = verdict.sentence(published: published)
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 8) {
        StatusGlyph(kind, size: glyphSize)
        Text(verdict.word)
          .chapterTextStyle(.verdictWord)
          .foregroundStyle(kind.textColor)
      }
      Text(sentence)
        .chapterTextStyle(.subhead)
        .foregroundStyle(ChapterTheme.Color.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.vertical, 12)
    .padding(.horizontal, ChapterTheme.Metric.rowPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      ChapterTheme.Color.surface,
      in: RoundedRectangle(cornerRadius: ChapterTheme.Metric.cardRadius)
    )
    .overlay(
      RoundedRectangle(cornerRadius: ChapterTheme.Metric.cardRadius)
        .strokeBorder(kind.glyphColor, lineWidth: 2))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text("Verdict: \(verdict.word). \(sentence)"))
    .accessibilityIdentifier("verdict.card")
  }

  private var kind: StatusKind {
    switch verdict.outcome {
    case .ready: return .done
    case .limited: return .partly
    case .blocked: return .missing
    }
  }
}

/// A next action verbatim over its reason.
private struct NextVisitRow: View {
  let next: VerdictStatus.NextVisit
  let index: Int

  var body: some View {
    VStack(alignment: .leading, spacing: ChapterTheme.Metric.rowTitleGap) {
      Text(next.action)
        .chapterTextStyle(.body)
        .foregroundStyle(ChapterTheme.Color.ink)
        .lineLimit(3)
      if let reason = next.reason {
        Text(reason)
          .chapterTextStyle(.footnote)
          .foregroundStyle(ChapterTheme.Color.muted)
          .lineLimit(2)
      }
    }
    .padding(.horizontal, ChapterTheme.Metric.rowPadding)
    .padding(.vertical, 5)
    .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("verdict.next.\(index)")
  }
}

// MARK: - Screen D · Revision n

/// What Revision n knows besides the changes.
struct RevisionReviewState: Equatable {
  var changes: RevisionChanges
  /// The project title (critique R-29), the bar's right caption.
  var projectTitle: String
  var isSealing = false
  /// "The package could not be sealed: … Nothing was uploaded." (`SealFailureText`).
  var sealError: String?
}

struct RevisionReviewActions {
  /// "Keep editing": back to the Capture overview, revision mode.
  var keepEditing: () -> Void = {}
  /// "Seal revision n and upload".
  var seal: () -> Void = {}
}

/// Screen D (§6): what revision n changes and what stays, then seal it.
struct RevisionReviewView: View {
  let state: RevisionReviewState
  let actions: RevisionReviewActions

  init(state: RevisionReviewState, actions: RevisionReviewActions = RevisionReviewActions()) {
    self.state = state
    self.actions = actions
  }

  private var changes: RevisionChanges { state.changes }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        PackageSubtitle(changes.subtitle)
          .padding(.top, ChapterTheme.Metric.subtitleTop)
        ChapterSection(header: "What changed") {
          if changes.rows.isEmpty {
            Text(changes.nothingChangedText)
              .chapterTextStyle(.body)
              .foregroundStyle(ChapterTheme.Color.muted)
              .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
              .padding(.horizontal, ChapterTheme.Metric.rowPadding)
          }
          ForEach(Array(changes.rows.enumerated()), id: \.offset) { _, row in
            ChangeRow(row: row)
          }
          TitleDetail {
            Text("Manifest")
              .chapterTextStyle(.body)
              .foregroundStyle(ChapterTheme.Color.ink)
          } detail: {
            Text(changes.manifestDetail)
              .chapterTextStyle(.subhead)
              .foregroundStyle(ChapterTheme.Color.muted)
              .monospacedDigit()
          }
          .padding(.horizontal, ChapterTheme.Metric.rowPadding)
          .padding(.vertical, 4)
          .frame(maxWidth: .infinity, minHeight: 48)
          .accessibilityElement(children: .combine)
          .accessibilityIdentifier("revision.manifest")
        }
        if let title = changes.unchangedTitle {
          ChapterSection(
            header: "Unchanged", footer: changes.hasNoChanges ? nil : changes.footnote
          ) {
            VStack(alignment: .leading, spacing: ChapterTheme.Metric.rowTitleGap) {
              Text(title)
                .chapterTextStyle(.body)
                .foregroundStyle(ChapterTheme.Color.ink)
              Text(changes.unchangedSubtitle)
                .chapterTextStyle(.footnote)
                .foregroundStyle(ChapterTheme.Color.muted)
            }
            .padding(.horizontal, ChapterTheme.Metric.rowPadding)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("revision.unchanged")
          }
        } else if !changes.hasNoChanges {
          SectionFooter(changes.footnote)
        }
        if let error = state.sealError {
          ErrorLine(text: error)
        }
      }
      .padding(.horizontal, ChapterTheme.Metric.screenPadding)
      .padding(.bottom, ChapterTheme.Metric.sectionGap)
      .chapterContentWidth()
    }
    .navigationTitle(changes.title)
    .navigationBarTitleDisplayMode(.large)
    .chapterNavigationCaption(state.projectTitle)
    .chapterBackChevronOnly()
    .navigationBarBackButtonHidden(state.isSealing)
    .chapterScreenBackground()
    .chapterActionBar {
      Button("Keep editing", action: actions.keepEditing)
        .buttonStyle(.chapter(.tinted))
        .disabled(state.isSealing)
        .accessibilityIdentifier("revision.keepEditing")
      Button(state.isSealing ? "Sealing\u{2026}" : changes.sealButtonTitle, action: actions.seal)
        .buttonStyle(.chapter(.primary))
        .disabled(changes.hasNoChanges || state.isSealing)
        .accessibilityIdentifier("revision.seal")
    }
  }
}

/// One "What changed" row: the 22 pt plus, equals or minus glyph and two lines.
private struct ChangeRow: View {
  let row: RevisionChanges.Row

  var body: some View {
    HStack(spacing: ChapterTheme.Metric.rowGap) {
      glyph
      VStack(alignment: .leading, spacing: ChapterTheme.Metric.rowTitleGap) {
        Text(row.title)
          .chapterTextStyle(.body)
          .foregroundStyle(ChapterTheme.Color.ink)
        Text(row.detail)
          .chapterTextStyle(.footnote)
          .foregroundStyle(ChapterTheme.Color.muted)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, ChapterTheme.Metric.rowPadding)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(row.accessibilityLabel))
  }

  @ViewBuilder
  private var glyph: some View {
    switch row.kind {
    case .added: PlusGlyph(accessibilityLabel: nil)
    case .changed: EqualsGlyph(accessibilityLabel: nil)
    case .removed: MinusGlyph(accessibilityLabel: nil)
    }
  }
}

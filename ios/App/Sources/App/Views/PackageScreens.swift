import AppCore
import CaptureUI
import SwiftUI

private typealias Palette = ChapterTokens.Palette
private typealias Space = ChapterTokens.Space
private typealias Typo = ChapterTokens.Typography
private typealias Control = ChapterTokens.Control
private typealias Radius = ChapterTokens.Radius

/// screen-package, 1: "Package ready" — folder layout, sizes, seal.
struct PackageReadyView: View {
  let visit: VisitModel

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Package ready").font(Typo.serif(30)).foregroundStyle(Palette.ink)
        .accessibilityAddTraits(.isHeader)
      if let review = visit.plan?.review {
        Text(review.subtitle).font(Typo.sans(15)).foregroundStyle(Palette.muted)
        ScrollView { folders(review) }
        HStack(alignment: .top, spacing: 10) {
          Image(systemName: "lock").font(.system(size: 14)).foregroundStyle(Palette.ink)
          Text(review.sealNote).font(Typo.caption).foregroundStyle(Palette.ink)
        }
        .padding(.horizontal, Space.s4).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.nude, in: RoundedRectangle(cornerRadius: Radius.card))
      } else if visit.isBuilding {
        ProgressView("Writing plans and 3D files…").frame(maxWidth: .infinity)
      }
      Spacer(minLength: 0)
      Button { visit.addMoreRooms() } label: {
        Text("Add more rooms").font(Typo.body).foregroundStyle(Palette.ink)
          .frame(maxWidth: .infinity, minHeight: Control.primaryHeight)
          .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.ink, lineWidth: 1))
      }
      .buttonStyle(.plain)
      .disabled(visit.isSealing)
      Button { visit.sealAndUpload() } label: {
        Text(visit.isSealing ? "Sealing…" : "Seal and upload")
          .font(Typo.headline).foregroundStyle(Palette.surface)
          .frame(maxWidth: .infinity, minHeight: Control.primaryHeight)
          .background(
            visit.plan == nil ? Palette.line : Palette.ink,
            in: RoundedRectangle(cornerRadius: Radius.card))
      }
      .buttonStyle(.plain)
      .disabled(visit.plan == nil || visit.isSealing)
    }
    .padding(.horizontal, 20)
    .padding(.top, Space.s2)
    .padding(.bottom, 28)
  }

  private func folders(_ review: PackageReview) -> some View {
    VStack(spacing: 0) {
      ForEach(Array(review.captures.enumerated()), id: \.offset) { index, group in
        VStack(alignment: .leading, spacing: 6) {
          Text("Original Exports \u{00B7} \(group.label)").font(Typo.sans(15, weight: .semibold))
          if index == 0 {
            Text(group.kinds).font(Typo.caption).foregroundStyle(Palette.muted)
          }
          Text(group.countText).font(Typo.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s4).padding(.vertical, 14)
        divider
      }
      row("Site Photos", review.photosText)
      divider
      row("Field Measurements", review.controlsText)
      divider
      row("Source Register", review.manifestText)
    }
    .foregroundStyle(Palette.ink)
    .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card))
    .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.line, lineWidth: 1))
  }

  private var divider: some View { Rectangle().fill(Palette.nude).frame(height: 1) }

  private func row(_ title: String, _ value: String) -> some View {
    HStack {
      Text(title).font(Typo.sans(15, weight: .semibold))
      Spacer()
      Text(value).font(Typo.sans(15))
    }
    .padding(.horizontal, Space.s4).padding(.vertical, 14)
    .accessibilityElement(children: .combine)
  }
}

/// screen-package, 2: "Uploading" with the station status.
struct UploadingView: View {
  let snapshot: UploadSnapshot
  let onNewCapture: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("Uploading").font(Typo.serif(30)).foregroundStyle(Palette.ink)
          .accessibilityAddTraits(.isHeader)
        Spacer()
        Button("New capture", action: onNewCapture)
          .font(Typo.sans(15)).foregroundStyle(Palette.ink)
          .frame(minHeight: Control.minTouch)
      }
      progressCard
      categories
      Text("STATION").font(Typo.caption).tracking(2).foregroundStyle(Palette.muted)
      VStack(alignment: .leading, spacing: 10) {
        ForEach(snapshot.station.steps, id: \.title) { step in
          HStack(spacing: 12) {
            Text(step.done ? "\u{25CF}" : "\u{25CB}")
              .foregroundStyle(step.done ? Palette.ready : Palette.muted)
            Text(step.title).foregroundStyle(step.done ? Palette.ink : Palette.muted)
          }
          .font(Typo.sans(15))
          .accessibilityElement(children: .ignore)
          .accessibilityLabel("\(step.title), \(step.done ? "done" : "not yet")")
          .accessibilityIdentifier("station.\(step.title)")
        }
      }
      Spacer(minLength: 0)
      if let verdict = snapshot.verdict { verdictCard(verdict) }
      Text("Files stay on this phone until the station confirms each one.")
        .font(Typo.caption).foregroundStyle(Palette.muted)
        .frame(maxWidth: .infinity, alignment: .center)
        .multilineTextAlignment(.center)
    }
    .padding(.horizontal, 20)
    .padding(.top, Space.s2)
    .padding(.bottom, 28)
  }

  private var progressCard: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(snapshot.progress.bytesText).font(Typo.sans(15, weight: .semibold))
        Spacer()
        Text(snapshot.progress.percentText).font(Typo.sans(15))
      }
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          RoundedRectangle(cornerRadius: 5).fill(Palette.nude)
          RoundedRectangle(cornerRadius: 5).fill(Palette.ink)
            .frame(width: proxy.size.width * snapshot.progress.fraction)
        }
      }
      .frame(height: 10)
      .accessibilityHidden(true)
      Text(snapshot.caption).font(Typo.caption)
        .foregroundStyle(isFailure ? Palette.blocked : Palette.muted)
    }
    .foregroundStyle(Palette.ink)
    .padding(Space.s4)
    .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card))
    .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.line, lineWidth: 1))
  }

  private var isFailure: Bool {
    if case .failed = snapshot.activity { return true }
    return false
  }

  private var categories: some View {
    VStack(spacing: 0) {
      ForEach(Array(snapshot.progress.rows.enumerated()), id: \.offset) { index, row in
        HStack {
          Text(row.category.rawValue)
          Spacer()
          Text(row.status.text).foregroundStyle(color(row.status))
        }
        .font(Typo.sans(15))
        .padding(.horizontal, Space.s4).padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        if index < snapshot.progress.rows.count - 1 {
          Rectangle().fill(Palette.nude).frame(height: 1)
        }
      }
    }
    .foregroundStyle(Palette.ink)
    .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card))
    .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.line, lineWidth: 1))
  }

  private func color(_ status: UploadProgressSummary.Status) -> Color {
    switch status {
    case .verified: return Palette.ready
    case .uploading: return Palette.ink
    case .waiting: return Palette.muted
    }
  }

  private func verdictColors(_ verdict: VerdictDisplay) -> (tint: Color, text: Color) {
    switch verdict.outcome {
    case .ready: return (Palette.ready, Palette.ready)
    case .limited: return (Palette.limited, Palette.limitedText)
    case .blocked: return (Palette.blocked, Palette.blocked)
    }
  }

  private func verdictCard(_ verdict: VerdictDisplay) -> some View {
    let colors = verdictColors(verdict)
    let tint = colors.tint
    let text = colors.text
    return VStack(alignment: .leading, spacing: 6) {
      Text(verdict.title).font(Typo.sans(15, weight: .semibold)).foregroundStyle(text)
      Text(verdict.nextAction.map { "\(verdict.summary) \($0)" } ?? verdict.summary)
        .font(Typo.caption).foregroundStyle(Palette.ink)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(Space.s4)
    .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card))
    .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(tint, lineWidth: 2))
  }
}

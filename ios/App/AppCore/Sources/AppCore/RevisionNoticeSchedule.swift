import CaptureContract
import Foundation

/// Keeps the station's next-revision notice current while a visit is in revision mode
/// (phone-package §10.4, addendum C8): the web's "Revision 2 · not sealed · on the phone" reads
/// it, so it follows every change, not only the review of revision n.
///
/// Building revision n is heavy (it maps the scans again and writes the plans of new floors), so
/// the build is what waits: each change replaces the waiting build, which runs once nothing
/// changed for `delay` (10 s); its notice goes to that visit's `NextRevisionNotifier` (one per
/// base package, so two visits never overwrite each other's notice) and is sent at once.
/// `flush()` (the app came back to the foreground) runs a waiting build now and sends every
/// visit's last notice again. The schedule lives as long as the signed-in app, not the visit,
/// so a change made just before the visit closes is still sent. Best effort, as the notice is:
/// a build or send that fails is dropped without a word, and the next change or foreground
/// tries again.
///
/// Main-actor isolated, so changes arrive in the order the operator made them.
@MainActor
public final class RevisionNoticeSchedule {
  /// Makes the notice from the visit as it was at the change (off the main actor).
  public typealias Build = @Sendable () async throws -> NextRevisionNoticeDraft

  private struct Waiting {
    var base: LowercaseUUID
    var build: Build
  }

  private let sender: any NextRevisionNoticeSending
  /// One per base package: each keeps that visit's last notice.
  private var notifiers: [LowercaseUUID: NextRevisionNotifier] = [:]
  private let delay: TimeInterval
  private let sleep: @Sendable (TimeInterval) async throws -> Void
  private var waiting: Waiting?
  private var pending: Task<Void, Never>?
  /// Builds that run now (another visit's waiting build, `flush`), for `waitUntilIdle`.
  private var running: [Task<Void, Never>] = []
  /// Per base package, bumped by every change, review and seal: a build that finishes after one
  /// of them is out of date and its notice is dropped.
  private var generations: [LowercaseUUID: Int] = [:]
  /// Builds run so far (tests).
  public private(set) var buildCount = 0

  public init(
    sender: any NextRevisionNoticeSending, delay: TimeInterval = 10,
    sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
      try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }
  ) {
    self.sender = sender
    self.delay = delay
    self.sleep = sleep
  }

  /// Revision n on `basePackageId` changed (a floor, a photo, a control, a room name, or the
  /// revision just started). `build` runs once nothing changed for `delay`. A build still
  /// waiting for another visit runs now rather than being replaced.
  public func changed(basePackageId: LowercaseUUID, build: @escaping Build) {
    if let other = waiting, other.base != basePackageId {
      startNow(other)
    }
    bump(basePackageId)
    waiting = Waiting(base: basePackageId, build: build)
    pending?.cancel()
    let delay = self.delay
    let sleep = self.sleep
    pending = Task {
      do { try await sleep(delay) } catch { return }
      guard !Task.isCancelled else { return }
      await self.runWaiting()
    }
  }

  /// The app came back to the foreground: a waiting build runs now, and every other visit's
  /// last notice is sent again (the station may have missed it).
  public func flush() async {
    pending?.cancel()
    pending = nil
    let built = waiting?.base
    if let waiting {
      self.waiting = nil
      await run(waiting)
    }
    for (base, notifier) in notifiers where base != built {
      await notifier.flush()
    }
  }

  /// Revision n on `basePackageId` was built for its review: its notice goes now, and a waiting
  /// build of the same visit is no longer needed.
  public func built(_ notice: NextRevisionNoticeDraft, basePackageId: LowercaseUUID) async {
    dropWaiting(of: basePackageId)
    bump(basePackageId)
    await send(notice, basePackageId)
  }

  /// Revision n on `basePackageId` was sealed (the station drops the notice itself): nothing
  /// more is built or sent for it.
  public func stop(basePackageId: LowercaseUUID) async {
    dropWaiting(of: basePackageId)
    bump(basePackageId)
    await notifiers.removeValue(forKey: basePackageId)?.stop()
  }

  /// Waits for the scheduled and running builds and their sends (tests).
  public func waitUntilIdle() async {
    while true {
      let tasks = running + (pending.map { [$0] } ?? [])
      guard !tasks.isEmpty else { return }
      for task in tasks { await task.value }
      running.removeAll { task in tasks.contains(task) }
      if let pending, tasks.contains(pending) { self.pending = nil }
    }
  }

  // MARK: Private

  private func bump(_ base: LowercaseUUID) {
    generations[base, default: 0] += 1
  }

  private func dropWaiting(of base: LowercaseUUID) {
    guard waiting?.base == base else { return }
    waiting = nil
    pending?.cancel()
    pending = nil
  }

  private func startNow(_ item: Waiting) {
    running.append(Task { await self.run(item) })
  }

  private func runWaiting() async {
    guard let waiting else { return }
    self.waiting = nil
    await run(waiting)
  }

  private func run(_ item: Waiting) async {
    let generation = generations[item.base] ?? 0
    buildCount += 1
    guard let notice = try? await item.build(), generations[item.base] == generation else {
      return
    }
    await send(notice, item.base)
  }

  private func send(_ notice: NextRevisionNoticeDraft, _ base: LowercaseUUID) async {
    let notifier = notifiers[base] ?? NextRevisionNotifier(sender: sender)
    notifiers[base] = notifier
    await notifier.changed(notice, basePackageId: base)
    await notifier.flush()
  }
}

// The HUB project list of "New capture" with its date and whether it is the copy saved on this
// phone (phone-capture §3.2.1, critique G-11). Kept apart from StationQueries.swift, which the
// package track owns.
import CaptureContract
import CaptureCore
import Foundation
import StationClient

extension StationProjectProvider {
  /// The station's list, or the copy saved on this phone when offline (`ProjectList.isStale`),
  /// with the time the station returned it. Offline with nothing saved throws
  /// `HubProjectListingError.offlineWithoutSavedList`; every other error is thrown unchanged.
  public func listing() async throws -> HubProjectListing {
    do {
      return Self.listing(of: try await store.projects())
    } catch StationError.offline {
      throw HubProjectListingError.offlineWithoutSavedList
    }
  }

  public static func listing(of list: ProjectList) -> HubProjectListing {
    HubProjectListing(
      projects: summaries(of: list), fetchedAt: list.fetchedAt.date, isOfflineCopy: list.isStale)
  }
}

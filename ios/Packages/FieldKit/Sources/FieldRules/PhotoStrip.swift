import Foundation

/// The strip under the labels on "Label a photo" (phone-field §3.5): the last photos of the
/// selected room as thumbnails, and a line that counts them with the photo being labeled.
public struct PhotoStrip: Hashable, Sendable {
  /// At most this many thumbnails.
  public static let maximumThumbnails = 4
  static let privacyNote = "keep people and personal items out of the frame"

  /// The saved photos of the room shown as thumbnails: the last 4, oldest left, newest right.
  public let thumbnails: [PhotoRecord]
  /// Photos of the room including the one being labeled; 0 when no room is selected.
  public let count: Int
  /// `5 photos in Kitchen · keep people and personal items out of the frame`, or the privacy
  /// note alone when no room is selected.
  public let text: String

  /// - Parameters:
  ///   - photos: the saved photos of this capture, in save order.
  ///   - room: the selected room; matched by `PhotoCoverage.key` (trimmed, ignoring case).
  ///   - includesPending: a photo is being labeled (always on the labeling screen) and counts.
  public init(photos: [PhotoRecord], room: String?, includesPending: Bool = true) {
    let trimmed = room?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !trimmed.isEmpty else {
      thumbnails = []
      count = 0
      text = "Keep people and personal items out of the frame."
      return
    }
    let key = PhotoCoverage.key(trimmed)
    let roomPhotos = photos.filter { PhotoCoverage.key($0.room) == key }
    thumbnails = Array(roomPhotos.suffix(Self.maximumThumbnails))
    count = roomPhotos.count + (includesPending ? 1 : 0)
    text =
      "\(count) \(count == 1 ? "photo" : "photos") in \(trimmed) \u{00B7} \(Self.privacyNote)"
  }
}

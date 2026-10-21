#if canImport(SwiftUI) && canImport(UIKit)
  import FieldRules
  import Foundation
  import ImageIO
  import PhotoStore
  import UIKit

  /// Small thumbnails of saved photos for the strip on "Label a photo" (phone-field §3.5):
  /// decoded off the main actor from the original bytes with `CGImageSourceCreateThumbnailAtIndex`
  /// (120 px, EXIF orientation applied) and kept in memory only, keyed by the photo's path.
  /// Nothing is ever written to the visit or package folders.
  @MainActor
  final class ThumbnailCache {
    static let shared = ThumbnailCache()
    /// Longest side of a thumbnail in pixels (40 pt at 3x).
    nonisolated static let maxPixelSize = 120

    private let cache = NSCache<NSString, UIImage>()

    init() {
      cache.countLimit = 64
    }

    /// The cached thumbnail, if it was decoded before.
    func cached(_ record: PhotoRecord) -> UIImage? {
      cache.object(forKey: record.path as NSString)
    }

    /// The thumbnail of `record`, decoded once; nil when the file cannot be read or decoded (the
    /// strip then keeps its placeholder).
    func thumbnail(for record: PhotoRecord, store: PhotoRecordStore) async -> UIImage? {
      if let image = cached(record) { return image }
      let image = await Task.detached(priority: .userInitiated) {
        guard let data = try? store.originalData(for: record) else { return nil as UIImage? }
        return Self.decode(data)
      }.value
      if let image { cache.setObject(image, forKey: record.path as NSString) }
      return image
    }

    nonisolated static func decode(_ data: Data) -> UIImage? {
      guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
      let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
      ]
      guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
      else { return nil }
      return UIImage(cgImage: image)
    }
  }
#endif

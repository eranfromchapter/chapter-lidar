#if canImport(UIKit) && os(iOS)
  import CaptureContract
  @testable import FieldKitUI
  import FieldRules
  import ImageIO
  import PhotoStore
  import UIKit
  import XCTest

  /// The strip's thumbnails (phone-field §3.5): 120 px on the longest side, decoded from the
  /// original bytes with the EXIF orientation applied, cached in memory by path; nil (the
  /// placeholder stays) when the bytes are not an image.
  @MainActor
  final class ThumbnailCacheTests: XCTestCase {
    private typealias F = SnapshotFixtures
    private let wood = UIColor(red: 0.55, green: 0.42, blue: 0.30, alpha: 1)

    func testAThumbnailIs120PixelsOnTheLongestSide() throws {
      let upright = try XCTUnwrap(
        ThumbnailCache.decode(F.photoJPEG(width: 400, height: 300, color: wood, orientation: .up)))
      XCTAssertEqual(upright.cgImage?.width, 120)
      XCTAssertEqual(upright.cgImage?.height, 90)

      let small = try XCTUnwrap(
        ThumbnailCache.decode(F.photoJPEG(width: 60, height: 40, color: wood, orientation: .up)))
      XCTAssertEqual(small.cgImage?.width, 60, "a small photo is not enlarged")
    }

    /// The camera stores a portrait photo landscape, tagged `.right`: the thumbnail is portrait
    /// and the stored top edge (the light band) is on its right.
    func testTheExifOrientationIsApplied() throws {
      let image = try XCTUnwrap(
        ThumbnailCache.decode(
          F.photoJPEG(width: 400, height: 300, color: wood, orientation: .right)))
      let cgImage = try XCTUnwrap(image.cgImage)
      XCTAssertEqual(cgImage.width, 90)
      XCTAssertEqual(cgImage.height, 120)
      XCTAssertEqual(image.imageOrientation, .up, "the pixels are turned, not tagged")
      let right = try XCTUnwrap(Self.brightness(of: cgImage, x: 87, y: 60))
      let left = try XCTUnwrap(Self.brightness(of: cgImage, x: 4, y: 60))
      let top = try XCTUnwrap(Self.brightness(of: cgImage, x: 45, y: 2))
      XCTAssertGreaterThan(right, left + 0.2, "the band is on the right")
      XCTAssertEqual(top, left, accuracy: 0.05, "and not at the top")
    }

    func testBytesThatAreNotAnImageGiveNoThumbnail() {
      XCTAssertNil(ThumbnailCache.decode(F.jpeg(1)), "JPEG-shaped, not decodable")
      XCTAssertNil(ThumbnailCache.decode(Data()))
      XCTAssertNil(ThumbnailCache.decode(Data("not a photo".utf8)))
    }

    func testAThumbnailIsDecodedOnceFromTheStoredOriginal() async throws {
      let cache = ThumbnailCache()
      let store = try F.photoStore(decodable: true)
      let record = try XCTUnwrap(store.records.last)
      XCTAssertNil(cache.cached(record))
      let first = await cache.thumbnail(for: record, store: store)
      let image = try XCTUnwrap(first)
      XCTAssertEqual(image.cgImage?.width, 90)
      XCTAssertEqual(image.cgImage?.height, 120)
      XCTAssertTrue(cache.cached(record) === image)
      let second = await cache.thumbnail(for: record, store: store)
      XCTAssertTrue(second === image, "served from memory")
    }

    func testAnUndecodableOriginalIsNotCached() async throws {
      let cache = ThumbnailCache()
      let store = try F.photoStore()
      let record = try XCTUnwrap(store.records.last)
      let image = await cache.thumbnail(for: record, store: store)
      XCTAssertNil(image)
      XCTAssertNil(cache.cached(record))
    }

    /// The mean of red, green and blue (0…1) of one pixel.
    private static func brightness(of image: CGImage, x: Int, y: Int) -> Double? {
      var pixel = [UInt8](repeating: 0, count: 4)
      guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
      let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
        guard
          let context = CGContext(
            data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        // Draw the image so that pixel (x, y), counted from the top left, lands on the one pixel.
        context.draw(
          image,
          in: CGRect(
            x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return true
      }
      guard drawn else { return nil }
      return (Double(pixel[0]) + Double(pixel[1]) + Double(pixel[2])) / (3 * 255)
    }
  }
#endif

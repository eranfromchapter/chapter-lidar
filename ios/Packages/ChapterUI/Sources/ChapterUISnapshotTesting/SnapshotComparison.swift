#if canImport(UIKit) && canImport(XCTest) && os(iOS)
  import CoreGraphics
  import UIKit

  /// Pixel comparison of two snapshots. A pixel differs when any of its channels (red, green,
  /// blue, alpha; 8-bit sRGB) differs by more than `channelTolerance`; a snapshot fails when more
  /// than `maxDifferingFraction` of its pixels differ (critique R-18d: 8/255 and 0.5 %, which
  /// absorbs anti-aliasing drift between simulator builds).
  public struct SnapshotTolerance: Sendable, Equatable {
    public var channelTolerance: Int
    public var maxDifferingFraction: Double

    public init(channelTolerance: Int, maxDifferingFraction: Double) {
      self.channelTolerance = channelTolerance
      self.maxDifferingFraction = maxDifferingFraction
    }

    /// Every phone snapshot: > 8/255 on more than 0.5 % of pixels fails.
    public static let phone = SnapshotTolerance(channelTolerance: 8, maxDifferingFraction: 0.005)
  }

  public enum SnapshotComparison {
    public struct Result: Sendable, Equatable {
      /// Pixel size of the reference and of the new image.
      public let referenceSize: CGSize
      public let actualSize: CGSize
      /// Pixels beyond the channel tolerance (all pixels when the sizes differ).
      public let differingPixels: Int
      public let totalPixels: Int

      public var sizesMatch: Bool { referenceSize == actualSize }
      public var differingFraction: Double {
        totalPixels == 0 ? 1 : Double(differingPixels) / Double(totalPixels)
      }

      public func passes(_ tolerance: SnapshotTolerance) -> Bool {
        sizesMatch && differingFraction <= tolerance.maxDifferingFraction
      }
    }

    /// Compares `actual` with `reference`, pixel by pixel. When the sizes match it also returns an
    /// image with the differing pixels in red over a faded copy of the reference.
    public static func compare(
      reference: CGImage, actual: CGImage, channelTolerance: Int
    ) -> (result: Result, diff: CGImage?) {
      let referenceSize = CGSize(width: reference.width, height: reference.height)
      let actualSize = CGSize(width: actual.width, height: actual.height)
      guard referenceSize == actualSize,
        let expected = rgbaPixels(reference), let found = rgbaPixels(actual)
      else {
        let total = max(reference.width * reference.height, actual.width * actual.height)
        return (
          Result(
            referenceSize: referenceSize, actualSize: actualSize, differingPixels: total,
            totalPixels: total), nil
        )
      }
      var diff = [UInt8](repeating: 255, count: expected.count)
      var differing = 0
      // Raw buffers: this runs over 3 million pixels per snapshot in a Debug build.
      expected.withUnsafeBufferPointer { e in
        found.withUnsafeBufferPointer { f in
          diff.withUnsafeMutableBufferPointer { d in
            var index = 0
            while index < e.count {
              let beyond =
                abs(Int(e[index]) - Int(f[index])) > channelTolerance
                || abs(Int(e[index + 1]) - Int(f[index + 1])) > channelTolerance
                || abs(Int(e[index + 2]) - Int(f[index + 2])) > channelTolerance
                || abs(Int(e[index + 3]) - Int(f[index + 3])) > channelTolerance
              if beyond {
                differing += 1
                d[index + 1] = 0
                d[index + 2] = 0
              } else {
                // A faded reference: a quarter of its intensity over white.
                d[index] = e[index] / 4 + 191
                d[index + 1] = e[index + 1] / 4 + 191
                d[index + 2] = e[index + 2] / 4 + 191
              }
              index += 4
            }
          }
        }
      }
      let result = Result(
        referenceSize: referenceSize, actualSize: actualSize, differingPixels: differing,
        totalPixels: reference.width * reference.height)
      return (result, image(rgba: diff, width: reference.width, height: reference.height))
    }

    /// The image's pixels as 8-bit sRGB RGBA, premultiplied, rows top to bottom.
    static func rgbaPixels(_ image: CGImage) -> [UInt8]? {
      let width = image.width
      let height = image.height
      var pixels = [UInt8](repeating: 0, count: width * height * 4)
      guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
      let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
        guard
          let context = CGContext(
            data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
      }
      return drawn ? pixels : nil
    }

    static func image(rgba: [UInt8], width: Int, height: Int) -> CGImage? {
      guard let space = CGColorSpace(name: CGColorSpace.sRGB),
        let provider = CGDataProvider(data: Data(rgba) as CFData)
      else { return nil }
      return CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
        space: space,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
  }
#endif

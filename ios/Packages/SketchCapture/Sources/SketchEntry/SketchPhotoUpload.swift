import Foundation

#if canImport(ImageIO)
  import CoreGraphics
  import ImageIO
  import UniformTypeIdentifiers
#endif

public enum SketchPhotoUploadError: Error, Equatable, CustomStringConvertible {
  /// The bytes could not be decoded or re-encoded as an image.
  case unreadable
  /// This platform cannot convert the format (Linux: HEIC and PDF).
  case unsupported(SketchImageFormat)

  public var description: String {
    switch self {
    case .unreadable: return "The photo could not be read as an image."
    case .unsupported(let format):
      return "A \(format.rawValue.uppercased()) cannot be sent from this device."
    }
  }
}

/// The photo as the reader gets it (spec F16 2): the Claude API takes JPEG, PNG, WebP and GIF,
/// so a HEIC photo and a PDF's first page become JPEG; a photo whose longer side is over
/// 2048 px, or whose pixels are turned by an EXIF orientation, is redrawn upright at most
/// 2048 px as JPEG (quality 0.85), which keeps the request small. A JPEG or PNG that is already
/// upright and small enough goes as it is. The original bytes stay unchanged for the package.
public enum SketchPhotoUpload {
  public static let maxPixelSize = 2048
  public static let jpegQuality = 0.85
  /// A JPEG or PNG larger than this is re-encoded even when it is small in pixels.
  public static let maxPassThroughBytes = 4_000_000

  @Sendable
  public static func prepare(_ selection: SketchImageSelection) throws -> SketchPhotoUploadImage {
    #if canImport(ImageIO)
      switch selection.format {
      case .pdf:
        guard let image = pdfFirstPage(selection.data) else { throw SketchPhotoUploadError.unreadable }
        return SketchPhotoUploadImage(data: try jpeg(image), mediaType: "image/jpeg")
      case .jpeg, .png, .heic:
        guard let source = CGImageSourceCreateWithData(selection.data as CFData, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
          let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        else { throw SketchPhotoUploadError.unreadable }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let small = max(width, height) <= maxPixelSize
        if selection.format != .heic, small, orientation == 1,
          selection.data.count <= maxPassThroughBytes
        {
          return SketchPhotoUploadImage(data: selection.data, mediaType: selection.format.mime)
        }
        let options: [CFString: Any] = [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: min(max(width, height), maxPixelSize),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { throw SketchPhotoUploadError.unreadable }
        return SketchPhotoUploadImage(data: try jpeg(image), mediaType: "image/jpeg")
      }
    #else
      switch selection.format {
      case .jpeg, .png: return SketchPhotoUploadImage(data: selection.data, mediaType: selection.format.mime)
      case .heic, .pdf: throw SketchPhotoUploadError.unsupported(selection.format)
      }
    #endif
  }

  #if canImport(ImageIO)
    /// JPEG bytes of `image` at `jpegQuality`.
    static func jpeg(_ image: CGImage) throws -> Data {
      let data = NSMutableData()
      guard
        let destination = CGImageDestinationCreateWithData(
          data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil)
      else { throw SketchPhotoUploadError.unreadable }
      let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: jpegQuality]
      CGImageDestinationAddImage(destination, image, options as CFDictionary)
      guard CGImageDestinationFinalize(destination) else { throw SketchPhotoUploadError.unreadable }
      return data as Data
    }

    /// The first page of a PDF drawn on white, its longer side `maxPixelSize`.
    static func pdfFirstPage(_ data: Data) -> CGImage? {
      guard let provider = CGDataProvider(data: data as CFData),
        let document = CGPDFDocument(provider), let page = document.page(at: 1)
      else { return nil }
      let box = page.getBoxRect(.mediaBox)
      guard box.width > 0, box.height > 0 else { return nil }
      let longer = Double(max(box.width, box.height))
      let scale: Double = Double(maxPixelSize) / longer
      let width = Int((Double(box.width) * scale).rounded())
      let height = Int((Double(box.height) * scale).rounded())
      guard
        let context = CGContext(
          data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
      else { return nil }
      context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
      context.fill(CGRect(x: 0, y: 0, width: width, height: height))
      context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
      context.translateBy(x: -box.minX, y: -box.minY)
      context.drawPDFPage(page)
      return context.makeImage()
    }
  #endif
}

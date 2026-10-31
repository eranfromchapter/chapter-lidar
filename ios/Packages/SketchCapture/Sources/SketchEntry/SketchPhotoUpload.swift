import Foundation

#if canImport(ImageIO)
  import CoreGraphics
  import ImageIO
  import UniformTypeIdentifiers
#endif

#if canImport(PDFKit)
  import PDFKit
#endif

public enum SketchPhotoUploadError: Error, Equatable, CustomStringConvertible {
  /// The bytes could not be decoded or re-encoded as an image.
  case unreadable
  /// This platform cannot convert the format (Linux: HEIC).
  case unsupported(SketchImageFormat)

  public var description: String {
    switch self {
    case .unreadable: return "The photo could not be read as an image."
    case .unsupported(let format):
      return "A \(format.rawValue.uppercased()) cannot be sent from this device."
    }
  }
}

/// The photo as the reader gets it (spec F16 2). The Claude API takes JPEG, PNG, WebP and GIF
/// images and PDF documents:
/// - a PDF goes as the PDF itself (`application/pdf`), every page, so a plan report whose
///   dimensions are on a later page is read whole. A PDF over `maxPDFBytes` (its base64 must stay
///   under the API's 32 MB request limit) or `maxPDFPages` is trimmed to its first pages until it
///   fits, and the upload says so (`note`); a PDF whose first page alone is too large goes as
///   that page drawn as a JPEG;
/// - a HEIC photo becomes JPEG; a photo whose longer side is over 2048 px, or whose pixels are
///   turned by an EXIF orientation, is redrawn upright at most 2048 px as JPEG (quality 0.85),
///   which keeps the request small. A JPEG or PNG that is already upright and small enough goes
///   as it is.
/// The original bytes stay unchanged for the package (`sketch.<ext>`).
public enum SketchPhotoUpload {
  public static let maxPixelSize = 2048
  public static let jpegQuality = 0.85
  /// A JPEG or PNG larger than this is re-encoded even when it is small in pixels.
  public static let maxPassThroughBytes = 4_000_000
  /// The largest PDF sent whole: its base64 (4/3 of it) stays under the API's 32 MB request.
  public static let maxPDFBytes = 24_000_000
  /// The most pages of a PDF the API reads.
  public static let maxPDFPages = 100

  @Sendable
  public static func prepare(_ selection: SketchImageSelection) throws -> SketchPhotoUploadImage {
    if selection.format == .pdf { return try preparePDF(selection.data) }
    #if canImport(ImageIO)
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
    #else
      switch selection.format {
      case .jpeg, .png, .pdf:
        return SketchPhotoUploadImage(data: selection.data, mediaType: selection.format.mime)
      case .heic: throw SketchPhotoUploadError.unsupported(selection.format)
      }
    #endif
  }

  /// A PDF as it is sent: the bytes untouched when they fit (`maxBytes`, `maxPages`); else, with
  /// PDFKit, a new PDF of the first pages that fit (at least one) and a note saying how many
  /// were sent; else the first page as a JPEG. Without PDFKit (Linux) the bytes go untouched.
  public static func preparePDF(
    _ data: Data, maxBytes: Int = maxPDFBytes, maxPages: Int = maxPDFPages
  ) throws -> SketchPhotoUploadImage {
    #if canImport(PDFKit)
      guard let document = PDFDocument(data: data), document.pageCount > 0 else {
        throw SketchPhotoUploadError.unreadable
      }
      let pageCount = document.pageCount
      if data.count <= maxBytes, pageCount <= maxPages {
        return SketchPhotoUploadImage(data: data, mediaType: "application/pdf")
      }
      // The most leading pages whose PDF fits: halve the range until it is found.
      var low = 0
      var high = min(pageCount, maxPages)
      var best: Data?
      while low < high {
        let middle = (low + high + 1) / 2
        if let trimmed = firstPages(of: document, count: middle), trimmed.count <= maxBytes {
          low = middle
          best = trimmed
        } else {
          high = middle - 1
        }
      }
      if low > 0, let best {
        let note =
          "The PDF has \(pageCount) pages and is too large to send whole: Claude read the first "
          + "\(low == 1 ? "page" : "\(low) pages")."
        return SketchPhotoUploadImage(data: best, mediaType: "application/pdf", note: note)
      }
      #if canImport(ImageIO)
        guard let image = pdfFirstPage(data) else { throw SketchPhotoUploadError.unreadable }
        return SketchPhotoUploadImage(
          data: try jpeg(image), mediaType: "image/jpeg",
          note: "The PDF is too large to send: Claude read its first page as a picture.")
      #else
        throw SketchPhotoUploadError.unreadable
      #endif
    #else
      return SketchPhotoUploadImage(data: data, mediaType: "application/pdf")
    #endif
  }

  #if canImport(PDFKit)
    /// A PDF of the first `count` pages of `document` (copies, the document is unchanged).
    static func firstPages(of document: PDFDocument, count: Int) -> Data? {
      let trimmed = PDFDocument()
      for index in 0..<count {
        guard let page = document.page(at: index)?.copy() as? PDFPage else { return nil }
        trimmed.insert(page, at: index)
      }
      return trimmed.dataRepresentation()
    }
  #endif

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

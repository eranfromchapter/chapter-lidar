#if canImport(SwiftUI) && os(iOS)
  import ChapterUI
  import PDFKit
  import SketchEntry
  import SwiftUI
  import UIKit

  /// The sketch image as drawn on the phone: JPEG, PNG and HEIC through UIImage, a PDF's first
  /// page rendered through PDFKit at about two phone widths. Nil when the bytes cannot be drawn.
  enum SketchImageRendering {
    static func image(for selection: SketchImageSelection) -> UIImage? {
      switch selection.format {
      case .jpeg, .png, .heic:
        return UIImage(data: selection.data)
      case .pdf:
        guard let document = PDFDocument(data: selection.data), let page = document.page(at: 0)
        else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = min(2400 / max(bounds.width, bounds.height), 8)
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        return page.thumbnail(of: size, for: .mediaBox)
      }
    }
  }

  /// The sketch on top of Rooms and measurements: pinch to zoom (up to 6×), drag to pan, double
  /// tap to go back to the whole sketch. A UIScrollView, so the gestures are the system's.
  struct SketchZoomableImage: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIScrollView {
      let scrollView = UIScrollView()
      scrollView.delegate = context.coordinator
      scrollView.minimumZoomScale = 1
      scrollView.maximumZoomScale = 6
      scrollView.showsHorizontalScrollIndicator = false
      scrollView.showsVerticalScrollIndicator = false
      scrollView.bouncesZoom = true
      scrollView.backgroundColor = .clear
      let imageView = UIImageView(image: image)
      imageView.contentMode = .scaleAspectFit
      imageView.isAccessibilityElement = true
      imageView.accessibilityLabel = "The sketch"
      imageView.accessibilityIdentifier = "sketch.image"
      scrollView.addSubview(imageView)
      context.coordinator.imageView = imageView
      let doubleTap = UITapGestureRecognizer(
        target: context.coordinator, action: #selector(Coordinator.resetZoom(_:)))
      doubleTap.numberOfTapsRequired = 2
      scrollView.addGestureRecognizer(doubleTap)
      return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
      context.coordinator.imageView?.image = image
      context.coordinator.imageView?.frame = scrollView.bounds
      scrollView.contentSize = scrollView.bounds.size
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
      var imageView: UIImageView?

      func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

      @objc func resetZoom(_ recognizer: UITapGestureRecognizer) {
        guard let scrollView = recognizer.view as? UIScrollView else { return }
        scrollView.setZoomScale(1, animated: true)
      }
    }
  }

  /// The sketch card on the Rooms screen: the image zoomable in a 220 pt well with the card's
  /// corner and border; "Pinch to zoom" under it.
  struct SketchImageCard: View {
    let selection: SketchImageSelection

    var body: some View {
      VStack(alignment: .leading, spacing: ChapterTheme.Metric.sectionHeaderGap) {
        Group {
          if let image = SketchImageRendering.image(for: selection) {
            SketchZoomableImage(image: image)
          } else {
            Text("The sketch could not be drawn.")
              .chapterTextStyle(.footnote)
              .foregroundStyle(ChapterTheme.Color.blocked)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        }
        .frame(height: 220)
        .frame(maxWidth: .infinity)
        .background(ChapterTheme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: ChapterTheme.Metric.cardRadius))
        .overlay(
          RoundedRectangle(cornerRadius: ChapterTheme.Metric.cardRadius)
            .strokeBorder(ChapterTheme.Color.line, lineWidth: ChapterTheme.Metric.cardBorder))
        Text("Pinch to zoom \u{00B7} double tap to see the whole sketch")
          .chapterTextStyle(.footnote)
          .foregroundStyle(ChapterTheme.Color.muted)
          .padding(.horizontal, ChapterTheme.Metric.sectionInset)
      }
    }
  }

  /// The system camera for "Take a photo" of the sketch: the photo as JPEG bytes, or nil when
  /// the operator cancelled.
  struct SketchCameraPicker: UIViewControllerRepresentable {
    let onPhoto: (Data?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
      let picker = UIImagePickerController()
      picker.sourceType = .camera
      picker.cameraCaptureMode = .photo
      picker.delegate = context.coordinator
      return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPhoto: onPhoto) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
      let onPhoto: (Data?) -> Void

      init(onPhoto: @escaping (Data?) -> Void) {
        self.onPhoto = onPhoto
      }

      func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
      ) {
        let image = info[.originalImage] as? UIImage
        onPhoto(image?.jpegData(compressionQuality: 0.92))
      }

      func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        onPhoto(nil)
      }
    }
  }
#endif

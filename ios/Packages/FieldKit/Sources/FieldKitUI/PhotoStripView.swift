#if canImport(SwiftUI) && canImport(UIKit)
  import ChapterUI
  import FieldRules
  import PhotoStore
  import SwiftUI

  /// The strip under the labels (phone-field §3.5, artboard 2d-1): up to 4 thumbnails of the
  /// selected room's last photos (40 pt, radius 6, a line-coloured placeholder until decoded),
  /// then `5 photos in Kitchen · keep people and personal items out of the frame`.
  struct PhotoStripView: View {
    let strip: PhotoStrip
    let store: PhotoRecordStore

    var body: some View {
      HStack(spacing: FieldMetric.chipGap) {
        ForEach(strip.thumbnails, id: \.path) { record in
          Thumbnail(record: record, store: store)
        }
        Text(strip.text)
          .chapterTextStyle(.footnote)
          .foregroundStyle(FieldTheme.Color.muted)
          .lineLimit(3)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.leading, strip.thumbnails.isEmpty ? 0 : 4)
          .accessibilityIdentifier("photo.strip")
      }
    }
  }

  private struct Thumbnail: View {
    let record: PhotoRecord
    let store: PhotoRecordStore
    @State private var image: UIImage?

    /// A thumbnail decoded before shows at once (the strip is rebuilt after every saved photo).
    init(record: PhotoRecord, store: PhotoRecordStore) {
      self.record = record
      self.store = store
      _image = State(initialValue: ThumbnailCache.shared.cached(record))
    }

    var body: some View {
      FieldTheme.Color.line
        .frame(width: FieldMetric.thumbnail, height: FieldMetric.thumbnail)
        .overlay {
          if let image {
            Image(uiImage: image).resizable().scaledToFill()
          }
        }
        .clipShape(RoundedRectangle(cornerRadius: FieldMetric.thumbnailRadius))
        .accessibilityHidden(true)
        .task(id: record.path) {
          image = ThumbnailCache.shared.cached(record)
          if image == nil {
            image = await ThumbnailCache.shared.thumbnail(for: record, store: store)
          }
        }
    }
  }
#endif

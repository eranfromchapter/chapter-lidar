#if canImport(ARKit) && os(iOS)
  import ARKit
  import AVFoundation
  import CaptureContract
  import CoreVideo
  import Foundation
  import VideoToolbox

  /// Records the walkthrough (spec F15 2): the camera image of about 15 frames a second, scaled
  /// to 1280 px wide, HEVC (H.264 when the phone cannot encode HEVC) in an MP4 without audio,
  /// and for every recorded frame its camera pose and tracking state; the intrinsics are scaled
  /// to the video's size. Used on the frame processor's queue only.
  ///
  /// A recording error never blocks the walkthrough: the video stops, the poses go on, and
  /// `finish` reports no video (the log then names none) with the reason.
  final class WalkthroughRecorder {
    static let framesPerSecond = 15.0
    static let videoWidth = 1280

    private let url: URL
    private let clockZero: TimeInterval
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var transfer: VTPixelTransferSession?
    private var firstTimestamp: TimeInterval?
    private var lastTimestamp: TimeInterval = -.infinity
    private var frames: [WalkthroughLog.Frame] = []
    private var intrinsics: WalkthroughLog.Intrinsics?
    private var width = 0
    private var height = 0
    private var written = 0
    private var problem: String?

    init(url: URL, clockZero: TimeInterval) {
      self.url = url
      self.clockZero = clockZero
    }

    /// One camera frame: kept when 1/15 s has passed since the last one kept.
    func append(_ frame: ARFrame, tracking: (WalkthroughTracking, WalkthroughTrackingReason?)) {
      let interval = 1 / Self.framesPerSecond
      // A little early is fine: frames come at 60 or 30 a second.
      guard frame.timestamp - lastTimestamp >= interval * 0.9 else { return }
      lastTimestamp = frame.timestamp
      frames.append(
        WalkthroughLog.Frame(
          t: max(0, frame.timestamp - clockZero),
          transform: WalkthroughFrameProcessor.columnMajor(frame.camera.transform),
          tracking: tracking.0))
      guard problem == nil else { return }
      do {
        try appendVideo(frame)
      } catch {
        fail("The video could not be written: \(error.localizedDescription)")
      }
    }

    /// Finishes the file; `done` gets the recording (no video when it failed or is empty).
    func finish(_ done: @escaping (WalkthroughRecording) -> Void) {
      let frames = self.frames
      let intrinsics = self.intrinsics
      let width = self.width
      let height = self.height
      let rate = Self.framesPerSecond
      guard let writer, let input, problem == nil, written > 0 else {
        self.writer?.cancelWriting()
        try? FileManager.default.removeItem(at: url)
        done(
          WalkthroughRecording(
            frames: frames, problem: problem ?? (written == 0 ? "No video frame was recorded." : nil)))
        return
      }
      input.markAsFinished()
      let url = self.url
      writer.finishWriting {
        if writer.status == .completed {
          done(
            WalkthroughRecording(
              videoURL: url, width: width, height: height, framesPerSecond: rate,
              intrinsics: intrinsics, frames: frames))
        } else {
          try? FileManager.default.removeItem(at: url)
          let reason = writer.error?.localizedDescription ?? "unknown"
          done(
            WalkthroughRecording(
              frames: frames, problem: "The video could not be finished: \(reason)"))
        }
      }
    }

    // MARK: Video

    private func appendVideo(_ frame: ARFrame) throws {
      let image = frame.capturedImage
      if writer == nil {
        try setUp(for: frame)
      }
      guard let writer, let input, let adaptor else { return }
      guard writer.status == .writing else {
        if writer.status == .failed { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        return
      }
      guard input.isReadyForMoreMediaData else { return }
      guard let pool = adaptor.pixelBufferPool else { return }
      var scaled: CVPixelBuffer?
      CVPixelBufferPoolCreatePixelBuffer(nil, pool, &scaled)
      guard let scaled, let transfer else { return }
      let status = VTPixelTransferSessionTransferImage(transfer, from: image, to: scaled)
      guard status == noErr else { throw CocoaError(.fileWriteUnknown) }
      let first = firstTimestamp ?? frame.timestamp
      firstTimestamp = first
      let time = CMTime(seconds: frame.timestamp - first, preferredTimescale: 600)
      if adaptor.append(scaled, withPresentationTime: time) {
        written += 1
      } else if writer.status == .failed {
        throw writer.error ?? CocoaError(.fileWriteUnknown)
      }
    }

    private func setUp(for frame: ARFrame) throws {
      let source = frame.camera.imageResolution
      let sourceWidth = Double(source.width)
      let sourceHeight = Double(source.height)
      guard sourceWidth > 0, sourceHeight > 0 else { throw CocoaError(.fileWriteUnknown) }
      let scale = Double(Self.videoWidth) / sourceWidth
      width = Self.videoWidth
      // Even, as the encoders want.
      let scaledHeight: Double = (sourceHeight * scale / 2).rounded() * 2
      height = Int(scaledHeight)
      let k = frame.camera.intrinsics
      intrinsics = WalkthroughLog.Intrinsics(
        fx: Double(k.columns.0.x) * scale, fy: Double(k.columns.1.y) * scale,
        cx: Double(k.columns.2.x) * scale, cy: Double(k.columns.2.y) * scale,
        width: width, height: height)

      try? FileManager.default.removeItem(at: url)
      let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
      let compression: [String: Any] = [
        AVVideoAverageBitRateKey: 4_000_000,
        AVVideoExpectedSourceFrameRateKey: Int(Self.framesPerSecond),
      ]
      var settings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: width, AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: compression,
      ]
      if !writer.canApply(outputSettings: settings, forMediaType: .video) {
        settings[AVVideoCodecKey] = AVVideoCodecType.h264
      }
      let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
      input.expectsMediaDataInRealTime = true
      // The camera image is landscape; shown upright on a phone held in portrait.
      input.transform = CGAffineTransform(rotationAngle: .pi / 2)
      guard writer.canAdd(input) else { throw CocoaError(.fileWriteUnknown) }
      writer.add(input)
      let attributes: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String:
          kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
      ]
      let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input, sourcePixelBufferAttributes: attributes)
      var transfer: VTPixelTransferSession?
      VTPixelTransferSessionCreate(allocator: nil, pixelTransferSessionOut: &transfer)
      guard let transfer else { throw CocoaError(.fileWriteUnknown) }
      guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
      writer.startSession(atSourceTime: .zero)
      self.writer = writer
      self.input = input
      self.adaptor = adaptor
      self.transfer = transfer
    }

    private func fail(_ message: String) {
      problem = message
      writer?.cancelWriting()
    }
  }
#endif

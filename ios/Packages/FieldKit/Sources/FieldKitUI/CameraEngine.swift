#if canImport(SwiftUI) && canImport(UIKit) && canImport(AVFoundation)
  import AVFoundation
  import Foundation
  import SwiftUI
  import UIKit

  public enum CameraError: Error, Equatable, Sendable, CustomStringConvertible {
    case notAuthorized
    case unavailable
    case busy
    case noData

    public var description: String {
      switch self {
      case .notAuthorized:
        return "Camera access is off. Turn it on for Chapter Capture in Settings."
      case .unavailable: return "The camera is not available on this device."
      case .busy: return "The camera is still saving the last photo."
      case .noData: return "The camera returned no photo. Try again."
      }
    }
  }

  /// The app's own camera. It hands back the file exactly as the camera pipeline produced it
  /// (`AVCapturePhoto.fileDataRepresentation()`: HEIC when the device supports it, otherwise JPEG,
  /// with EXIF), so Chapter keeps the original. Nothing is re-encoded or cropped here.
  ///
  /// All mutable state is touched only on `queue`; that is why the class can be
  /// `@unchecked Sendable`.
  public final class CameraEngine: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    public let session = AVCaptureSession()

    private let queue = DispatchQueue(label: "com.hellochapter.capture.fieldkit.camera")
    private let output = AVCapturePhotoOutput()
    private var isConfigured = false
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var pending: CheckedContinuation<Data, Error>?

    public override init() {
      super.init()
    }

    /// Asks for camera permission when it has not been decided yet.
    public static func requestAccess() async -> Bool {
      switch AVCaptureDevice.authorizationStatus(for: .video) {
      case .authorized: return true
      case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
      default: return false
      }
    }

    /// Starts the preview. Throws when the camera is not allowed or not available.
    public func start() async throws {
      guard await Self.requestAccess() else { throw CameraError.notAuthorized }
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        queue.async {
          do {
            try self.configureIfNeeded()
            if !self.session.isRunning { self.session.startRunning() }
            continuation.resume()
          } catch {
            continuation.resume(throwing: error)
          }
        }
      }
    }

    public func stop() {
      queue.async {
        if self.session.isRunning { self.session.stopRunning() }
      }
    }

    /// Takes one photo and returns the original file bytes.
    public func capture() async throws -> Data {
      try await withCheckedThrowingContinuation { continuation in
        queue.async {
          guard self.isConfigured, self.session.isRunning else {
            continuation.resume(throwing: CameraError.unavailable)
            return
          }
          guard self.pending == nil else {
            continuation.resume(throwing: CameraError.busy)
            return
          }
          self.pending = continuation
          if let connection = self.output.connection(with: .video),
            let angle = self.rotationCoordinator?.videoRotationAngleForHorizonLevelCapture,
            connection.isVideoRotationAngleSupported(angle)
          {
            connection.videoRotationAngle = angle
          }
          let settings = self.makeSettings()
          self.output.capturePhoto(with: settings, delegate: self)
        }
      }
    }

    // MARK: Configuration (runs on `queue`)

    private func configureIfNeeded() throws {
      guard !isConfigured else { return }
      guard
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
        let input = try? AVCaptureDeviceInput(device: device)
      else { throw CameraError.unavailable }

      session.beginConfiguration()
      defer { session.commitConfiguration() }
      session.sessionPreset = .photo
      guard session.canAddInput(input), session.canAddOutput(output) else {
        throw CameraError.unavailable
      }
      session.addInput(input)
      session.addOutput(output)
      output.maxPhotoQualityPrioritization = .quality
      rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
      isConfigured = true
    }

    private func makeSettings() -> AVCapturePhotoSettings {
      let settings: AVCapturePhotoSettings
      if output.availablePhotoCodecTypes.contains(.hevc) {
        settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
      } else {
        settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
      }
      settings.photoQualityPrioritization = .quality
      return settings
    }

    // MARK: AVCapturePhotoCaptureDelegate

    public func photoOutput(
      _ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto,
      error: Error?
    ) {
      // Read the bytes here; AVCapturePhoto itself must not cross to another queue.
      let data = photo.fileDataRepresentation()
      queue.async {
        guard let continuation = self.pending else { return }
        self.pending = nil
        if let error {
          continuation.resume(throwing: error)
        } else if let data {
          continuation.resume(returning: data)
        } else {
          continuation.resume(throwing: CameraError.noData)
        }
      }
    }
  }

  /// Live camera preview for a `CameraEngine` session.
  struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
      let view = PreviewView()
      view.previewLayer.session = session
      view.previewLayer.videoGravity = .resizeAspectFill
      return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
      override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
      var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
  }
#endif

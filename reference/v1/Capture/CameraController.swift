import AVFoundation
import SwiftUI
import UIKit

/// Rear camera, phone upright, facing the wall.
final class CameraController: NSObject, AVCapturePhotoCaptureDelegate {
    enum CameraError: LocalizedError {
        case notAllowed, notRunning, noImage

        var errorDescription: String? {
            switch self {
            case .notAllowed: return "Camera access is off. Turn it on in Settings > Height Ritual > Camera."
            case .notRunning: return "The camera is not ready yet. Wait a second and try again."
            case .noImage: return "The photo could not be read. Try again."
            }
        }
    }

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "camera.session")
    private var configured = false
    private var continuation: CheckedContinuation<UIImage, Error>?

    func start() {
        Task {
            guard await Self.authorize() else { return }
            queue.async { [self] in
                if !configured { configure() }
                if !session.isRunning { session.startRunning() }
            }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func capture() async throws -> UIImage {
        guard await Self.authorize() else { throw CameraError.notAllowed }
        return try await withCheckedThrowingContinuation { cont in
            queue.async { [self] in
                guard session.isRunning else {
                    cont.resume(throwing: CameraError.notRunning)
                    return
                }
                continuation = cont
                if let connection = output.connection(with: .video),
                   connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90 // portrait
                }
                output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }
    }

    private static func authorize() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        }
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        configured = true
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        let cont = continuation
        continuation = nil
        if let error {
            cont?.resume(throwing: error)
            return
        }
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            cont?.resume(throwing: CameraError.noImage)
            return
        }
        cont?.resume(returning: image)
    }
}

/// Live camera picture for the capture screen.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        if let connection = view.previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }
}

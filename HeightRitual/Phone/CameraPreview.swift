@preconcurrency import AVFoundation
import SwiftUI
import UIKit

/// Live rear-camera picture, upright, the whole 9:16 frame visible (no cropping), so overlay
/// fractions match the recorded frame. Black where there is no camera (simulator).
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession?

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        if let session {
            let preview = PreviewView.shared(for: session)
            preview.frame = container.bounds
            preview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            container.addSubview(preview)
        }
        return container
    }

    func updateUIView(_ view: UIView, context: Context) {}

    /// One preview for the app's one session, attached once, before the
    /// session ever runs. Touching the session or its connection from the main thread waits for
    /// the session queue, which is busy for up to a second while the camera starts or stops; a
    /// new layer per visit did that on every visit and froze input for seconds (found by the UI
    /// stress test). Reusing the view means the main thread never touches the session again.
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        private static var views: [ObjectIdentifier: PreviewView] = [:]

        static func shared(for session: AVCaptureSession) -> PreviewView {
            if let view = views[ObjectIdentifier(session)] {
                view.removeFromSuperview()
                return view
            }
            let view = PreviewView()
            view.backgroundColor = .black
            view.previewLayer.videoGravity = .resizeAspect
            // Turned upright by CameraController on the session queue, once the input exists.
            view.previewLayer.session = session
            views[ObjectIdentifier(session)] = view
            return view
        }
    }
}

extension AppState {
    /// The capture session when the real camera is in use; nil in tests.
    var cameraSession: AVCaptureSession? { (camera as? CameraController)?.session }
}

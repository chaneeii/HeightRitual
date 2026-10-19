@preconcurrency import AVFoundation
import Foundation

/// Rear camera, phone upright on its stand, facing the wall. 1080p, 30 fps, movie files of about
/// 5 s (SPEC 9 step 1). The session runs on its own queue; callbacks return on the main actor.
///
/// Camera capture does not work in the simulator: there `stopRecording` returns nil.
@MainActor
final class CameraController: NSObject, CameraProviding {
    nonisolated let session = AVCaptureSession()
    private nonisolated let movieOutput = AVCaptureMovieFileOutput()
    private nonisolated let queue = DispatchQueue(label: "camera.session")
    private nonisolated(unsafe) var configured = false
    private nonisolated(unsafe) var audioInput: AVCaptureDeviceInput?

    private var pendingStop: (@MainActor (URL?) -> Void)?
    private var isRecording = false

    static var isAllowed: Bool { AVCaptureDevice.authorizationStatus(for: .video) == .authorized }
    static var isRefused: Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        return status == .denied || status == .restricted
    }

    /// The session starts after the screen's push has run: starting it takes the session's lock
    /// for up to a second, and the push must not wait on it (see `CameraPreview`).
    nonisolated static let startDelay = 0.35

    /// Whether a screen wants the preview now. The delayed start checks it, so leaving the film
    /// screen within the delay does not leave the camera running behind other screens.
    private var wantsPreview = false

    /// `askMicrophone`: with sound on, the microphone is asked for right after the camera,
    /// not later in the middle of filming.
    func startPreview(askMicrophone: Bool) {
        wantsPreview = true
        Task {
            guard await Self.authorize(.video) else { return }
            if askMicrophone { _ = await Self.authorize(.audio) }
            try? await Task.sleep(for: .seconds(Self.startDelay))
            guard wantsPreview else { return }
            queue.async { [self] in
                if !configured { configure() }
                turnPreviewUpright()
                if !session.isRunning { session.startRunning() }
            }
        }
    }

    func stopPreview() {
        wantsPreview = false
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func startRecording(sound: Bool) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("film-\(UUID().uuidString).mov")
        isRecording = true
        Task {
            // 마이크는 사운드가 켜져 있을 때만 요청한다 (SPEC 12, X1)
            let withSound = sound ? await Self.authorize(.audio) : false
            queue.async { [self] in
                if !configured { configure() }
                setAudio(withSound)
                guard session.isRunning, movieOutput.connection(with: .video) != nil else {
                    Task { @MainActor in self.recordingFinished(nil) }
                    return
                }
                if let connection = movieOutput.connection(with: .video),
                   connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
                movieOutput.startRecording(to: url, recordingDelegate: self)
            }
        }
    }

    func stopRecording(_ done: @escaping @MainActor (URL?) -> Void) {
        guard isRecording else {
            done(nil)
            return
        }
        pendingStop = done
        queue.async { [self] in
            if movieOutput.isRecording {
                movieOutput.stopRecording()
            } else {
                // Recording never began (no camera, or stopped within the first frames).
                Task { @MainActor in self.recordingFinished(nil) }
            }
        }
    }

    private func recordingFinished(_ url: URL?) {
        isRecording = false
        if let pendingStop {
            self.pendingStop = nil
            pendingStop(url)
        } else if let url {
            // Finished on its own (max duration) before anyone asked; nobody wants the file.
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: Session

    private static func authorize(_ type: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: type) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: type)
        default: return false
        }
    }

    private nonisolated func configure() {
        // Keep the app's own audio session (AudioRoute): playback stays on the phone speaker.
        session.automaticallyConfiguresApplicationAudioSession = false
        session.beginConfiguration()
        if session.canSetSessionPreset(.hd1920x1080) { session.sessionPreset = .hd1920x1080 }
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
            try? device.lockForConfiguration()
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            device.unlockForConfiguration()
        }
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
            // Safety net; AppState stops after 5 s.
            movieOutput.maxRecordedDuration = CMTime(seconds: 7, preferredTimescale: 600)
        }
        session.commitConfiguration()
        configured = true
    }

    /// The preview layer's connection exists only once the camera input is added, so it is turned
    /// upright here, on the session queue, rather than by the view on the main thread.
    private nonisolated func turnPreviewUpright() {
        for connection in session.connections where connection.videoPreviewLayer != nil {
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
        }
    }

    private nonisolated func setAudio(_ on: Bool) {
        guard on != (audioInput != nil) else { return }
        session.beginConfiguration()
        if on {
            if let mic = AVCaptureDevice.default(for: .audio),
               let input = try? AVCaptureDeviceInput(device: mic),
               session.canAddInput(input) {
                session.addInput(input)
                audioInput = input
            }
        } else if let audioInput {
            session.removeInput(audioInput)
            self.audioInput = nil
        }
        session.commitConfiguration()
    }
}

extension CameraController: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                                from connections: [AVCaptureConnection], error: Error?) {
        // A max-duration stop reports an error but still writes a usable file.
        let ok = FileManager.default.fileExists(atPath: outputFileURL.path)
        Task { @MainActor in self.recordingFinished(ok ? outputFileURL : nil) }
    }
}

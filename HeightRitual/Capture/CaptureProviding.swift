import Foundation

/// The camera as AppState sees it. The AVFoundation version comes in milestone 5.
@MainActor
protocol CameraProviding: AnyObject {
    func startPreview()
    func stopPreview()
    func startRecording(sound: Bool)
    /// Calls back with the movie file, or nil if nothing was recorded.
    func stopRecording(_ done: @escaping @MainActor (URL?) -> Void)
}

/// A cut-out clip that is not saved yet. Files live in the temporary folder until Save.
struct ProcessedClip: Equatable {
    var videoURL: URL?
    var posterURL: URL?
    var hasSound = false
    var bodyRatio: Double?
    var floorRatio: Double?
    /// Height suggested from the video (SPEC 9 step 3); nil when it could not be estimated.
    var estimatedMM: Int?
}

/// Cut-out, crop, write and estimate (SPEC 9 steps 2 to 7). The Vision version comes in milestone 6.
protocol ClipProcessing {
    /// Returns nil when nobody was found in the video.
    func process(movie: URL?, camera: CameraPosition?,
                 progress: @escaping @MainActor (Double) -> Void) async throws -> ProcessedClip?
}

/// Stands in for the camera until milestone 5, and in the simulator, which has no camera.
@MainActor
final class PlaceholderCamera: CameraProviding {
    func startPreview() {}
    func stopPreview() {}
    func startRecording(sound: Bool) {}
    func stopRecording(_ done: @escaping @MainActor (URL?) -> Void) { done(nil) }
}

/// Stands in for the cut-out until milestone 6: a clip without video and without an estimate,
/// so the height step can be walked through on the simulator.
struct PlaceholderProcessor: ClipProcessing {
    func process(movie: URL?, camera: CameraPosition?,
                 progress: @escaping @MainActor (Double) -> Void) async throws -> ProcessedClip? {
        for step in 1...4 {
            try await Task.sleep(for: .milliseconds(250))
            await progress(Double(step) / 4)
        }
        return ProcessedClip()
    }
}

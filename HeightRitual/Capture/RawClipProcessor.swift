@preconcurrency import AVFoundation
import UIKit

/// Milestone 6, first step: keeps the filmed clip as it is (no cut-out yet) and saves a poster.
/// No height estimate without the person found in the video, so the height field starts at the
/// member's last height. `VideoCutout` replaces this once segmentation is written.
struct RawClipProcessor: ClipProcessing {
    func process(movie: URL?, camera: CameraPosition?,
                 progress: @escaping @MainActor (Double) -> Void) async throws -> ProcessedClip? {
        // Simulator, or the camera gave nothing: a clip without video, so the flow can go on.
        guard let movie, FileManager.default.fileExists(atPath: movie.path) else {
            await progress(1)
            return ProcessedClip()
        }
        let temp = FileManager.default.temporaryDirectory
        let clip = temp.appendingPathComponent("clip-\(UUID().uuidString).mov")
        try FileManager.default.copyItem(at: movie, to: clip)
        await progress(0.5)

        let asset = AVURLAsset(url: clip)
        let hasSound = !((try? await asset.loadTracks(withMediaType: .audio)) ?? []).isEmpty
        var posterURL: URL?
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        if let image = try? await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image,
           let png = UIImage(cgImage: image).pngData() {
            let url = temp.appendingPathComponent("poster-\(UUID().uuidString).png")
            if (try? png.write(to: url)) != nil { posterURL = url }
        }
        await progress(1)
        return ProcessedClip(videoURL: clip, posterURL: posterURL, hasSound: hasSound)
    }
}

import AVFoundation

/// The one player for clips on the wall (SPEC 9). The projector and the phone's wall copy each
/// show it in their own AVPlayerLayer. A clip plays once and holds its last frame.
///
/// Not yet run on a device: alpha HEVC over the wall drawing, and two layers on one player.
@MainActor
final class WallPlayer {
    let player = AVPlayer()
    private(set) var url: URL?

    init() {
        player.actionAtItemEnd = .pause
        player.isMuted = true
    }

    /// Plays `url` from the start; nil clears the picture (records without a clip).
    func play(_ url: URL?, sound: Bool) {
        player.isMuted = !sound
        guard let url else {
            stop()
            return
        }
        if url != self.url {
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            self.url = url
        }
        player.seek(to: .zero)
        player.play()
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        url = nil
    }
}

import AVFoundation
import SwiftUI

/// A clip playing silently on repeat, for the height step.
struct LoopingVideo: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.play(url)
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        if view.url != url { view.play(url) }
    }

    static func dismantleUIView(_ view: PlayerView, coordinator: ()) {
        view.player.pause()
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        let player = AVQueuePlayer()
        private var looper: AVPlayerLooper?
        private(set) var url: URL?

        func play(_ url: URL) {
            self.url = url
            let layer = self.layer as! AVPlayerLayer
            layer.player = player
            layer.videoGravity = .resizeAspect
            backgroundColor = .black
            player.isMuted = true
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            player.play()
        }
    }
}

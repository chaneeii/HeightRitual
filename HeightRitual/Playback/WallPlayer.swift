import AVFoundation

/// The one player for clips on the wall (SPEC 9). The projector and the phone's wall copy each
/// show it in their own AVPlayerLayer. A clip loops until another one is chosen.
///
/// Not yet run on a device: alpha HEVC over the wall drawing, and two layers on one player.
@MainActor
final class WallPlayer {
    let player = AVPlayer()
    private(set) var url: URL?
    private var soundURL: URL?

    init() {
        // Lookback loops each clip until another record is chosen.
        player.actionAtItemEnd = .none
        player.isMuted = true
        AudioRoute.start()
        NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil,
                                               queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let item = note.object as? AVPlayerItem, item === self.player.currentItem else { return }
                self.player.seek(to: .zero)
                self.player.play()
            }
        }
    }

    /// Plays `url` from the start; nil clears the picture (records without a clip).
    /// `soundFrom`: the clip as filmed, whose sound goes with a cut-out that has none.
    func play(_ url: URL?, sound: Bool, soundFrom soundURL: URL? = nil) {
        player.isMuted = !sound
        guard let url else {
            stop()
            return
        }
        let soundURL = sound ? soundURL : nil
        if url != self.url || soundURL != self.soundURL {
            self.url = url
            self.soundURL = soundURL
            guard let soundURL else {
                player.replaceCurrentItem(with: AVPlayerItem(url: url))
                player.seek(to: .zero)
                player.play()
                return
            }
            Task {
                let item = await Self.item(video: url, sound: soundURL)
                guard self.url == url, self.soundURL == soundURL else { return }
                player.replaceCurrentItem(with: item)
                player.play()
            }
            return
        }
        player.seek(to: .zero)
        player.play()
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        url = nil
        soundURL = nil
    }

    /// The cut-out's picture with the raw clip's sound over the same time range.
    private nonisolated static func item(video: URL, sound: URL) async -> AVPlayerItem {
        let composition = AVMutableComposition()
        guard let picture = try? await AVURLAsset(url: video).loadTracks(withMediaType: .video).first,
              let range = try? await picture.load(.timeRange),
              let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              (try? track.insertTimeRange(range, of: picture, at: .zero)) != nil
        else { return AVPlayerItem(url: video) }
        track.preferredTransform = (try? await picture.load(.preferredTransform)) ?? .identity
        if let audio = try? await AVURLAsset(url: sound).loadTracks(withMediaType: .audio).first,
           let audioRange = try? await audio.load(.timeRange),
           let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? audioTrack.insertTimeRange(range.intersection(audioRange), of: audio, at: .zero)
        }
        return AVPlayerItem(asset: composition)
    }
}

/// Clip sound plays from the phone's own speaker, also while the projector is connected over
/// HDMI (the projector has no speaker). Not yet checked on a device with a projector.
enum AudioRoute {
    @MainActor private static var observer: NSObjectProtocol?

    @MainActor static func start() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker])
        try? session.setActive(true)
        useSpeaker()
        observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                .flatMap(AVAudioSession.RouteChangeReason.init)
            guard reason != .override, reason != .categoryChange else { return }
            useSpeaker()
        }
    }

    /// Headphones keep the sound; anything else (HDMI, AirPlay) goes back to the speaker.
    nonisolated static func useSpeaker() {
        let session = AVAudioSession.sharedInstance()
        let headphones = session.currentRoute.outputs.contains {
            [.headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE].contains($0.portType)
        }
        try? session.overrideOutputAudioPort(headphones ? .none : .speaker)
    }
}

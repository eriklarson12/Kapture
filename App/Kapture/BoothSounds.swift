import AVFoundation
import KaptureKit
import Observation

/// Players are built once, at init: constructing an `AVAudioPlayer` on the
/// beat is how a shutter arrives after the flash it belongs to.
@MainActor
@Observable
final class BoothSounds: CaptureCueSink {
    var isMuted = false

    @ObservationIgnored private var players: [CaptureCue: AVAudioPlayer] = [:]

    init() {
        for cue in CaptureCue.allCases {
            guard let player = try? AVAudioPlayer(data: SoundCue.wav(for: cue)) else { continue }
            player.prepareToPlay()
            players[cue] = player
        }
    }

    /// Rewinds before playing: a cue can be asked for again before the last one
    /// finished ringing. Cues never overlap in a run, so one player each is enough.
    func play(_ cue: CaptureCue) {
        guard !isMuted, let player = players[cue] else { return }
        player.currentTime = 0
        player.play()
    }
}

import AVFoundation
import MediaPlayer
import Observation

/// Single app-wide audio player. Keeps playing in the background and drives the
/// lock screen / car / AirPods controls.
@MainActor
@Observable
final class PlayerEngine {
    /// Notes are placed slightly before the tap to allow for reaction time.
    static let reactionOffset: TimeInterval = 2

    private(set) var loadedMixID: UUID?
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

    /// Called when "next track" is pressed on the car, headphones or lock screen.
    /// The argument is the playback time, already adjusted for reaction time.
    @ObservationIgnored var onRemoteMarker: ((TimeInterval) -> Void)?

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var title = ""
    @ObservationIgnored private var subtitle = ""
    @ObservationIgnored private let finishDelegate = FinishDelegate()

    init() {
        configureRemoteCommands()
        finishDelegate.onFinish = { [weak self] in
            Task { @MainActor in self?.didFinish() }
        }
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard raw == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor in self?.pause() }
        }
    }

    var markerTime: TimeInterval { max(0, currentTime - Self.reactionOffset) }

    func load(mixID: UUID, url: URL, title: String, subtitle: String) throws {
        pause()
        let newPlayer = try AVAudioPlayer(contentsOf: url)
        newPlayer.delegate = finishDelegate
        newPlayer.prepareToPlay()
        player = newPlayer
        loadedMixID = mixID
        duration = newPlayer.duration
        currentTime = 0
        self.title = title
        self.subtitle = subtitle
        updateNowPlaying()
    }

    func unload(mixID: UUID) {
        guard loadedMixID == mixID else { return }
        pause()
        player = nil
        loadedMixID = nil
        duration = 0
        currentTime = 0
        onRemoteMarker = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func play() {
        guard let player else { return }
        AudioSessionSetup.configureForPlayback()
        try? AVAudioSession.sharedInstance().setActive(true)
        guard player.play() else { return }
        isPlaying = true
        startTimer()
        updateNowPlaying()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        timer?.invalidate()
        timer = nil
        currentTime = player?.currentTime ?? 0
        updateNowPlaying()
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        let clamped = min(max(0, time), max(0, duration - 0.05))
        player.currentTime = clamped
        currentTime = clamped
        updateNowPlaying()
    }

    func skip(by delta: TimeInterval) {
        seek(to: (player?.currentTime ?? 0) + delta)
    }

    // MARK: - Private

    private func didFinish() {
        isPlaying = false
        timer?.invalidate()
        timer = nil
        currentTime = 0
        updateNowPlaying()
    }

    private func startTimer() {
        timer?.invalidate()
        let newTimer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
            }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func updateNowPlaying() {
        guard let player else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: subtitle,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.play() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.toggle() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor in self?.seek(to: position) }
            return .success
        }
        // "Previous" jumps back 15 seconds so a section can be re-heard hands-free.
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skip(by: -15) }
            return .success
        }
        // "Next" adds a note (spoken, or a bare marker) instead of changing track.
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self, self.loadedMixID != nil else { return }
                self.onRemoteMarker?(self.markerTime)
            }
            return .success
        }
    }
}

private final class FinishDelegate: NSObject, AVAudioPlayerDelegate {
    var onFinish: (() -> Void)?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish?()
    }
}

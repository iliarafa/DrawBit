import Foundation
import Observation
import AVFoundation
import MediaPlayer

/// The DrawBit FM station — owns the bundled `Playlist` and the AVFoundation
/// playback engine. Created once at app scope (`DrawBitApp`) and injected into
/// the environment so playback survives the Gallery↔Editor switch and the
/// background / lock screen.
///
/// AVFoundation/MediaPlayer are isolated to this file; the sequencing logic lives
/// in the pure `Playlist`. Mirrors `PlaybackController`'s timer discipline (main
/// run loop, `.common` mode, invalidate on stop/deinit).
@MainActor
@Observable
final class RadioController {
    @ObservationIgnored private var playlist: Playlist
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var progressTimer: Timer?
    @ObservationIgnored private var sessionConfigured = false
    @ObservationIgnored private var remoteCommandsConfigured = false
    @ObservationIgnored private var consecutiveFailures = 0
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private lazy var playerDelegate = PlayerDelegate(owner: self)

    /// True while the station is playing.
    private(set) var isPlaying = false
    /// Position within the current track, 0...1.
    private(set) var progress: Double = 0
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

    init(tracks: [AudioTrack]? = nil) {
        self.playlist = Playlist(tracks: tracks ?? BundledTracks.load())
        registerSessionObservers()
    }

    deinit {
        progressTimer?.invalidate()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Public surface (UI binds to this)

    var hasTracks: Bool { !playlist.isEmpty }
    var currentTitle: String { playlist.current?.title ?? "" }
    /// All tracks in the station, in playback order. Lets a track list UI render
    /// the full programme.
    var tracks: [AudioTrack] { playlist.tracks }
    /// Index of the currently-selected track (0 when the station is empty).
    /// Lets a track list UI highlight the active row.
    var currentIndex: Int { playlist.currentIndex }

    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    func play() {
        guard playlist.current != nil else { return }
        if player == nil { loadCurrentTrack(autoplay: false) }
        ensureSessionActive()
        player?.play()
        isPlaying = true
        startProgressTimer()
        updateNowPlaying()
    }

    /// `deactivateSession` releases the shared audio session so a previously-interrupted app
    /// (Spotify, a podcast) may auto-resume — the good-citizen behavior for a *user* pause; play()
    /// reactivates it. System-induced pauses (an interruption began, headphones unplugged) pass
    /// `false`: the OS already owns the session on an interruption, and handing audio to another
    /// app on an unplug isn't wanted.
    func pause(deactivateSession: Bool = true) {
        player?.pause()
        isPlaying = false
        stopProgressTimer()
        updateNowPlaying()
        if deactivateSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    func next() {
        guard !playlist.isEmpty else { return }
        playlist.next()
        loadCurrentTrack(autoplay: isPlaying)
    }

    func previous() {
        guard !playlist.isEmpty else { return }
        playlist.previous()
        loadCurrentTrack(autoplay: isPlaying)
    }

    /// Jump to a specific track and start playing it. Out-of-range indices are
    /// ignored (mirrors `Playlist.select(index:)`). Mirrors the `next()`/`previous()`
    /// discipline but always autoplays — a tap on the track list is an explicit
    /// "play this one" gesture.
    func play(trackAt index: Int) {
        guard !playlist.isEmpty, playlist.tracks.indices.contains(index) else { return }
        playlist.select(index: index)
        loadCurrentTrack(autoplay: true)
    }

    func seek(toFraction fraction: Double) {
        guard let player, player.duration > 0 else { return }
        let clamped = min(1, max(0, fraction))
        let target = clamped * player.duration
        player.currentTime = target
        currentTime = target
        duration = player.duration
        progress = clamped
        updateNowPlaying()
    }

    // MARK: - Track loading & auto-advance

    private func loadCurrentTrack(autoplay: Bool) {
        guard let track = playlist.current else { return }
        do {
            let p = try AVAudioPlayer(contentsOf: track.url)
            p.delegate = playerDelegate
            p.prepareToPlay()
            player = p
            consecutiveFailures = 0
            duration = p.duration
            currentTime = 0
            progress = 0
            if autoplay {
                ensureSessionActive()
                p.play()
                isPlaying = true
                startProgressTimer()
            }
            updateNowPlaying()
        } catch {
            advanceAfterFailure()
        }
    }

    /// Called by the delegate when a track ends. Playlist-radio: advance and loop.
    fileprivate func trackFinished(successfully flag: Bool) {
        if flag {
            playlist.advance()
            loadCurrentTrack(autoplay: true)
        } else {
            advanceAfterFailure()
        }
    }

    private func advanceAfterFailure() {
        consecutiveFailures += 1
        // Give up if every track in the station fails to decode.
        guard consecutiveFailures < max(1, playlist.tracks.count) else {
            stop()
            consecutiveFailures = 0
            return
        }
        playlist.advance()
        loadCurrentTrack(autoplay: true)
    }

    private func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        stopProgressTimer()
        progress = 0
        currentTime = 0
        clearNowPlaying()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Progress timer

    private func startProgressTimer() {
        stopProgressTimer()
        let t = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickProgress() }
        }
        // .common keeps it firing during gallery scroll-tracking, like PlaybackController.
        RunLoop.main.add(t, forMode: .common)
        progressTimer = t
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func tickProgress() {
        guard let player else { return }
        currentTime = player.currentTime
        duration = player.duration
        progress = player.duration > 0 ? player.currentTime / player.duration : 0
    }

    // MARK: - Audio session, interruptions, route changes

    private func ensureSessionActive() {
        // FM is starting — silence the launch intro so the two never overlap. Runs
        // before the category flips to `.playback`, so the handoff is clean. No-op if
        // the intro was never played.
        IntroAudio.shared.stop()
        let session = AVAudioSession.sharedInstance()
        if !sessionConfigured {
            // .playback: DrawBit FM is the app's primary audio — it plays over the
            // silent switch while the app is in the foreground. (Interrupts other
            // apps' audio, e.g. Spotify; that's intended for a station.) The app
            // declares no `audio` UIBackgroundModes, so playback stops when the app
            // is backgrounded — see project.yml (App Review guideline 2.5.4).
            try? session.setCategory(.playback, mode: .default)
            configureRemoteCommands()
            sessionConfigured = true
        }
        try? session.setActive(true)
    }

    private func registerSessionObservers() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification,
                                        object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated { self?.handleInterruption(note) }
        })
        observers.append(nc.addObserver(forName: AVAudioSession.routeChangeNotification,
                                        object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated { self?.handleRouteChange(note) }
        })
    }

    private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            if isPlaying { pause(deactivateSession: false) }
        case .ended:
            if let optRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt,
               AVAudioSession.InterruptionOptions(rawValue: optRaw).contains(.shouldResume) {
                play()
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        // Headphones/Bluetooth removed → pause, the expected behavior. System-induced, so keep the
        // session (don't hand audio to another app blasting on the speaker).
        if reason == .oldDeviceUnavailable, isPlaying { pause(deactivateSession: false) }
    }

    // MARK: - Now Playing / remote commands

    private func configureRemoteCommands() {
        guard !remoteCommandsConfigured else { return }
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.play() }; return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }; return .success
        }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.togglePlayPause() }; return .success
        }
        c.nextTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.next() }; return .success
        }
        c.previousTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.previous() }; return .success
        }
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let e = event as? MPChangePlaybackPositionCommandEvent,
                      self.duration > 0 else { return .commandFailed }
                self.seek(toFraction: e.positionTime / self.duration)
                return .success
            }
        }
        remoteCommandsConfigured = true
    }

    private func updateNowPlaying() {
        guard let track = playlist.current, player != nil else { clearNowPlaying(); return }
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = track.title
        info[MPMediaItemPropertyArtist] = "DrawBit FM"
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func clearNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}

/// Separate `NSObject` shim so the `@Observable` controller doesn't have to
/// conform to `AVAudioPlayerDelegate` itself. Forwards track-end to the owner.
private final class PlayerDelegate: NSObject, AVAudioPlayerDelegate {
    weak var owner: RadioController?
    init(owner: RadioController) { self.owner = owner }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in owner?.trackFinished(successfully: flag) }
    }
}

import AVFoundation
import SwiftUI
import UIKit

struct AVFoundationDASHPlayerView: UIViewRepresentable {
    let source: PlayableVideoSource
    let playbackState: BilibiliVLCPlaybackState
    let commandCenter: BilibiliVLCCommandCenter

    func makeCoordinator() -> Coordinator {
        Coordinator(playbackState: playbackState, commandCenter: commandCenter)
    }

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.backgroundColor = .black
        context.coordinator.attach(to: view.playerLayer)
        context.coordinator.play(source: source)
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        context.coordinator.attach(to: uiView.playerLayer)
        context.coordinator.play(source: source)
    }

    static func dismantleUIView(_ uiView: PlayerContainerView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        private let player = AVPlayer()
        private weak var playerLayer: AVPlayerLayer?
        private weak var playbackState: BilibiliVLCPlaybackState?
        private weak var commandCenter: BilibiliVLCCommandCenter?
        private var currentSource: PlayableVideoSource?
        private var loadTask: Task<Void, Never>?
        private var statusObserver: NSKeyValueObservation?
        private var timeObserver: Any?
        private var shouldAutoplay = true

        init(playbackState: BilibiliVLCPlaybackState, commandCenter: BilibiliVLCCommandCenter) {
            self.playbackState = playbackState
            self.commandCenter = commandCenter
            bindCommands()
        }

        deinit {
            removeTimeObserver()
        }

        func attach(to layer: AVPlayerLayer) {
            playerLayer = layer
            layer.videoGravity = .resizeAspect
            layer.player = player
        }

        func play(source: PlayableVideoSource) {
            guard source != currentSource else { return }
            currentSource = source
            shouldAutoplay = true
            loadTask?.cancel()
            statusObserver?.invalidate()
            statusObserver = nil
            removeTimeObserver()
            playbackState?.resetForNewMedia()
            player.pause()
            player.replaceCurrentItem(with: nil)

            loadTask = Task { [weak self] in
                await self?.loadAndPlay(source: source)
            }
        }

        func stop() {
            loadTask?.cancel()
            statusObserver?.invalidate()
            statusObserver = nil
            removeTimeObserver()
            player.pause()
            player.replaceCurrentItem(with: nil)
            currentSource = nil
        }

        private func bindCommands() {
            commandCenter?.togglePlayHandler = { [weak self] in
                guard let self else { return }
                if self.player.timeControlStatus == .playing {
                    self.player.pause()
                    self.shouldAutoplay = false
                } else {
                    self.shouldAutoplay = true
                    self.player.play()
                }
                self.updatePlaybackState()
            }

            commandCenter?.playHandler = { [weak self] in
                guard let self else { return }
                self.shouldAutoplay = true
                self.player.play()
                self.updatePlaybackState()
            }

            commandCenter?.pauseHandler = { [weak self] in
                guard let self else { return }
                self.shouldAutoplay = false
                self.player.pause()
                self.updatePlaybackState()
            }

            commandCenter?.seekHandler = { [weak self] position, resumePlayback in
                guard let self, let item = self.player.currentItem else { return }
                let duration = item.duration
                guard duration.isValid, duration.isNumeric, duration.seconds > 0 else { return }
                let target = CMTime(seconds: duration.seconds * min(max(position, 0), 1), preferredTimescale: 600)
                self.player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                    guard let self else { return }
                    if resumePlayback {
                        self.shouldAutoplay = true
                        self.player.play()
                    }
                    self.playbackState?.pendingSeekPosition = nil
                    self.updatePlaybackState()
                }
            }

            commandCenter?.stopHandler = { [weak self] in
                self?.stop()
            }
        }

        private func loadAndPlay(source: PlayableVideoSource) async {
            guard let audioURL = source.audioURL else { return }
            configureAudioSession()

            if (source.quality ?? 0) > 80 {
                do {
                    HLSPlaybackDiagnostics.shared.reset()
                    let manifestURL = try await DashHLSManifestService().makeManifest(for: source)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        let item = AVPlayerItem(url: manifestURL)
                        item.preferredForwardBufferDuration = 0.8
                        self.player.automaticallyWaitsToMinimizeStalling = false
                        self.observe(item: item)
                        self.player.replaceCurrentItem(with: item)
                        self.addTimeObserver()
                        self.updatePlaybackState()
                        self.playWhenReady(item: item)
                    }
                } catch {
                    print("DASH to HLS load failed: \(error.localizedDescription)")
                }
                return
            }

            do {
                let item = try await makePlayerItem(videoURL: source.url, audioURL: audioURL, headers: source.headers)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.player.automaticallyWaitsToMinimizeStalling = false
                    self.player.replaceCurrentItem(with: item)
                    self.addTimeObserver()
                    self.updatePlaybackState()
                    self.playWhenReady(item: item)
                }
            } catch {
                print("AVFoundation DASH load failed: \(error.localizedDescription)")
            }
        }

        private func observe(item: AVPlayerItem) {
            statusObserver?.invalidate()
            statusObserver = item.observe(\.status, options: [.new]) { item, _ in
                switch item.status {
                case .readyToPlay:
                    HLSPlaybackDiagnostics.shared.recordPlayerStatus("ready")
                    if self.shouldAutoplay {
                        self.player.play()
                    }
                    self.updatePlaybackState()
                case .failed:
                    HLSPlaybackDiagnostics.shared.recordPlayerStatus("failed:\(item.error?.localizedDescription ?? "unknown")")
                case .unknown:
                    HLSPlaybackDiagnostics.shared.recordPlayerStatus("unknown")
                @unknown default:
                    HLSPlaybackDiagnostics.shared.recordPlayerStatus("other")
                }
            }
        }

        private func playWhenReady(item: AVPlayerItem) {
            shouldAutoplay = true
            player.play()
            if item.status != .readyToPlay {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self, weak item] in
                    guard let self, self.shouldAutoplay, item === self.player.currentItem else { return }
                    self.player.play()
                    self.updatePlaybackState()
                }
            }
        }

        private func addTimeObserver() {
            removeTimeObserver()
            timeObserver = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
                queue: .main
            ) { [weak self] _ in
                self?.updatePlaybackState()
            }
        }

        private func removeTimeObserver() {
            if let timeObserver {
                player.removeTimeObserver(timeObserver)
                self.timeObserver = nil
            }
        }

        private func updatePlaybackState() {
            guard let playbackState else { return }
            let current = player.currentTime()
            let duration = player.currentItem?.duration ?? .invalid
            let isPlaying = player.timeControlStatus == .playing
            DispatchQueue.main.async {
                playbackState.isPlaying = isPlaying
                guard duration.isValid, duration.isNumeric, duration.seconds > 0 else {
                    playbackState.elapsedText = Self.timeText(current.seconds)
                    playbackState.durationText = "00:00"
                    return
                }
                if let pendingSeekPosition = playbackState.pendingSeekPosition {
                    playbackState.position = pendingSeekPosition
                } else if !playbackState.isScrubbing {
                    playbackState.position = min(max(current.seconds / duration.seconds, 0), 1)
                }
                playbackState.elapsedText = Self.timeText(current.seconds)
                playbackState.durationText = Self.timeText(duration.seconds)
            }
        }

        private static func timeText(_ seconds: Double) -> String {
            guard seconds.isFinite, seconds >= 0 else { return "00:00" }
            let totalSeconds = Int(seconds.rounded(.down))
            let minutes = totalSeconds / 60
            let remainingSeconds = totalSeconds % 60
            return String(format: "%02d:%02d", minutes, remainingSeconds)
        }

        private func configureAudioSession() {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .moviePlayback, options: [])
                try session.setActive(true)
            } catch {
                print("Failed to configure AVFoundation DASH audio session: \(error.localizedDescription)")
            }
        }

        private func makePlayerItem(videoURL: URL, audioURL: URL, headers: [String: String]) async throws -> AVPlayerItem {
            let options = assetOptions(headers: headers)
            let videoAsset = AVURLAsset(url: videoURL, options: options)
            let audioAsset = AVURLAsset(url: audioURL, options: options)

            let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
            let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
            guard let videoTrack = videoTracks.first else {
                throw AVFoundationDASHError.missingVideoTrack
            }
            guard let audioTrack = audioTracks.first else {
                throw AVFoundationDASHError.missingAudioTrack
            }

            let duration = try await videoAsset.load(.duration)
            let composition = AVMutableComposition()
            guard let compositionVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw AVFoundationDASHError.cannotCreateCompositionTrack
            }
            try compositionVideoTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: videoTrack,
                at: .zero
            )
            compositionVideoTrack.preferredTransform = try await videoTrack.load(.preferredTransform)

            if let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) {
                let audioDuration = try await audioAsset.load(.duration)
                let targetDuration = min(duration, audioDuration)
                try compositionAudioTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: targetDuration),
                    of: audioTrack,
                    at: .zero
                )
            }

            let item = AVPlayerItem(asset: composition)
            item.preferredForwardBufferDuration = 1
            return item
        }

        private func assetOptions(headers: [String: String]) -> [String: Any] {
            var enrichedHeaders = headers
            if let cookieHeader = BilibiliCookieStore.cookieHeader() {
                enrichedHeaders["Cookie"] = cookieHeader
            }
            enrichedHeaders["Accept"] = "*/*"
            enrichedHeaders["Connection"] = "keep-alive"
            return ["AVURLAssetHTTPHeaderFieldsKey": enrichedHeaders]
        }
    }

    final class PlayerContainerView: UIView {
        override class var layerClass: AnyClass {
            AVPlayerLayer.self
        }

        var playerLayer: AVPlayerLayer {
            layer as! AVPlayerLayer
        }
    }
}

enum AVFoundationDASHError: Error {
    case missingVideoTrack
    case missingAudioTrack
    case cannotCreateCompositionTrack
}

import AVFoundation
import SwiftUI
import UIKit

struct AVFoundationDASHPlayerView: UIViewRepresentable {
    let source: PlayableVideoSource
    let commandCenter: BilibiliVLCCommandCenter

    func makeCoordinator() -> Coordinator {
        Coordinator(commandCenter: commandCenter)
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
        private weak var commandCenter: BilibiliVLCCommandCenter?
        private var currentSource: PlayableVideoSource?
        private var loadTask: Task<Void, Never>?

        init(commandCenter: BilibiliVLCCommandCenter) {
            self.commandCenter = commandCenter
            self.commandCenter?.togglePlayHandler = { [weak self] in
                guard let self else { return }
                if self.player.timeControlStatus == .playing {
                    self.player.pause()
                } else {
                    self.player.play()
                }
            }
            self.commandCenter?.stopHandler = { [weak self] in
                self?.stop()
            }
        }

        func attach(to layer: AVPlayerLayer) {
            playerLayer = layer
            layer.videoGravity = .resizeAspect
            layer.player = player
        }

        func play(source: PlayableVideoSource) {
            guard source != currentSource else { return }
            currentSource = source
            loadTask?.cancel()
            player.pause()
            player.replaceCurrentItem(with: nil)

            loadTask = Task { [weak self] in
                await self?.loadAndPlay(source: source)
            }
        }

        func stop() {
            loadTask?.cancel()
            player.pause()
            player.replaceCurrentItem(with: nil)
            currentSource = nil
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
                        item.preferredForwardBufferDuration = 2
                        self.player.replaceCurrentItem(with: item)
                        self.player.play()
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
                    self.player.replaceCurrentItem(with: item)
                    self.player.play()
                }
            } catch {
                print("AVFoundation DASH load failed: \(error.localizedDescription)")
            }
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
            item.preferredForwardBufferDuration = 4
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

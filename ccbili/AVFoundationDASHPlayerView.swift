import AVFoundation
import AVKit
import SwiftUI
import UIKit

struct AVFoundationDASHPlayerView: UIViewControllerRepresentable {
    let source: PlayableVideoSource
    let playbackState: BilibiliVLCPlaybackState
    let commandCenter: BilibiliVLCCommandCenter

    func makeCoordinator() -> Coordinator {
        Coordinator(playbackState: playbackState, commandCenter: commandCenter)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = context.coordinator.player
        context.coordinator.attachInlineController(controller)
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = true
        controller.videoGravity = .resizeAspect
        context.coordinator.play(source: source)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== context.coordinator.player {
            controller.player = context.coordinator.player
        }
        context.coordinator.attachInlineController(controller)
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspect
        context.coordinator.play(source: source)
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.stop()
        AppOrientationController.lock(.portrait)
    }

    final class Coordinator {
        let player = AVPlayer()
        private weak var playbackState: BilibiliVLCPlaybackState?
        private weak var commandCenter: BilibiliVLCCommandCenter?
        private var currentSource: PlayableVideoSource?
        private var loadTask: Task<Void, Never>?
        private var statusObserver: NSKeyValueObservation?
        private var timeObserver: Any?
        private var shouldAutoplay = true
        private var orientationObserver: NSObjectProtocol?
        private weak var inlinePlayerViewController: AVPlayerViewController?
        private var fullscreenWindow: UIWindow?
        private var fullscreenController: LandscapePlayerFullscreenController?

        init(playbackState: BilibiliVLCPlaybackState, commandCenter: BilibiliVLCCommandCenter) {
            self.playbackState = playbackState
            self.commandCenter = commandCenter
            bindCommands()
            startOrientationObservation()
        }

        deinit {
            stopOrientationObservation()
            dismissLandscapeFullscreen()
            removeTimeObserver()
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
            dismissLandscapeFullscreen()
            loadTask?.cancel()
            statusObserver?.invalidate()
            statusObserver = nil
            removeTimeObserver()
            player.pause()
            player.replaceCurrentItem(with: nil)
            currentSource = nil
        }

        func attachInlineController(_ controller: AVPlayerViewController) {
            inlinePlayerViewController = controller
            if fullscreenController == nil, controller.player !== player {
                controller.player = player
            }
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

        private func startOrientationObservation() {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            orientationObserver = NotificationCenter.default.addObserver(
                forName: UIDevice.orientationDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.handleDeviceOrientationChange(UIDevice.current.orientation)
            }
        }

        private func stopOrientationObservation() {
            if let orientationObserver {
                NotificationCenter.default.removeObserver(orientationObserver)
                self.orientationObserver = nil
            }
        }

        private func handleDeviceOrientationChange(_ orientation: UIDeviceOrientation) {
            switch orientation {
            case .landscapeLeft, .landscapeRight:
                presentLandscapeFullscreen(orientation: orientation)
            case .portrait, .portraitUpsideDown:
                dismissLandscapeFullscreen()
            default:
                break
            }
        }

        private func presentLandscapeFullscreen(orientation: UIDeviceOrientation) {
            if let fullscreenController {
                fullscreenController.update(orientation: orientation)
                return
            }

            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
            else { return }

            let inlineFrame = inlinePlayerViewController?.view.convert(
                inlinePlayerViewController?.view.bounds ?? .zero,
                to: nil
            )
            let controller = LandscapePlayerFullscreenController(
                player: player,
                orientation: orientation,
                sourceFrame: inlineFrame
            )
            inlinePlayerViewController?.player = nil
            let window = UIWindow(windowScene: scene)
            window.windowLevel = .alert + 2
            window.backgroundColor = .black
            window.rootViewController = controller
            window.isHidden = false
            fullscreenWindow = window
            fullscreenController = controller
            controller.animateIn()
        }

        private func dismissLandscapeFullscreen() {
            guard let controller = fullscreenController, let window = fullscreenWindow else {
                inlinePlayerViewController?.player = player
                return
            }
            fullscreenController = nil
            fullscreenWindow = nil
            controller.animateOut { [weak self] in
                controller.detachPlayer()
                window.isHidden = true
                AppOrientationController.lock(.portrait, scene: window.windowScene)
                self?.inlinePlayerViewController?.player = self?.player
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
}

final class LandscapePlayerFullscreenController: UIViewController {
    private let player: AVPlayer
    private let playerViewController = AVPlayerViewController()
    private let sourceFrame: CGRect?
    private var orientation: UIDeviceOrientation
    private var currentScale: CGFloat = 1
    private var currentAlpha: CGFloat = 1
    private var currentCenter: CGPoint?

    init(player: AVPlayer, orientation: UIDeviceOrientation, sourceFrame: CGRect?) {
        self.player = player
        self.orientation = orientation
        self.sourceFrame = sourceFrame
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { orientationMask }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .portrait }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setNeedsUpdateOfHomeIndicatorAutoHidden()

        playerViewController.player = player
        playerViewController.showsPlaybackControls = true
        playerViewController.allowsPictureInPicturePlayback = true
        playerViewController.videoGravity = .resizeAspect
        playerViewController.view.backgroundColor = .black

        addChild(playerViewController)
        view.addSubview(playerViewController.view)
        playerViewController.didMove(toParent: self)
        update(orientation: orientation)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setNeedsUpdateOfSupportedInterfaceOrientations()
        AppOrientationController.lock(orientationMask, scene: view.window?.windowScene)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutPlayerView()
    }

    func update(orientation: UIDeviceOrientation) {
        self.orientation = orientation
        guard isViewLoaded else { return }
        setNeedsUpdateOfSupportedInterfaceOrientations()
        AppOrientationController.lock(orientationMask, scene: view.window?.windowScene)
        currentScale = 1
        currentAlpha = 1
        currentCenter = nil
        UIView.animate(
            withDuration: 0.36,
            delay: 0,
            usingSpringWithDamping: 0.86,
            initialSpringVelocity: 0.18,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            self.layoutPlayerView()
        }
    }

    func animateIn() {
        guard isViewLoaded else { return }
        currentAlpha = 0
        currentScale = initialPresentationScale()
        currentCenter = sourceFrame.map { CGPoint(x: $0.midX, y: $0.midY) }
        layoutPlayerView()
        UIView.animate(
            withDuration: 0.42,
            delay: 0,
            usingSpringWithDamping: 0.84,
            initialSpringVelocity: 0.2,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            self.currentAlpha = 1
            self.currentScale = 1
            self.currentCenter = nil
            self.layoutPlayerView()
        }
    }

    func animateOut(completion: @escaping () -> Void) {
        guard isViewLoaded else {
            completion()
            return
        }
        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseInOut, .allowUserInteraction]
        ) {
            self.currentScale = self.initialPresentationScale()
            self.currentAlpha = 0
            self.currentCenter = self.sourceFrame.map { CGPoint(x: $0.midX, y: $0.midY) }
            self.layoutPlayerView()
        } completion: { _ in
            completion()
        }
    }

    func detachPlayer() {
        playerViewController.player = nil
        playerViewController.willMove(toParent: nil)
        playerViewController.view.removeFromSuperview()
        playerViewController.removeFromParent()
    }

    private func layoutPlayerView() {
        let bounds = view.bounds
        let rotationAngle: CGFloat = orientation == .landscapeLeft ? .pi / 2 : -.pi / 2
        playerViewController.view.bounds = CGRect(x: 0, y: 0, width: bounds.height, height: bounds.width)
        playerViewController.view.center = currentCenter ?? CGPoint(x: bounds.midX, y: bounds.midY)
        playerViewController.view.transform = CGAffineTransform(rotationAngle: rotationAngle)
            .scaledBy(x: currentScale, y: currentScale)
        playerViewController.view.alpha = currentAlpha
    }

    private func initialPresentationScale() -> CGFloat {
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0 else { return 0.92 }
        let inlineHeight = bounds.width * 9 / 16
        let fullscreenHeight = bounds.width
        return max(0.2, min(1, inlineHeight / fullscreenHeight))
    }

    private var orientationMask: UIInterfaceOrientationMask {
        orientation == .landscapeLeft ? .landscapeRight : .landscapeLeft
    }
}

enum AVFoundationDASHError: Error {
    case missingVideoTrack
    case missingAudioTrack
    case cannotCreateCompositionTrack
}

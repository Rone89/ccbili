import AVFoundation
import AVKit
import MediaPlayer
import SwiftUI
import UIKit

struct AVFoundationDASHPlayerView: UIViewControllerRepresentable {
    let source: PlayableVideoSource
    let playbackState: BilibiliVLCPlaybackState
    let commandCenter: BilibiliVLCCommandCenter
    let onVideoSizeChange: (CGSize) -> Void

    init(
        source: PlayableVideoSource,
        playbackState: BilibiliVLCPlaybackState,
        commandCenter: BilibiliVLCCommandCenter,
        onVideoSizeChange: @escaping (CGSize) -> Void = { _ in }
    ) {
        self.source = source
        self.playbackState = playbackState
        self.commandCenter = commandCenter
        self.onVideoSizeChange = onVideoSizeChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            playbackState: playbackState,
            commandCenter: commandCenter,
            onVideoSizeChange: onVideoSizeChange
        )
    }

    func makeUIViewController(context: Context) -> InlineAVPlayerContainerController {
        let controller = InlineAVPlayerContainerController()
        context.coordinator.configurePlayerController()
        context.coordinator.attachInlineContainer(controller)
        context.coordinator.play(source: source)
        return controller
    }

    func updateUIViewController(_ controller: InlineAVPlayerContainerController, context: Context) {
        context.coordinator.onVideoSizeChange = onVideoSizeChange
        context.coordinator.configurePlayerController()
        context.coordinator.attachInlineContainer(controller)
        context.coordinator.play(source: source)
    }

    static func dismantleUIViewController(_ controller: InlineAVPlayerContainerController, coordinator: Coordinator) {
        coordinator.playerViewController.delegate = nil
        coordinator.stop()
        coordinator.teardownPlayerController()
        AppOrientationController.lock(.portrait)
    }

    final class Coordinator: NSObject, AVPlayerViewControllerDelegate, UIGestureRecognizerDelegate {
        let player = AVPlayer()
        let playerViewController = LandscapeAVPlayerController()
        var onVideoSizeChange: (CGSize) -> Void
        private weak var playbackState: BilibiliVLCPlaybackState?
        private weak var commandCenter: BilibiliVLCCommandCenter?
        private var currentSource: PlayableVideoSource?
        private var loadTask: Task<Void, Never>?
        private var statusObserver: NSKeyValueObservation?
        private var videoBoundsObserver: NSKeyValueObservation?
        private var timeObserver: Any?
        private var shouldAutoplay = true
        private weak var inlineContainerController: InlineAVPlayerContainerController?
        private var automaticFullscreenController: LandscapeAVPlayerController?
        private weak var observedVideoBoundsController: AVPlayerViewController?
        private weak var activeOverlayController: AVPlayerViewController?
        private var orientationObserver: NSObjectProtocol?
        private var isAutomaticFullscreenTransitioning = false
        private let sourceForwardBufferDuration: TimeInterval = 30
        private var danmakuHostingController: UIHostingController<PlayerDanmakuOverlayView>?
        private var gestureContainerView: PlayerGestureOverlayView?
        private var overlayConstraints: [NSLayoutConstraint] = []
        private var playbackRateBeforeFullscreen: Float = 1
        private var wasPlayingBeforeFullscreen = false
        private var isHoldingPlaybackStateForFullscreenTransition = false
        private var fullscreenPlaybackTransitionGeneration = 0
        private var isFullscreenActive = false
        private var longPressPlaybackRate: Float = 1
        private var wasPlayingBeforeLongPress = false
        private var panStartPosition: Double = 0
        private var panStartBrightness: CGFloat = 0
        private var pendingOverlayVideoBoundsUpdate: (videoBounds: CGRect, isFullscreen: Bool)?
        private var isOverlayVideoBoundsUpdateScheduled = false
        private var lastAppliedOverlayVideoBounds: CGRect = .null
        private var lastAppliedOverlayFullscreenState = false
        private lazy var volumeController = PlayerSystemVolumeController()

        init(
            playbackState: BilibiliVLCPlaybackState,
            commandCenter: BilibiliVLCCommandCenter,
            onVideoSizeChange: @escaping (CGSize) -> Void
        ) {
            self.playbackState = playbackState
            self.commandCenter = commandCenter
            self.onVideoSizeChange = onVideoSizeChange
            super.init()
            bindCommands()
            startDeviceOrientationObservation()
        }

        deinit {
            stopDeviceOrientationObservation()
            dismissAutomaticFullscreen(animated: false, restorePlayback: false, reinstallInlineOverlay: false)
            teardownPlayerController()
            removeTimeObserver()
        }

        func play(source: PlayableVideoSource) {
            guard source != currentSource else { return }
            currentSource = source
            shouldAutoplay = true
            isHoldingPlaybackStateForFullscreenTransition = false
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
            dismissAutomaticFullscreen(animated: false, restorePlayback: false, reinstallInlineOverlay: false)
            loadTask?.cancel()
            statusObserver?.invalidate()
            statusObserver = nil
            videoBoundsObserver?.invalidate()
            videoBoundsObserver = nil
            removeTimeObserver()
            player.pause()
            player.replaceCurrentItem(with: nil)
            currentSource = nil
            isHoldingPlaybackStateForFullscreenTransition = false
        }

        func configurePlayerController() {
            if playerViewController.player !== player {
                playerViewController.player = player
            }
            playerViewController.delegate = self
            playerViewController.showsPlaybackControls = true
            playerViewController.allowsPictureInPicturePlayback = true
            playerViewController.canStartPictureInPictureAutomaticallyFromInline = true
            playerViewController.entersFullScreenWhenPlaybackBegins = false
            playerViewController.exitsFullScreenWhenPlaybackEnds = true
            playerViewController.videoGravity = .resizeAspect
            playerViewController.modalPresentationStyle = .fullScreen
            playerViewController.view.backgroundColor = .black
            playerViewController.supportedOrientationMask = .portrait
            playerViewController.preferredPresentationOrientation = .portrait
        }

        private func configureFullscreenController(
            _ controller: LandscapeAVPlayerController,
            orientation: UIInterfaceOrientation,
            mask: UIInterfaceOrientationMask
        ) {
            if controller.player !== player {
                controller.player = player
            }
            controller.delegate = self
            controller.showsPlaybackControls = true
            controller.allowsPictureInPicturePlayback = true
            controller.canStartPictureInPictureAutomaticallyFromInline = true
            controller.entersFullScreenWhenPlaybackBegins = false
            controller.exitsFullScreenWhenPlaybackEnds = true
            controller.videoGravity = .resizeAspect
            controller.modalPresentationStyle = .fullScreen
            controller.modalTransitionStyle = .crossDissolve
            controller.view.backgroundColor = .black
            controller.preferredPresentationOrientation = orientation
            controller.supportedOrientationMask = mask
        }

        func attachInlineContainer(_ containerController: InlineAVPlayerContainerController) {
            inlineContainerController = containerController
            configurePlayerController()
            guard !isFullscreenActive,
                  !isAutomaticFullscreenTransitioning,
                  automaticFullscreenController?.presentingViewController == nil else {
                return
            }

            playerViewController.supportedOrientationMask = .portrait
            containerController.embed(playerViewController)
            installOverlays(in: playerViewController)
        }

        func installOverlays(in controller: AVPlayerViewController) {
            guard let contentOverlayView = controller.contentOverlayView else { return }
            activeOverlayController = controller

            if danmakuHostingController?.view.superview !== contentOverlayView {
                danmakuHostingController?.willMove(toParent: nil)
                danmakuHostingController?.view.removeFromSuperview()
                danmakuHostingController?.removeFromParent()

                let hostingController = UIHostingController(
                    rootView: PlayerDanmakuOverlayView(videoBounds: controller.videoBounds, isFullscreen: false)
                )
                hostingController.view.backgroundColor = .clear
                hostingController.view.translatesAutoresizingMaskIntoConstraints = false
                controller.addChild(hostingController)
                contentOverlayView.addSubview(hostingController.view)
                hostingController.didMove(toParent: controller)
                danmakuHostingController = hostingController
            }

            if gestureContainerView?.superview !== contentOverlayView {
                gestureContainerView?.removeFromSuperview()

                let gestureView = PlayerGestureOverlayView()
                gestureView.translatesAutoresizingMaskIntoConstraints = false
                contentOverlayView.addSubview(gestureView)
                installGestures(on: gestureView)
                volumeController.attach(to: gestureView)
                gestureContainerView = gestureView
            }

            NSLayoutConstraint.deactivate(overlayConstraints)
            overlayConstraints = [danmakuHostingController?.view, gestureContainerView].compactMap { $0 }.flatMap { overlayView in
                [
                    overlayView.topAnchor.constraint(equalTo: contentOverlayView.topAnchor),
                    overlayView.bottomAnchor.constraint(equalTo: contentOverlayView.bottomAnchor),
                    overlayView.leadingAnchor.constraint(equalTo: contentOverlayView.leadingAnchor),
                    overlayView.trailingAnchor.constraint(equalTo: contentOverlayView.trailingAnchor)
                ]
            }
            NSLayoutConstraint.activate(overlayConstraints)

            observeVideoBounds(on: controller)
            updateOverlayVideoBounds(controller.videoBounds, isFullscreen: isFullscreenActive)
        }

        func teardownPlayerController() {
            videoBoundsObserver?.invalidate()
            videoBoundsObserver = nil
            inlineContainerController = nil
            observedVideoBoundsController = nil
            activeOverlayController = nil
            automaticFullscreenController?.delegate = nil
            automaticFullscreenController?.player = nil
            automaticFullscreenController = nil
            if let parent = playerViewController.parent as? InlineAVPlayerContainerController {
                parent.detach(playerViewController)
            } else {
                playerViewController.view.removeFromSuperview()
                playerViewController.removeFromParent()
            }
            NSLayoutConstraint.deactivate(overlayConstraints)
            overlayConstraints = []
            volumeController.detach()
            gestureContainerView?.removeFromSuperview()
            gestureContainerView = nil
            danmakuHostingController?.willMove(toParent: nil)
            danmakuHostingController?.view.removeFromSuperview()
            danmakuHostingController?.removeFromParent()
            danmakuHostingController = nil
            pendingOverlayVideoBoundsUpdate = nil
            isOverlayVideoBoundsUpdateScheduled = false
            lastAppliedOverlayVideoBounds = .null
            lastAppliedOverlayFullscreenState = false
        }

        private func bindCommands() {
            commandCenter?.togglePlayHandler = { [weak self] in
                guard let self else { return }
                if self.player.timeControlStatus == .playing {
                    self.isHoldingPlaybackStateForFullscreenTransition = false
                    self.player.pause()
                    self.shouldAutoplay = false
                } else {
                    self.shouldAutoplay = true
                    self.player.playImmediately(atRate: max(self.playbackRateBeforeFullscreen, 1))
                }
                self.updatePlaybackState()
            }

            commandCenter?.playHandler = { [weak self] in
                guard let self else { return }
                self.shouldAutoplay = true
                self.player.playImmediately(atRate: max(self.playbackRateBeforeFullscreen, 1))
                self.updatePlaybackState()
            }

            commandCenter?.pauseHandler = { [weak self] in
                guard let self else { return }
                self.isHoldingPlaybackStateForFullscreenTransition = false
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

        private func startDeviceOrientationObservation() {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            orientationObserver = NotificationCenter.default.addObserver(
                forName: UIDevice.orientationDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.handleDeviceOrientationChange(UIDevice.current.orientation)
            }
        }

        private func stopDeviceOrientationObservation() {
            if let orientationObserver {
                NotificationCenter.default.removeObserver(orientationObserver)
                self.orientationObserver = nil
            }
        }

        private func handleDeviceOrientationChange(_ orientation: UIDeviceOrientation) {
            switch orientation {
            case .landscapeLeft, .landscapeRight:
                presentAutomaticFullscreen(preferredOrientation: orientation)
            case .portrait, .portraitUpsideDown:
                dismissAutomaticFullscreen(animated: true, restorePlayback: true)
            default:
                break
            }
        }

        private func presentAutomaticFullscreen(preferredOrientation: UIDeviceOrientation) {
            let interfaceOrientation = interfaceOrientation(for: preferredOrientation)
            let orientationMask = interfaceOrientationMask(for: interfaceOrientation)

            if isFullscreenActive {
                if let automaticFullscreenController {
                    automaticFullscreenController.preferredPresentationOrientation = interfaceOrientation
                    automaticFullscreenController.supportedOrientationMask = orientationMask
                    automaticFullscreenController.setNeedsUpdateOfSupportedInterfaceOrientations()
                }
                AppOrientationController.lock(
                    orientationMask,
                    scene: automaticFullscreenController?.view.window?.windowScene ?? playerViewController.view.window?.windowScene
                )
                return
            }

            guard !isAutomaticFullscreenTransitioning,
                  let inlineContainerController,
                  inlineContainerController.view.window != nil,
                  let scene = inlineContainerController.view.window?.windowScene,
                  let presenter = (inlineContainerController.view.window?.rootViewController ?? inlineContainerController.view.nearestViewController)?.topPresentedViewController,
                  presenter.presentedViewController == nil else {
                return
            }

            capturePlaybackBeforeFullscreenTransition()
            isAutomaticFullscreenTransitioning = true
            isFullscreenActive = true

            let fullscreenController = LandscapeAVPlayerController()
            configureFullscreenController(
                fullscreenController,
                orientation: interfaceOrientation,
                mask: orientationMask
            )
            fullscreenController.onDismiss = { [weak self] dismissedController in
                self?.handleAutomaticFullscreenDismissed(dismissedController)
            }
            automaticFullscreenController = fullscreenController
            keepPlaybackRunningDuringFullscreenTransition()

            AppOrientationController.lockForPlayerFullscreen(orientationMask, scene: scene) { [weak self, weak fullscreenController, weak presenter] in
                guard let self else { return }
                guard let fullscreenController,
                      let presenter,
                      presenter.presentedViewController == nil,
                      self.automaticFullscreenController === fullscreenController,
                      self.isAutomaticFullscreenTransitioning else {
                    self.finishAutomaticFullscreenDismiss(restorePlayback: true, reinstallInlineOverlay: true)
                    return
                }

                self.presentAutomaticFullscreenWhenSceneIsReady(
                    fullscreenController,
                    presenter: presenter,
                    scene: scene,
                    orientationMask: orientationMask
                )
            }
        }

        private func presentAutomaticFullscreenWhenSceneIsReady(
            _ fullscreenController: LandscapeAVPlayerController,
            presenter: UIViewController,
            scene: UIWindowScene,
            orientationMask: UIInterfaceOrientationMask,
            attempt: Int = 0
        ) {
            guard presenter.presentedViewController == nil,
                  automaticFullscreenController === fullscreenController,
                  isAutomaticFullscreenTransitioning else {
                finishAutomaticFullscreenDismiss(restorePlayback: true, reinstallInlineOverlay: true)
                return
            }

            guard isSceneReadyForFullscreenPresentation(scene, orientationMask: orientationMask) else {
                guard attempt < 15 else {
                    finishAutomaticFullscreenDismiss(restorePlayback: true, reinstallInlineOverlay: true)
                    return
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self, weak fullscreenController, weak presenter] in
                    guard let self, let fullscreenController, let presenter else { return }
                    self.presentAutomaticFullscreenWhenSceneIsReady(
                        fullscreenController,
                        presenter: presenter,
                        scene: scene,
                        orientationMask: orientationMask,
                        attempt: attempt + 1
                    )
                }
                return
            }

            if playerViewController.player === player {
                playerViewController.player = nil
            }
            presenter.present(fullscreenController, animated: true) { [weak self, weak fullscreenController] in
                guard let self else { return }
                guard let fullscreenController,
                      fullscreenController.presentingViewController != nil else {
                    self.finishAutomaticFullscreenDismiss(restorePlayback: true, reinstallInlineOverlay: true)
                    return
                }
                self.isAutomaticFullscreenTransitioning = false
                fullscreenController.setNeedsUpdateOfSupportedInterfaceOrientations()
                self.installOverlays(in: fullscreenController)
                self.restorePlaybackAfterFullscreenTransition()
            }
        }

        private func dismissAutomaticFullscreen(
            animated: Bool,
            restorePlayback: Bool,
            reinstallInlineOverlay: Bool = true
        ) {
            guard !isAutomaticFullscreenTransitioning,
                  isFullscreenActive || automaticFullscreenController?.presentingViewController != nil else {
                return
            }

            if restorePlayback {
                capturePlaybackBeforeFullscreenTransition()
            }
            isAutomaticFullscreenTransitioning = true
            automaticFullscreenController?.onDismiss = nil
            keepPlaybackRunningDuringFullscreenTransition()

            guard let fullscreenController = automaticFullscreenController else {
                finishAutomaticFullscreenDismiss(
                    restorePlayback: restorePlayback,
                    reinstallInlineOverlay: reinstallInlineOverlay
                )
                return
            }

            guard fullscreenController.presentingViewController != nil else {
                finishAutomaticFullscreenDismiss(
                    restorePlayback: restorePlayback,
                    reinstallInlineOverlay: reinstallInlineOverlay
                )
                return
            }

            fullscreenController.dismiss(animated: animated) { [weak self] in
                guard let self else { return }
                self.finishAutomaticFullscreenDismiss(
                    restorePlayback: restorePlayback,
                    reinstallInlineOverlay: reinstallInlineOverlay
                )
            }
        }

        private func handleAutomaticFullscreenDismissed(_ controller: LandscapeAVPlayerController) {
            guard automaticFullscreenController === controller,
                  !isAutomaticFullscreenTransitioning else {
                return
            }

            finishAutomaticFullscreenDismiss(restorePlayback: true, reinstallInlineOverlay: true)
        }

        private func finishAutomaticFullscreenDismiss(restorePlayback: Bool, reinstallInlineOverlay: Bool) {
            isAutomaticFullscreenTransitioning = false
            isFullscreenActive = false
            automaticFullscreenController?.onDismiss = nil
            automaticFullscreenController?.delegate = nil
            automaticFullscreenController?.player = nil
            automaticFullscreenController = nil
            configurePlayerController()
            playerViewController.supportedOrientationMask = .portrait
            playerViewController.setNeedsUpdateOfSupportedInterfaceOrientations()

            if reinstallInlineOverlay, let inlineContainerController {
                if playerViewController.parent !== inlineContainerController {
                    attachInlineContainer(inlineContainerController)
                } else {
                    installOverlays(in: playerViewController)
                }
                AppOrientationController.endPlayerFullscreen(scene: inlineContainerController.view.window?.windowScene)
            } else {
                AppOrientationController.endPlayerFullscreen()
            }

            if restorePlayback {
                restorePlaybackAfterFullscreenTransition()
            }
        }

        private func capturePlaybackBeforeFullscreenTransition() {
            if player.rate > 0 {
                playbackRateBeforeFullscreen = player.rate
            }
            wasPlayingBeforeFullscreen = shouldAutoplay
                || player.rate > 0
                || player.timeControlStatus == .playing
                || player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            isHoldingPlaybackStateForFullscreenTransition = wasPlayingBeforeFullscreen
            fullscreenPlaybackTransitionGeneration += 1
        }

        private func keepPlaybackRunningDuringFullscreenTransition() {
            guard wasPlayingBeforeFullscreen else {
                updatePlaybackState()
                return
            }

            shouldAutoplay = true
            let targetRate = max(playbackRateBeforeFullscreen, 1)
            if player.currentItem?.status == .readyToPlay {
                player.playImmediately(atRate: targetRate)
            } else {
                player.play()
            }
            updatePlaybackState()
        }

        private func releasePlaybackStateHoldAfterFullscreenTransition() {
            let generation = fullscreenPlaybackTransitionGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self, self.fullscreenPlaybackTransitionGeneration == generation else { return }
                self.isHoldingPlaybackStateForFullscreenTransition = false
                self.updatePlaybackState()
            }
        }

        private func interfaceOrientation(for deviceOrientation: UIDeviceOrientation) -> UIInterfaceOrientation {
            deviceOrientation == .landscapeRight ? .landscapeLeft : .landscapeRight
        }

        private func interfaceOrientationMask(for interfaceOrientation: UIInterfaceOrientation) -> UIInterfaceOrientationMask {
            interfaceOrientation == .landscapeLeft ? .landscapeLeft : .landscapeRight
        }

        private func isSceneReadyForFullscreenPresentation(
            _ scene: UIWindowScene,
            orientationMask: UIInterfaceOrientationMask
        ) -> Bool {
            if orientationMask.contains(.landscapeLeft), scene.interfaceOrientation == .landscapeLeft {
                return true
            }
            if orientationMask.contains(.landscapeRight), scene.interfaceOrientation == .landscapeRight {
                return true
            }
            return false
        }

        private func currentLandscapeOrientation() -> UIInterfaceOrientation {
            let deviceOrientation = UIDevice.current.orientation
            if deviceOrientation == .landscapeLeft || deviceOrientation == .landscapeRight {
                return interfaceOrientation(for: deviceOrientation)
            }

            let windowScene = playerViewController.view.window?.windowScene
                ?? inlineContainerController?.view.window?.windowScene
            let interfaceOrientation = windowScene?.interfaceOrientation
            if interfaceOrientation == .landscapeLeft || interfaceOrientation == .landscapeRight {
                return interfaceOrientation ?? .landscapeRight
            }

            return .landscapeRight
        }

        private func installGestures(on view: PlayerGestureOverlayView) {
            view.gestureRecognizers?.forEach(view.removeGestureRecognizer)
            view.backgroundColor = .clear

            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            doubleTap.numberOfTapsRequired = 2
            doubleTap.cancelsTouchesInView = false
            doubleTap.delegate = self
            view.addGestureRecognizer(doubleTap)

            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            longPress.minimumPressDuration = 0.35
            longPress.cancelsTouchesInView = false
            longPress.delegate = self
            view.addGestureRecognizer(longPress)

            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.maximumNumberOfTouches = 1
            pan.cancelsTouchesInView = false
            pan.delegate = self
            view.addGestureRecognizer(pan)
        }

        @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            commandCenter?.togglePlay()
        }

        @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            switch gesture.state {
            case .began:
                wasPlayingBeforeLongPress = player.rate > 0 || player.timeControlStatus == .playing
                longPressPlaybackRate = player.rate > 0 ? player.rate : 1
                player.rate = 2
            case .ended, .cancelled, .failed:
                if wasPlayingBeforeLongPress {
                    player.rate = longPressPlaybackRate
                } else {
                    player.pause()
                }
            default:
                break
            }
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let targetView = gesture.view,
                  let item = player.currentItem else { return }

            let location = gesture.location(in: targetView)
            let translation = gesture.translation(in: targetView)

            switch gesture.state {
            case .began:
                panStartPosition = playbackState?.position ?? 0
                panStartBrightness = UIScreen.main.brightness
            case .changed:
                if abs(translation.x) > abs(translation.y) {
                    let delta = translation.x / max(targetView.bounds.width, 1)
                    playbackState?.pendingSeekPosition = min(max(panStartPosition + delta, 0), 1)
                    updatePlaybackState()
                } else if location.x < targetView.bounds.midX {
                    let brightness = panStartBrightness - translation.y / max(targetView.bounds.height, 1)
                    UIScreen.main.brightness = min(max(brightness, 0), 1)
                } else {
                    volumeController.changeVolume(by: Float(-translation.y / max(targetView.bounds.height, 1)))
                    gesture.setTranslation(.zero, in: targetView)
                }
            case .ended, .cancelled:
                guard let pendingSeekPosition = playbackState?.pendingSeekPosition else { return }
                let duration = item.duration
                guard duration.isValid, duration.isNumeric, duration.seconds > 0 else { return }
                let target = CMTime(seconds: duration.seconds * min(max(pendingSeekPosition, 0), 1), preferredTimescale: 600)
                let shouldResume = player.timeControlStatus == .playing
                player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                    guard let self else { return }
                    self.playbackState?.pendingSeekPosition = nil
                    if shouldResume {
                        self.player.play()
                    }
                    self.updatePlaybackState()
                }
            default:
                break
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            willBeginFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator
        ) {
            capturePlaybackBeforeFullscreenTransition()
            isFullscreenActive = true
            let interfaceOrientation = currentLandscapeOrientation()
            let orientationMask = interfaceOrientationMask(for: interfaceOrientation)
            if let playerViewController = playerViewController as? LandscapeAVPlayerController {
                playerViewController.supportedOrientationMask = orientationMask
                playerViewController.preferredPresentationOrientation = interfaceOrientation
                playerViewController.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            AppOrientationController.beginPlayerFullscreen(
                orientationMask,
                scene: playerViewController.view.window?.windowScene,
                requestGeometryUpdate: true
            )
            keepPlaybackRunningDuringFullscreenTransition()
            coordinator.animate { [weak self, weak playerViewController] _ in
                guard let self, let playerViewController else { return }
                self.updateOverlayVideoBounds(playerViewController.videoBounds, isFullscreen: true)
            } completion: { [weak self, weak playerViewController] _ in
                guard let self, let playerViewController else { return }
                self.restorePlaybackAfterFullscreenTransition()
                self.updateOverlayVideoBounds(playerViewController.videoBounds, isFullscreen: true)
            }
        }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator
        ) {
            capturePlaybackBeforeFullscreenTransition()
            keepPlaybackRunningDuringFullscreenTransition()
            coordinator.animate { [weak self, weak playerViewController] _ in
                guard let self, let playerViewController else { return }
                self.updateOverlayVideoBounds(playerViewController.videoBounds, isFullscreen: false)
            } completion: { [weak self, weak playerViewController] _ in
                guard let self, let playerViewController else { return }
                self.isFullscreenActive = false
                if let playerViewController = playerViewController as? LandscapeAVPlayerController {
                    playerViewController.supportedOrientationMask = .portrait
                }
                AppOrientationController.endPlayerFullscreen(scene: playerViewController.view.window?.windowScene)
                self.restorePlaybackAfterFullscreenTransition()
                if self.automaticFullscreenController === playerViewController {
                    self.automaticFullscreenController?.delegate = nil
                    self.automaticFullscreenController?.player = nil
                    self.automaticFullscreenController = nil
                    if let inlineContainerController = self.inlineContainerController {
                        self.installOverlays(in: self.playerViewController)
                        AppOrientationController.endPlayerFullscreen(scene: inlineContainerController.view.window?.windowScene)
                    }
                } else if let inlineContainerController = self.inlineContainerController {
                    self.attachInlineContainer(inlineContainerController)
                } else {
                    self.updateOverlayVideoBounds(playerViewController.videoBounds, isFullscreen: false)
                }
            }
        }

        private func restorePlaybackAfterFullscreenTransition() {
            if wasPlayingBeforeFullscreen {
                shouldAutoplay = true
                player.playImmediately(atRate: max(playbackRateBeforeFullscreen, 1))
                releasePlaybackStateHoldAfterFullscreenTransition()
            } else {
                isHoldingPlaybackStateForFullscreenTransition = false
                updatePlaybackState()
            }
        }

        private func observeVideoBounds(on controller: AVPlayerViewController) {
            guard videoBoundsObserver == nil || observedVideoBoundsController !== controller else { return }
            videoBoundsObserver?.invalidate()
            observedVideoBoundsController = controller
            videoBoundsObserver = controller.observe(\.videoBounds, options: [.initial, .new]) { [weak self] controller, _ in
                let videoBounds = controller.videoBounds
                DispatchQueue.main.async { [weak self] in
                    self?.scheduleOverlayVideoBoundsUpdate(
                        videoBounds,
                        isFullscreen: self?.isFullscreenActive == true
                    )
                }
            }
        }

        private func scheduleOverlayVideoBoundsUpdate(_ videoBounds: CGRect, isFullscreen: Bool) {
            pendingOverlayVideoBoundsUpdate = (videoBounds, isFullscreen)
            guard !isOverlayVideoBoundsUpdateScheduled else { return }

            isOverlayVideoBoundsUpdateScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isOverlayVideoBoundsUpdateScheduled = false
                guard let update = self.pendingOverlayVideoBoundsUpdate else { return }
                self.pendingOverlayVideoBoundsUpdate = nil
                self.updateOverlayVideoBounds(update.videoBounds, isFullscreen: update.isFullscreen)
            }
        }

        private func updateOverlayVideoBounds(_ videoBounds: CGRect, isFullscreen: Bool) {
            let controller = activeOverlayController ?? automaticFullscreenController ?? playerViewController
            guard let contentOverlayView = controller.contentOverlayView else { return }
            let convertedBounds: CGRect
            if videoBounds == .zero {
                convertedBounds = contentOverlayView.bounds
            } else {
                convertedBounds = contentOverlayView.convert(videoBounds, from: controller.view)
            }

            guard !convertedBounds.isApproximatelyEqual(to: lastAppliedOverlayVideoBounds)
                    || isFullscreen != lastAppliedOverlayFullscreenState else {
                return
            }

            lastAppliedOverlayVideoBounds = convertedBounds
            lastAppliedOverlayFullscreenState = isFullscreen
            danmakuHostingController?.rootView = PlayerDanmakuOverlayView(
                videoBounds: convertedBounds,
                isFullscreen: isFullscreen
            )
            gestureContainerView?.videoBounds = convertedBounds
        }

        private func loadAndPlay(source: PlayableVideoSource) async {
            configureAudioSession()

            if source.isDASHSeparated {
                do {
                    HLSPlaybackDiagnostics.shared.reset()
                    let manifestURL = try await DashHLSManifestService().makeManifest(for: source)
                    let asset = AVURLAsset(url: manifestURL, options: assetOptions(headers: source.headers))
                    await prewarmAsset(asset)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        let item = AVPlayerItem(asset: asset)
                        self.configureFastStart(item)
                        self.observe(item: item)
                        self.player.replaceCurrentItem(with: item)
                        self.addTimeObserver()
                        self.updatePlaybackState()
                        self.playWhenReady(item: item)
                    }
                    return
                } catch {
                    print("DASH to HLS load failed: \(error.localizedDescription)")
                }
            }

            guard let audioURL = source.audioURL else {
                await loadSingleURL(source: source)
                return
            }

            do {
                let item = try await makePlayerItem(videoURL: source.url, audioURL: audioURL, headers: source.headers)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.configureFastStart(item)
                    self.observe(item: item)
                    self.player.replaceCurrentItem(with: item)
                    self.addTimeObserver()
                    self.updatePlaybackState()
                    self.playWhenReady(item: item)
                }
            } catch {
                print("AVFoundation DASH load failed: \(error.localizedDescription)")
            }
        }

        private func loadSingleURL(source: PlayableVideoSource) async {
            let asset = AVURLAsset(url: source.url, options: assetOptions(headers: source.headers))
            let item = AVPlayerItem(asset: asset)

            await MainActor.run {
                self.configureFastStart(item)
                self.observe(item: item)
                self.player.replaceCurrentItem(with: item)
                self.addTimeObserver()
                self.updatePlaybackState()
                self.playWhenReady(item: item)
            }
        }

        private func observe(item: AVPlayerItem) {
            statusObserver?.invalidate()
            statusObserver = item.observe(\.status, options: [.new]) { item, _ in
                switch item.status {
                case .readyToPlay:
                    HLSPlaybackDiagnostics.shared.recordPlayerStatus("ready")
                    self.updateVideoSize(for: item)
                    if self.shouldAutoplay {
                        self.player.playImmediately(atRate: 1)
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

        private func updateVideoSize(for item: AVPlayerItem) {
            guard let videoTrack = item.tracks
                .compactMap({ $0.assetTrack })
                .first(where: { $0.mediaType == .video }) else {
                return
            }

            let transformedSize = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
            let videoSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))

            guard videoSize.width > 0, videoSize.height > 0 else {
                return
            }

            DispatchQueue.main.async {
                self.onVideoSizeChange(videoSize)
            }
        }

        private func playWhenReady(item: AVPlayerItem) {
            shouldAutoplay = true
            if item.status == .readyToPlay {
                player.playImmediately(atRate: 1)
            } else {
                player.play()
            }
            if item.status != .readyToPlay {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self, weak item] in
                    guard let self, self.shouldAutoplay, item === self.player.currentItem else { return }
                    self.player.playImmediately(atRate: 1)
                    self.updatePlaybackState()
                }
            }
        }

        private func configureFastStart(_ item: AVPlayerItem) {
            item.preferredForwardBufferDuration = sourceForwardBufferDuration
            item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
            player.automaticallyWaitsToMinimizeStalling = false
        }

        private func prewarmAsset(_ asset: AVURLAsset) async {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    await withCheckedContinuation { continuation in
                        asset.loadValuesAsynchronously(forKeys: ["playable"]) {
                            continuation.resume()
                        }
                    }
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                }
                await group.next()
                group.cancelAll()
            }
        }

        private func addTimeObserver() {
            removeTimeObserver()
            timeObserver = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
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
            let isPlaying = effectiveIsPlaying
            let applyUpdate = {
                guard duration.isValid, duration.isNumeric, duration.seconds > 0 else {
                    playbackState.updatePlayback(
                        position: nil,
                        elapsedText: Self.timeText(current.seconds),
                        durationText: "00:00",
                        isPlaying: isPlaying
                    )
                    return
                }
                let position: Double?
                if let pendingSeekPosition = playbackState.pendingSeekPosition {
                    position = pendingSeekPosition
                } else if !playbackState.isScrubbing {
                    position = min(max(current.seconds / duration.seconds, 0), 1)
                } else {
                    position = nil
                }
                playbackState.updatePlayback(
                    position: position,
                    elapsedText: Self.timeText(current.seconds),
                    durationText: Self.timeText(duration.seconds),
                    isPlaying: isPlaying
                )
            }
            if Thread.isMainThread {
                applyUpdate()
            } else {
                DispatchQueue.main.async(execute: applyUpdate)
            }
        }

        private var effectiveIsPlaying: Bool {
            if isHoldingPlaybackStateForFullscreenTransition, wasPlayingBeforeFullscreen {
                return true
            }

            return player.rate > 0
                || player.timeControlStatus == .playing
                || (shouldAutoplay && player.timeControlStatus == .waitingToPlayAtSpecifiedRate)
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
            item.preferredForwardBufferDuration = sourceForwardBufferDuration
            return item
        }

        private func assetOptions(headers: [String: String]) -> [String: Any] {
            var enrichedHeaders = headers
            if let cookieHeader = BilibiliCookieStore.cookieHeader() {
                enrichedHeaders["Cookie"] = cookieHeader
            }
            enrichedHeaders["Accept"] = "*/*"
            enrichedHeaders["Connection"] = "keep-alive"
            enrichedHeaders["Accept-Encoding"] = "identity"
            return ["AVURLAssetHTTPHeaderFieldsKey": enrichedHeaders]
        }
    }
}

final class InlineAVPlayerContainerController: UIViewController {
    private var hostedConstraints: [NSLayoutConstraint] = []

    func embed(_ playerViewController: AVPlayerViewController) {
        guard playerViewController.parent !== self else {
            view.setNeedsLayout()
            return
        }

        detach(playerViewController)
        addChild(playerViewController)
        playerViewController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(playerViewController.view)
        hostedConstraints = [
            playerViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            playerViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            playerViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ]
        NSLayoutConstraint.activate(hostedConstraints)
        playerViewController.didMove(toParent: self)
    }

    func detach(_ playerViewController: AVPlayerViewController) {
        NSLayoutConstraint.deactivate(hostedConstraints)
        hostedConstraints = []

        guard playerViewController.parent != nil else {
            playerViewController.view.removeFromSuperview()
            return
        }

        playerViewController.willMove(toParent: nil)
        playerViewController.view.removeFromSuperview()
        playerViewController.removeFromParent()
    }
}

final class LandscapeAVPlayerController: AVPlayerViewController {
    var preferredPresentationOrientation: UIInterfaceOrientation = .landscapeLeft
    var supportedOrientationMask: UIInterfaceOrientationMask = [.portrait, .landscapeLeft, .landscapeRight]
    var onDismiss: ((LandscapeAVPlayerController) -> Void)?

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        supportedOrientationMask
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        preferredPresentationOrientation
    }

    override var shouldAutorotate: Bool {
        true
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || navigationController?.isBeingDismissed == true {
            onDismiss?(self)
        }
    }
}

private extension UIViewController {
    var topPresentedViewController: UIViewController {
        var controller = self
        while let presentedController = controller.presentedViewController,
              !presentedController.isBeingDismissed {
            controller = presentedController
        }
        return controller
    }
}

private struct PlayerDanmakuOverlayView: View {
    let videoBounds: CGRect
    let isFullscreen: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.clear

                Color.clear
                    .frame(
                        width: max(videoBounds.width, 0),
                        height: max(videoBounds.height, 0)
                    )
                    .position(
                        x: min(max(videoBounds.midX, 0), proxy.size.width),
                        y: min(max(videoBounds.midY, 0), proxy.size.height)
                    )
            }
            .allowsHitTesting(false)
        }
    }
}

private final class PlayerGestureOverlayView: UIView {
    var videoBounds: CGRect = .zero

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard videoBounds != .zero else {
            return false
        }
        return videoBounds.contains(point)
    }
}

private final class PlayerSystemVolumeController {
    private let volumeView = MPVolumeView(frame: .zero)
    private weak var volumeSlider: UISlider?
    private var currentVolume: Float {
        AVAudioSession.sharedInstance().outputVolume
    }

    init() {
        volumeView.alpha = 0.01
        volumeView.isUserInteractionEnabled = false
        volumeSlider = volumeView.subviews.compactMap { $0 as? UISlider }.first
    }

    func attach(to view: UIView) {
        guard volumeView.superview !== view else { return }
        volumeView.removeFromSuperview()
        volumeView.frame = CGRect(x: -100, y: -100, width: 1, height: 1)
        view.addSubview(volumeView)
        volumeSlider = volumeView.subviews.compactMap { $0 as? UISlider }.first
    }

    func detach() {
        volumeView.removeFromSuperview()
    }

    func changeVolume(by delta: Float) {
        let targetVolume = min(max(currentVolume + delta, 0), 1)
        volumeSlider?.setValue(targetVolume, animated: false)
        volumeSlider?.sendActions(for: .valueChanged)
    }
}

private extension CGRect {
    func isApproximatelyEqual(to other: CGRect, tolerance: CGFloat = 0.5) -> Bool {
        guard isNull == other.isNull else {
            return false
        }

        if isNull {
            return true
        }

        return abs(origin.x - other.origin.x) <= tolerance
            && abs(origin.y - other.origin.y) <= tolerance
            && abs(size.width - other.size.width) <= tolerance
            && abs(size.height - other.size.height) <= tolerance
    }
}

enum AVFoundationDASHError: Error {
    case missingVideoTrack
    case missingAudioTrack
    case cannotCreateCompositionTrack
}

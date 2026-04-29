//
//  BilibiliVLCPlayerView.swift
//  ccbili
//
//  Created by chuzu  on 2026/4/26.
//

import SwiftUI
import UIKit
import AVFoundation
import Combine



struct BilibiliVLCPlayerView: View {
    @Environment(\.scenePhase) private var scenePhase

    let source: PlayableVideoSource
    private let enablesAutoFullscreen: Bool
    private let initialPosition: Double?
    private let onPositionChange: (Double) -> Void
    private let onPlaybackStateChange: (Bool) -> Void
    private let onFullscreenRequest: (() -> Void)?

    @StateObject private var playbackState = BilibiliVLCPlaybackState()
    @StateObject private var commandCenter = BilibiliVLCCommandCenter()
    @AppStorage(AppSettings.playbackDiagnosticsEnabledKey) private var isPlaybackDiagnosticsEnabled = false

    @State private var currentSource: PlayableVideoSource
    @State private var areControlsVisible = true
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var isSwitchingQuality = false
    @State private var qualityErrorMessage: String?
    @State private var isFullscreenPresented = false
    @State private var fullscreenOrientation: UIDeviceOrientation = .portrait
    @State private var pendingSeekPosition: Double?
    @State private var surfaceID = UUID()
    @State private var hlsDiagnosticsText = HLSPlaybackDiagnostics.shared.summary
    @State private var didReceiveFirstProgress = false
    @State private var seekResumePlayback = false
    @State private var hasAppeared = false
    @State private var shouldResumeAfterVisibilityReturn = false
    @State private var isPlayerLayerDetachedForFullscreen = false
    private let diagnosticsTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(
        source: PlayableVideoSource,
        enablesAutoFullscreen: Bool = true,
        initialPosition: Double? = nil,
        onPositionChange: @escaping (Double) -> Void = { _ in },
        onPlaybackStateChange: @escaping (Bool) -> Void = { _ in },
        onFullscreenRequest: (() -> Void)? = nil
    ) {
        self.source = source
        self.enablesAutoFullscreen = enablesAutoFullscreen
        self.initialPosition = initialPosition
        self.onPositionChange = onPositionChange
        self.onPlaybackStateChange = onPlaybackStateChange
        self.onFullscreenRequest = onFullscreenRequest
        _currentSource = State(initialValue: source)
        _pendingSeekPosition = State(initialValue: initialPosition)
    }

    var body: some View {
        playerSurface
            .background(.black)
            .clipped()
            .statusBarHidden(isFullscreenPresented)
            .animation(.easeInOut(duration: 0.25), value: isFullscreenPresented)
            .background(
                Group {
                    if enablesAutoFullscreen {
                        FullscreenPlayerWindowPresenter(
                            isPresented: isFullscreenPresented,
                            orientation: fullscreenOrientation,
                            playbackState: playbackState,
                            commandCenter: commandCenter,
                            debugText: isPlaybackDiagnosticsEnabled ? currentSource.debugDescription.map(debugText(base:)) : nil,
                            onLayerDetachedChange: { isDetached in
                                isPlayerLayerDetachedForFullscreen = isDetached
                            },
                            onDismiss: {
                                isFullscreenPresented = false
                            }
                        )
                        .frame(width: 0, height: 0)
                    }
                }
            )
        .onAppear {
            showControlsTemporarily()
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            schedulePendingSeekIfNeeded()
            if hasAppeared {
                resumeAfterVisibilityReturn()
            }
            hasAppeared = true
        }
        .onReceive(playbackState.$position) { position in
            onPositionChange(position)
            if position > 0 || playbackState.isPlaying {
                didReceiveFirstProgress = true
            }
        }
        .onReceive(playbackState.$isPlaying) { isPlaying in
            onPlaybackStateChange(isPlaying)
        }
        .onChange(of: source) { _, newValue in
            currentSource = newValue
            surfaceID = UUID()
            showControlsTemporarily()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            guard enablesAutoFullscreen else {
                return
            }

            let orientation = UIDevice.current.orientation

            if orientation == .landscapeLeft || orientation == .landscapeRight {
                fullscreenOrientation = orientation
                isFullscreenPresented = true
            } else if orientation == .portrait || orientation == .portraitUpsideDown {
                isFullscreenPresented = false
            }
        }
        .onReceive(diagnosticsTimer) { _ in
            hlsDiagnosticsText = HLSPlaybackDiagnostics.shared.summary
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                resumeAfterVisibilityReturn()
            case .inactive, .background:
                pauseForVisibilityLoss()
            @unknown default:
                break
            }
        }
        .onDisappear {
            hideControlsTask?.cancel()
            pauseForVisibilityLoss()
        }
    }

    private var playerSurface: some View {
        ZStack {
            if isPlayerLayerDetachedForFullscreen {
                Color.black
            } else {
                videoSurface
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if shouldUseCustomControls {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        commandCenter.togglePlay()
                        showControlsTemporarily()
                    }
                    .onTapGesture(count: 1) {
                        toggleControlsVisibility()
                    }

                playerOverlays
                    .opacity(isFullscreenPresented ? 0 : 1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var videoSurface: some View {
        Group {
            if shouldUseNativePlayer {
                AVFoundationDASHPlayerView(
                    source: currentSource,
                    playbackState: playbackState,
                    commandCenter: commandCenter
                )
            } else {
                BilibiliVLCVideoSurface(
                    source: currentSource,
                    playbackState: playbackState,
                    commandCenter: commandCenter,
                    isFullscreen: isFullscreenPresented,
                    fullscreenOrientation: fullscreenOrientation
                )
            }
        }
            .id(surfaceID)
            .background(.black)
            .onChange(of: currentSource) { _, _ in
                didReceiveFirstProgress = false
            }
    }

    @ViewBuilder
    private var playerOverlays: some View {
        if areControlsVisible {
            controlsOverlay
                .transition(.opacity)
        }

        if isSwitchingQuality {
            ProgressView()
                .tint(.white)
                .padding(14)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }

        if !didReceiveFirstProgress && !isSwitchingQuality {
            VStack(spacing: 8) {
                ProgressView()
                    .tint(.white)
                Text("正在加载视频")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .transition(.opacity)
        }
    }

    private var controlsOverlay: some View {
        ZStack {
            VStack(spacing: 0) {
                topControls

                if isPlaybackDiagnosticsEnabled, let debugDescription = currentSource.debugDescription {
                    debugOverlay(debugText(base: debugDescription))
                }

                Spacer()

                bottomProgressControls
            }
        }
        .allowsHitTesting(true)
    }

    private var topControls: some View {
        HStack(spacing: 10) {
            Button {
                commandCenter.togglePlay()
                showControlsTemporarily()
            } label: {
                Image(systemName: playbackState.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)

            if let qualityErrorMessage {
                Text(qualityErrorMessage)
                    .font(.caption2)
                    .foregroundStyle(.red.opacity(0.95))
                    .lineLimit(1)
            }

            Spacer()

            qualityMenu

            if !currentSource.isDASHSeparated, let onFullscreenRequest {
                Button {
                    onFullscreenRequest()
                    showControlsTemporarily()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }

    private func debugOverlay(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.yellow.opacity(0.95))
            .lineLimit(8)
            .minimumScaleFactor(0.65)
            .multilineTextAlignment(.leading)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.top, 6)
    }

    private var shouldUseNativePlayer: Bool {
        currentSource.isDASHSeparated || (currentSource.quality ?? 0) <= 80
    }

    private var shouldUseCustomControls: Bool {
        !shouldUseNativePlayer
    }

    private func debugText(base: String) -> String {
        guard base.contains("DASH-to-HLS") else { return base }
        return "\(base)\n\(hlsDiagnosticsText)"
    }

    private var qualityMenu: some View {
        Menu {
            let qualities = currentSource.availableQualities.isEmpty
                ? fallbackQualities
                : currentSource.availableQualities

            ForEach(qualities) { option in
                Button {
                    Task {
                        await switchQuality(to: option)
                    }
                } label: {
                    if option.quality == currentSource.quality {
                        Label(option.description, systemImage: "checkmark")
                    } else {
                        Text(option.description)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(currentSource.qualityDescription ?? "Quality")
                    .font(.caption.weight(.semibold))

                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isSwitchingQuality)
        .simultaneousGesture(
            TapGesture().onEnded {
                showControlsTemporarily()
            }
        )
    }

    private var bottomProgressControls: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text(playbackState.elapsedText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 44, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { playbackState.position },
                        set: { newValue in
                            playbackState.position = newValue
                        }
                    ),
                    in: 0...1,
                    onEditingChanged: { isEditing in
                        playbackState.isScrubbing = isEditing
                        showControlsTemporarily()

                        if isEditing {
                            seekResumePlayback = playbackState.isPlaying
                        }

                        if !isEditing {
                            let targetPosition = playbackState.position
                            playbackState.pendingSeekPosition = targetPosition
                            commandCenter.seek(to: targetPosition, resumePlayback: seekResumePlayback)
                            showControlsTemporarily()
                        }
                    }
                )
                .tint(.white)

                Text(playbackState.durationText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 44, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

    private var fallbackQualities: [VideoQualityOption] {
        [
            VideoQualityOption(quality: 112, description: "1080P+"),
            VideoQualityOption(quality: 32, description: "480P"),
            VideoQualityOption(quality: 64, description: "720P"),
            VideoQualityOption(quality: 80, description: "1080P")
        ]
    }

    private func toggleControlsVisibility() {
        if areControlsVisible {
            hideControls()
        } else {
            showControlsTemporarily()
        }
    }

    private func showControlsTemporarily() {
        withAnimation(.easeInOut(duration: 0.2)) {
            areControlsVisible = true
        }

        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(4))

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                hideControls()
            }
        }
    }

    private func hideControls() {
        hideControlsTask?.cancel()

        withAnimation(.easeInOut(duration: 0.25)) {
            areControlsVisible = false
        }
    }

    private func schedulePendingSeekIfNeeded() {
        guard let position = pendingSeekPosition, position > 0 else {
            pendingSeekPosition = nil
            return
        }

        pendingSeekPosition = nil

        Task {
            try? await Task.sleep(for: .milliseconds(900))

            await MainActor.run {
                commandCenter.seek(to: position)
            }
        }
    }

    private func pauseForVisibilityLoss() {
        shouldResumeAfterVisibilityReturn = true
        pendingSeekPosition = playbackState.position
        playbackState.pendingSeekPosition = playbackState.position
        commandCenter.pause()
    }

    private func resumeAfterVisibilityReturn() {
        guard shouldResumeAfterVisibilityReturn else { return }
        shouldResumeAfterVisibilityReturn = false
        commandCenter.seek(to: playbackState.pendingSeekPosition ?? playbackState.position, resumePlayback: false)
    }

    private func rebuildPlaybackSurfaceKeepingPosition() {
        pendingSeekPosition = playbackState.position
        playbackState.pendingSeekPosition = playbackState.position
        didReceiveFirstProgress = false
        surfaceID = UUID()
        schedulePendingSeekIfNeeded()
    }

    private func rotationAngle(for orientation: UIDeviceOrientation) -> Angle {
        guard isFullscreenPresented else { return .zero }
        return orientation == .landscapeLeft ? .degrees(90) : .degrees(-90)
    }

    @MainActor
    private func switchQuality(to option: VideoQualityOption) async {
        if option.quality == currentSource.quality {
            showControlsTemporarily()
            return
        }

        let previousPosition = playbackState.position

        isSwitchingQuality = true
        qualityErrorMessage = nil
        showControlsTemporarily()

        do {
            let newSource = try await PlayURLService().fetchPlayableSource(
                bvid: currentSource.bvid,
                cid: currentSource.cid,
                preferredQuality: option.quality
            )

            currentSource = newSource
            if let selectedQuality = newSource.quality {
                PlaybackPreferences.savePreferredQuality(selectedQuality)
            }
            playbackState.resetForNewMedia()
            didReceiveFirstProgress = false
            surfaceID = UUID()
            pendingSeekPosition = previousPosition
            schedulePendingSeekIfNeeded()
        } catch {
            qualityErrorMessage = "åæ¢å¤±è´¥ï¼\(error.localizedDescription)"
        }

        isSwitchingQuality = false
        showControlsTemporarily()
    }
}

final class BilibiliVLCPlaybackState: ObservableObject {
    @Published var position: Double = 0
    @Published var pendingSeekPosition: Double?
    @Published var elapsedText = "00:00"
    @Published var durationText = "00:00"
    @Published var isPlaying = false
    @Published var isScrubbing = false

    func resetForNewMedia() {
        position = 0
        pendingSeekPosition = nil
        elapsedText = "00:00"
        durationText = "00:00"
        isPlaying = false
        isScrubbing = false
    }
}

final class BilibiliVLCCommandCenter: ObservableObject {
    var togglePlayHandler: (() -> Void)?
    var playHandler: (() -> Void)?
    var pauseHandler: (() -> Void)?
    var seekHandler: ((Double, Bool) -> Void)?
    var stopHandler: (() -> Void)?
    var attachPlayerLayerHandler: ((AVPlayerLayer?) -> Void)?

    func togglePlay() {
        togglePlayHandler?()
    }

    func play() {
        playHandler?()
    }

    func pause() {
        pauseHandler?()
    }

    func seek(to position: Double, resumePlayback: Bool = true) {
        seekHandler?(position, resumePlayback)
    }

    func stop() {
        stopHandler?()
    }

    func attachPlayerLayer(_ layer: AVPlayerLayer?) {
        attachPlayerLayerHandler?(layer)
    }
}

private struct FullscreenPlayerWindowPresenter: UIViewRepresentable {
    let isPresented: Bool
    let orientation: UIDeviceOrientation
    let playbackState: BilibiliVLCPlaybackState
    let commandCenter: BilibiliVLCCommandCenter
    let debugText: String?
    let onLayerDetachedChange: (Bool) -> Void
    let onDismiss: () -> Void

    func makeUIView(context: Context) -> UIView {
        UIView(frame: .zero)
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.update(
            isPresented: isPresented,
            orientation: orientation,
            playbackState: playbackState,
            commandCenter: commandCenter,
            debugText: debugText,
            onLayerDetachedChange: onLayerDetachedChange,
            onDismiss: onDismiss
        )
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        Task { @MainActor in
            coordinator.dismiss(commandCenter: coordinator.commandCenter)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        fileprivate weak var commandCenter: BilibiliVLCCommandCenter?
        private var window: UIWindow?
        private var hostingController: UIHostingController<FullscreenPlayerOverlay>?
        private let playerLayer = AVPlayerLayer()
        private var onLayerDetachedChange: ((Bool) -> Void)?

        @MainActor
        func update(
            isPresented: Bool,
            orientation: UIDeviceOrientation,
            playbackState: BilibiliVLCPlaybackState,
            commandCenter: BilibiliVLCCommandCenter,
            debugText: String?,
            onLayerDetachedChange: @escaping (Bool) -> Void,
            onDismiss: @escaping () -> Void
        ) {
            self.commandCenter = commandCenter
            self.onLayerDetachedChange = onLayerDetachedChange
            if isPresented {
                present(
                    orientation: orientation,
                    playbackState: playbackState,
                    commandCenter: commandCenter,
                    debugText: debugText,
                    onLayerDetachedChange: onLayerDetachedChange,
                    onDismiss: onDismiss
                )
            } else {
                dismiss(commandCenter: commandCenter)
            }
        }

        @MainActor
        private func present(
            orientation: UIDeviceOrientation,
            playbackState: BilibiliVLCPlaybackState,
            commandCenter: BilibiliVLCCommandCenter,
            debugText: String?,
            onLayerDetachedChange: @escaping (Bool) -> Void,
            onDismiss: @escaping () -> Void
        ) {
            commandCenter.attachPlayerLayer(playerLayer)
            onLayerDetachedChange(true)
            let overlay = FullscreenPlayerOverlay(
                playerLayer: playerLayer,
                orientation: orientation,
                playbackState: playbackState,
                commandCenter: commandCenter,
                debugText: debugText,
                onDismiss: onDismiss
            )

            if let hostingController {
                hostingController.rootView = overlay
                return
            }

            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
            else { return }

            let newWindow = UIWindow(windowScene: scene)
            newWindow.windowLevel = .alert + 1
            newWindow.backgroundColor = .black
            let controller = UIHostingController(rootView: overlay)
            controller.view.backgroundColor = .black
            newWindow.rootViewController = controller
            newWindow.isHidden = false
            window = newWindow
            hostingController = controller
        }

        @MainActor
        func dismiss(commandCenter: BilibiliVLCCommandCenter?) {
            commandCenter?.attachPlayerLayer(nil)
            onLayerDetachedChange?(false)
            hostingController = nil
            window?.isHidden = true
            window = nil
        }
    }
}

private struct FullscreenPlayerOverlay: View {
    let playerLayer: AVPlayerLayer
    let orientation: UIDeviceOrientation
    @ObservedObject var playbackState: BilibiliVLCPlaybackState
    let commandCenter: BilibiliVLCCommandCenter
    let debugText: String?
    let onDismiss: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()

                PlayerLayerHost(playerLayer: playerLayer)
                    .frame(width: proxy.size.height, height: proxy.size.width)
                    .rotationEffect(rotationAngle)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)

                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        commandCenter.togglePlay()
                    }

                VStack {
                    HStack(spacing: 12) {
                        Button {
                            commandCenter.togglePlay()
                        } label: {
                            Image(systemName: playbackState.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 42, height: 42)
                                .background(.white.opacity(0.16), in: Circle())
                        }
                        .buttonStyle(.plain)

                        if let debugText {
                            Text(debugText)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.yellow)
                                .lineLimit(4)
                        }

                        Spacer()

                        Button {
                            onDismiss()
                        } label: {
                            Image(systemName: "arrow.down.right.and.arrow.up.left")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 42, height: 42)
                                .background(.white.opacity(0.16), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 16)

                    Spacer()

                    HStack(spacing: 12) {
                        Text(playbackState.elapsedText)
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(.white)

                        Slider(value: Binding(
                            get: { playbackState.position },
                            set: { playbackState.position = $0 }
                        ), in: 0...1, onEditingChanged: { editing in
                            playbackState.isScrubbing = editing
                            if !editing {
                                commandCenter.seek(to: playbackState.position, resumePlayback: playbackState.isPlaying)
                            }
                        })
                        .tint(.white)

                        Text(playbackState.durationText)
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
                .rotationEffect(rotationAngle)
                .frame(width: proxy.size.height, height: proxy.size.width)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
        }
        .ignoresSafeArea()
    }

    private var rotationAngle: Angle {
        orientation == .landscapeLeft ? .degrees(90) : .degrees(-90)
    }
}

private struct PlayerLayerHost: UIViewRepresentable {
    let playerLayer: AVPlayerLayer

    func makeUIView(context: Context) -> PlayerLayerContainerView {
        let view = PlayerLayerContainerView()
        view.backgroundColor = .black
        view.hostedPlayerLayer = playerLayer
        playerLayer.videoGravity = .resizeAspect
        view.layer.addSublayer(playerLayer)
        return view
    }

    func updateUIView(_ uiView: PlayerLayerContainerView, context: Context) {
        if playerLayer.superlayer !== uiView.layer {
            playerLayer.removeFromSuperlayer()
            uiView.layer.addSublayer(playerLayer)
        }
        uiView.hostedPlayerLayer = playerLayer
        playerLayer.frame = uiView.bounds
    }

    static func dismantleUIView(_ uiView: PlayerLayerContainerView, coordinator: ()) {
        uiView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        uiView.hostedPlayerLayer = nil
    }
}

private final class PlayerLayerContainerView: UIView {
    weak var hostedPlayerLayer: AVPlayerLayer?

    override func layoutSubviews() {
        super.layoutSubviews()
        hostedPlayerLayer?.frame = bounds
    }
}

private struct BilibiliVLCVideoSurface: UIViewRepresentable {
    let source: PlayableVideoSource
    let playbackState: BilibiliVLCPlaybackState
    let commandCenter: BilibiliVLCCommandCenter
    let isFullscreen: Bool
    let fullscreenOrientation: UIDeviceOrientation

    func makeCoordinator() -> Coordinator {
        Coordinator(playbackState: playbackState, commandCenter: commandCenter)
    }

    func makeUIView(context: Context) -> AVPlayerContainerView {
        let view = AVPlayerContainerView()
        view.backgroundColor = .black
        context.coordinator.attach(to: view.playerLayer)
        context.coordinator.play(source: source)
        return view
    }

    func updateUIView(_ uiView: AVPlayerContainerView, context: Context) {
        context.coordinator.attach(to: uiView.playerLayer)
        context.coordinator.play(source: source)
    }

    static func dismantleUIView(_ uiView: AVPlayerContainerView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        private let player = AVPlayer()
        private weak var playerLayer: AVPlayerLayer?
        private weak var inlinePlayerLayer: AVPlayerLayer?
        private weak var playbackState: BilibiliVLCPlaybackState?
        private weak var commandCenter: BilibiliVLCCommandCenter?
        private var currentSource: PlayableVideoSource?
        private var timeObserver: Any?
        private var isUsingExternalPlayerLayer = false

        init(playbackState: BilibiliVLCPlaybackState, commandCenter: BilibiliVLCCommandCenter) {
            self.playbackState = playbackState
            self.commandCenter = commandCenter
            bindCommands()
        }

        deinit {
            removeTimeObserver()
        }

        func attach(to layer: AVPlayerLayer) {
            inlinePlayerLayer = layer
            guard !isUsingExternalPlayerLayer else { return }
            playerLayer = layer
            layer.videoGravity = .resizeAspect
            layer.player = player
        }

        func play(source: PlayableVideoSource) {
            guard source != currentSource else { return }
            currentSource = source
            configureAudioSession()
            playbackState?.resetForNewMedia()
            removeTimeObserver()

            let asset = AVURLAsset(url: source.url, options: assetOptions(headers: source.headers))
            let item = AVPlayerItem(asset: asset)
            item.preferredForwardBufferDuration = 2
            player.replaceCurrentItem(with: item)
            addTimeObserver()
            player.play()
        }

        func stop() {
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
                } else {
                    self.player.play()
                }
                self.updatePlaybackState()
            }

            commandCenter?.playHandler = { [weak self] in
                guard let self else { return }
                self.player.play()
                self.updatePlaybackState()
            }

            commandCenter?.pauseHandler = { [weak self] in
                guard let self else { return }
                self.player.pause()
                self.updatePlaybackState()
            }

            commandCenter?.seekHandler = { [weak self] position, resumePlayback in
                guard let self, let item = self.player.currentItem else { return }
                let duration = item.duration
                guard duration.isValid, duration.seconds.isFinite, duration.seconds > 0 else { return }
                let target = CMTime(seconds: duration.seconds * position, preferredTimescale: 600)
                self.player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                    guard let self else { return }
                    if resumePlayback {
                        self.player.play()
                    }
                    self.playbackState?.pendingSeekPosition = nil
                    self.updatePlaybackState()
                }
            }

            commandCenter?.stopHandler = { [weak self] in
                self?.stop()
            }

            commandCenter?.attachPlayerLayerHandler = { [weak self] layer in
                guard let self else { return }
                if let layer {
                    self.isUsingExternalPlayerLayer = true
                    self.playerLayer?.player = nil
                    self.playerLayer = layer
                    layer.videoGravity = .resizeAspect
                    layer.player = self.player
                } else if let inlinePlayerLayer = self.inlinePlayerLayer {
                    self.isUsingExternalPlayerLayer = false
                    self.playerLayer?.player = nil
                    self.playerLayer = inlinePlayerLayer
                    inlinePlayerLayer.videoGravity = .resizeAspect
                    inlinePlayerLayer.player = self.player
                }
            }
        }

        private func addTimeObserver() {
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

        fileprivate func updatePlaybackState() {
            guard let playbackState else { return }
            let currentTime = player.currentTime().seconds
            let duration = player.currentItem?.duration.seconds ?? 0

            if let pendingSeekPosition = playbackState.pendingSeekPosition {
                playbackState.position = pendingSeekPosition
            } else if !playbackState.isScrubbing {
                if duration.isFinite, duration > 0, currentTime.isFinite {
                    playbackState.position = max(0, min(1, currentTime / duration))
                } else {
                    playbackState.position = 0
                }
            }
            playbackState.elapsedText = Self.format(seconds: currentTime)
            playbackState.durationText = Self.format(seconds: duration)
            playbackState.isPlaying = player.timeControlStatus == .playing
        }

        fileprivate static func format(seconds: TimeInterval) -> String {
            guard seconds.isFinite else { return "00:00" }
            let totalSeconds = max(Int(seconds), 0)
            let hours = totalSeconds / 3600
            let minutes = (totalSeconds % 3600) / 60
            let seconds = totalSeconds % 60
            if hours > 0 {
                return String(format: "%d:%02d:%02d", hours, minutes, seconds)
            }
            return String(format: "%02d:%02d", minutes, seconds)
        }

        private func assetOptions(headers: [String: String]) -> [String: Any] {
            var injectedHeaders = headers
            let cookies = HTTPCookieStorage.shared.cookies ?? []
            if let cookieHeader = HTTPCookie.requestHeaderFields(with: cookies)["Cookie"], !cookieHeader.isEmpty {
                injectedHeaders["Cookie"] = cookieHeader
            }
            injectedHeaders["Accept"] = "*/*"
            injectedHeaders["Connection"] = "keep-alive"
            return ["AVURLAssetHTTPHeaderFieldsKey": injectedHeaders]
        }

        private func configureAudioSession() {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .moviePlayback, options: [])
                try session.setActive(true)
            } catch {
                print("Failed to configure AVPlayer audio session: \(error.localizedDescription)")
            }
        }
    }
}

final class AVPlayerContainerView: UIView {
    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}


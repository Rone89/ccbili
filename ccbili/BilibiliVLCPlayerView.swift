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

import KSPlayer


struct BilibiliVLCPlayerView: View {
    let source: PlayableVideoSource
    private let enablesAutoFullscreen: Bool
    private let initialPosition: Double?
    private let onPositionChange: (Double) -> Void

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

    init(
        source: PlayableVideoSource,
        enablesAutoFullscreen: Bool = true,
        initialPosition: Double? = nil,
        onPositionChange: @escaping (Double) -> Void = { _ in }
    ) {
        self.source = source
        self.enablesAutoFullscreen = enablesAutoFullscreen
        self.initialPosition = initialPosition
        self.onPositionChange = onPositionChange
        _currentSource = State(initialValue: source)
        _pendingSeekPosition = State(initialValue: initialPosition)
    }

    var body: some View {
        playerSurface
            .background(.black)
            .clipped()
            .statusBarHidden(isFullscreenPresented)
            .animation(.easeInOut(duration: 0.25), value: isFullscreenPresented)
        .onAppear {
            showControlsTemporarily()
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            schedulePendingSeekIfNeeded()
        }
        .onReceive(playbackState.$position) { position in
            onPositionChange(position)
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
        .onDisappear {
            hideControlsTask?.cancel()
            commandCenter.stop()
        }
    }

    private var playerSurface: some View {
        ZStack {
            videoSurface

            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleControlsVisibility()
                }

            playerOverlays
        }
    }

    private var videoSurface: some View {
        BilibiliVLCVideoSurface(
            source: currentSource,
            playbackState: playbackState,
            commandCenter: commandCenter,
            isFullscreen: isFullscreenPresented,
            fullscreenOrientation: fullscreenOrientation
        )
            .id(surfaceID)
            .background(.black)
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
    }

    private var controlsOverlay: some View {
        ZStack {
            LinearGradient(
                colors: [
                    .black.opacity(0.48),
                    .clear,
                    .black.opacity(0.74)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                topControls

                if isPlaybackDiagnosticsEnabled, let debugDescription = currentSource.debugDescription {
                    debugOverlay(debugDescription)
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
                    .background(.white.opacity(0.16), in: Circle())
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
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }

    private func debugOverlay(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.yellow.opacity(0.95))
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.top, 6)
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
            .background(.white.opacity(0.16), in: Capsule())
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

                        if !isEditing {
                            commandCenter.seek(to: playbackState.position)
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
        .padding(.bottom, 10)
    }

    private var fallbackQualities: [VideoQualityOption] {
        [
            VideoQualityOption(quality: 32, description: "480P"),
            VideoQualityOption(quality: 64, description: "720P"),
            VideoQualityOption(quality: 80, description: "1080P"),
            VideoQualityOption(quality: 112, description: "1080P+"),
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

    @MainActor
    private func switchQuality(to option: VideoQualityOption) async {
        guard option.quality != currentSource.quality else {
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
            playbackState.resetForNewMedia()
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
    @Published var elapsedText = "00:00"
    @Published var durationText = "00:00"
    @Published var isPlaying = false
    @Published var isScrubbing = false

    func resetForNewMedia() {
        position = 0
        elapsedText = "00:00"
        durationText = "00:00"
        isPlaying = false
        isScrubbing = false
    }
}

final class BilibiliVLCCommandCenter: ObservableObject {
    var togglePlayHandler: (() -> Void)?
    var seekHandler: ((Double) -> Void)?
    var stopHandler: (() -> Void)?

    func togglePlay() {
        togglePlayHandler?()
    }

    func seek(to position: Double) {
        seekHandler?(position)
    }

    func stop() {
        stopHandler?()
    }
}

private struct BilibiliVLCVideoSurface: UIViewRepresentable {
    let source: PlayableVideoSource
    let playbackState: BilibiliVLCPlaybackState
    let commandCenter: BilibiliVLCCommandCenter
    let isFullscreen: Bool
    let fullscreenOrientation: UIDeviceOrientation

    func makeCoordinator() -> Coordinator {
        Coordinator(
            playbackState: playbackState,
            commandCenter: commandCenter
        )
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        context.coordinator.attach(to: view)
        context.coordinator.play(source: source)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.attach(to: uiView)
        context.coordinator.play(source: source)
        context.coordinator.setFullscreen(isFullscreen, orientation: fullscreenOrientation)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator: NSObject {
        private let player = KSPlayerLayer(
            url: URL(fileURLWithPath: "/dev/null"),
            isAutoPlay: false,
            options: KSOptions()
        )
        private weak var playbackState: BilibiliVLCPlaybackState?
        private weak var commandCenter: BilibiliVLCCommandCenter?
        private var currentSource: PlayableVideoSource?
        private weak var inlineView: UIView?
        private var fullscreenWindow: UIWindow?
        private let fullscreenContainer = UIView()
        private var isFullscreen = false

        init(
            playbackState: BilibiliVLCPlaybackState,
            commandCenter: BilibiliVLCCommandCenter
        ) {
            self.playbackState = playbackState
            self.commandCenter = commandCenter
            super.init()
            player.delegate = self
            bindCommands()
        }

        func attach(to view: UIView) {
            inlineView = view
            guard !isFullscreen else { return }

            guard player.player.view?.superview !== view else {
                return
            }

            attachPlayerView(to: view)
        }

        func setFullscreen(_ fullscreen: Bool, orientation: UIDeviceOrientation) {
            guard isFullscreen != fullscreen || fullscreen else { return }

            if fullscreen {
                enterFullscreen(orientation: orientation)
            } else {
                exitFullscreen()
            }
        }

        private func attachPlayerView(to view: UIView) {
            player.player.view?.removeFromSuperview()

            guard let playerView = player.player.view else {
                return
            }

            view.addSubview(playerView)
            playerView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                playerView.topAnchor.constraint(equalTo: view.topAnchor),
                playerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                playerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                playerView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])
        }

        private func enterFullscreen(orientation: UIDeviceOrientation) {
            guard fullscreenWindow == nil else { return }
            guard let windowScene = inlineView?.window?.windowScene ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
                return
            }

            isFullscreen = true

            let window = UIWindow(windowScene: windowScene)
            window.windowLevel = .statusBar + 1
            window.backgroundColor = .black

            let controller = UIViewController()
            controller.view.backgroundColor = .black
            window.rootViewController = controller
            window.isHidden = false
            fullscreenWindow = window

            fullscreenContainer.backgroundColor = .black
            controller.view.addSubview(fullscreenContainer)
            fullscreenContainer.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                fullscreenContainer.centerXAnchor.constraint(equalTo: controller.view.centerXAnchor),
                fullscreenContainer.centerYAnchor.constraint(equalTo: controller.view.centerYAnchor),
                fullscreenContainer.widthAnchor.constraint(equalTo: controller.view.heightAnchor),
                fullscreenContainer.heightAnchor.constraint(equalTo: controller.view.widthAnchor)
            ])

            fullscreenContainer.transform = rotationTransform(for: orientation)
            attachPlayerView(to: fullscreenContainer)
            fullscreenContainer.alpha = 0
            fullscreenContainer.transform = fullscreenContainer.transform.scaledBy(x: 0.96, y: 0.96)
            UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
                self.fullscreenContainer.alpha = 1
                self.fullscreenContainer.transform = self.rotationTransform(for: orientation)
            }
        }

        private func exitFullscreen() {
            isFullscreen = false

            if let inlineView {
                attachPlayerView(to: inlineView)
            }

            let oldContainer = fullscreenContainer
            let oldWindow = fullscreenWindow
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
                oldContainer.alpha = 0
            } completion: { _ in
                oldContainer.removeFromSuperview()
                oldWindow?.isHidden = true
            }
            fullscreenWindow = nil
        }

        private func rotationTransform(for orientation: UIDeviceOrientation) -> CGAffineTransform {
            orientation == .landscapeLeft
                ? CGAffineTransform(rotationAngle: .pi / 2)
                : CGAffineTransform(rotationAngle: -.pi / 2)
        }

        func play(source: PlayableVideoSource) {
            guard currentSource != source else {
                return
            }

            currentSource = source

            configureAudioSession()
            player.stop()

            let options = makeOptions(for: source)
            if let audioURL = source.audioURL {
                player.set(urls: [source.url, audioURL], options: options)
            } else {
                player.set(url: source.url, options: options)
            }
            player.play()
        }

        func stop() {
            player.stop()
            exitFullscreen()
            currentSource = nil
        }

        private func bindCommands() {
            commandCenter?.togglePlayHandler = { [weak self] in
                guard let self else { return }

                if self.player.state.isPlaying {
                    self.player.pause()
                } else {
                    self.player.play()
                }

                self.updatePlaybackState()
            }

            commandCenter?.seekHandler = { [weak self] position in
                guard let self else { return }
                let duration = self.player.player.duration
                guard duration.isFinite, duration > 0 else {
                    return
                }

                self.player.seek(time: duration * position, autoPlay: true) { [weak self] _ in
                    self?.updatePlaybackState()
                }
            }

            commandCenter?.stopHandler = { [weak self] in
                self?.stop()
            }
        }

        fileprivate func updatePlaybackState() {
            guard let playbackState else {
                return
            }

            let duration = player.player.duration
            let currentTime = player.player.currentPlaybackTime

            DispatchQueue.main.async {
                if !playbackState.isScrubbing {
                    if duration.isFinite, duration > 0 {
                        playbackState.position = max(0, min(1, currentTime / duration))
                    } else {
                        playbackState.position = 0
                    }
                }

                playbackState.elapsedText = Self.format(seconds: currentTime)
                playbackState.durationText = Self.format(seconds: duration)
                playbackState.isPlaying = self.player.state.isPlaying
            }

        }

        fileprivate static func format(seconds: TimeInterval) -> String {
            guard seconds.isFinite else {
                return "00:00"
            }

            let totalSeconds = max(Int(seconds), 0)
            let hours = totalSeconds / 3600
            let minutes = (totalSeconds % 3600) / 60
            let seconds = totalSeconds % 60

            if hours > 0 {
                return String(format: "%d:%02d:%02d", hours, minutes, seconds)
            }

            return String(format: "%02d:%02d", minutes, seconds)
        }

        private func makeOptions(for source: PlayableVideoSource) -> KSOptions {
            let options = KSOptions()
            options.isSeekedAutoPlay = true
            options.hardwareDecode = false
            options.referer = source.headers["Referer"] ?? AppConfig.webBaseURL.absoluteString
            options.userAgent = source.headers["User-Agent"] ?? AppConfig.defaultUserAgent
            var headers = source.headers
            let cookies = HTTPCookieStorage.shared.cookies ?? []
            if let cookieHeader = HTTPCookie.requestHeaderFields(with: cookies)["Cookie"], !cookieHeader.isEmpty {
                headers["Cookie"] = cookieHeader
            }
            headers["Accept"] = "*/*"
            headers["Connection"] = "keep-alive"
            options.appendHeader(headers)
            return options
        }

        private func configureAudioSession() {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .moviePlayback, options: [])
                try session.setActive(true)
            } catch {
                print("Failed to configure audio session: \(error.localizedDescription)")
            }
        }
    }
}

extension BilibiliVLCVideoSurface.Coordinator: KSPlayerLayerDelegate {
    func player(layer: KSPlayerLayer, state: KSPlayerState) {
        updatePlaybackState()
    }

    func player(layer: KSPlayerLayer, currentTime: TimeInterval, totalTime: TimeInterval) {
        guard let playbackState else {
            return
        }

        DispatchQueue.main.async {
            if !playbackState.isScrubbing, totalTime.isFinite, totalTime > 0 {
                playbackState.position = max(0, min(1, currentTime / totalTime))
            }

            playbackState.elapsedText = Self.format(seconds: currentTime)
            playbackState.durationText = Self.format(seconds: totalTime)
            playbackState.isPlaying = layer.state.isPlaying
        }

    }

    func player(layer: KSPlayerLayer, finish error: Error?) {
        updatePlaybackState()
    }

    func player(layer: KSPlayerLayer, bufferedCount: Int, consumeTime: TimeInterval) {}
}

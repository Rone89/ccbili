import SwiftUI
import UIKit

struct MPVPlayerView: UIViewRepresentable {
    let source: PlayableVideoSource
    let commandCenter: BilibiliVLCCommandCenter

    func makeCoordinator() -> Coordinator {
        Coordinator(commandCenter: commandCenter)
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
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        private let player = MPVPlayerController()
        private var currentSource: PlayableVideoSource?
        private weak var commandCenter: BilibiliVLCCommandCenter?

        init(commandCenter: BilibiliVLCCommandCenter) {
            self.commandCenter = commandCenter
            self.commandCenter?.togglePlayHandler = { [weak self] in
                self?.player.togglePlay()
            }
            self.commandCenter?.stopHandler = { [weak self] in
                self?.stop()
            }
        }

        func attach(to view: UIView) {
            player.attach(to: view.layer)
        }

        func play(source: PlayableVideoSource) {
            guard source != currentSource else { return }
            currentSource = source
            player.play(source: source)
        }

        func stop() {
            player.stop()
        }
    }
}

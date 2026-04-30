import SwiftUI
import UIKit

struct InteractivePopGestureRestorer: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        PopGestureRestoringViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            (uiViewController as? PopGestureRestoringViewController)?.restoreInteractivePopGesture()
        }
    }
}

private final class PopGestureRestoringViewController: UIViewController {
    private let gestureDelegate = InteractivePopGestureDelegate()

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        restoreInteractivePopGesture()
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        DispatchQueue.main.async { [weak self] in
            self?.restoreInteractivePopGesture()
        }
    }

    func restoreInteractivePopGesture() {
        guard
            let navigationController = navigationController,
            let interactivePopGestureRecognizer = navigationController.interactivePopGestureRecognizer
        else { return }

        gestureDelegate.navigationController = navigationController
        interactivePopGestureRecognizer.delegate = gestureDelegate
        interactivePopGestureRecognizer.isEnabled = true
    }
}

private final class InteractivePopGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    weak var navigationController: UINavigationController?

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let navigationController = navigationController else { return false }
        return navigationController.viewControllers.count > 1 && navigationController.transitionCoordinator == nil
    }
}

extension View {
    func restoresInteractivePopGesture() -> some View {
        background {
            InteractivePopGestureRestorer()
                .frame(width: 0, height: 0)
        }
    }
}

import UIKit

enum AppOrientationController {
    static var supportedOrientations: UIInterfaceOrientationMask = .portrait
    private(set) static var isPlayerFullscreenActive = false

    static func allow(_ orientations: UIInterfaceOrientationMask, scene: UIWindowScene? = nil) {
        supportedOrientations = orientations
        requestSupportedOrientationUpdates(in: targetScene(scene))
    }

    static func lock(_ orientations: UIInterfaceOrientationMask, scene: UIWindowScene? = nil) {
        supportedOrientations = orientations
        let targetScene = targetScene(scene)

        requestSupportedOrientationUpdates(in: targetScene)

        if #available(iOS 16.0, *) {
            targetScene?.requestGeometryUpdate(.iOS(interfaceOrientations: orientations))
        } else {
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }

    static func beginPlayerFullscreen(
        _ orientations: UIInterfaceOrientationMask,
        scene: UIWindowScene? = nil,
        requestGeometryUpdate: Bool
    ) {
        isPlayerFullscreenActive = true
        if requestGeometryUpdate {
            lock(orientations, scene: scene)
        } else {
            allow(orientations, scene: scene)
        }
    }

    static func endPlayerFullscreen(scene: UIWindowScene? = nil) {
        isPlayerFullscreenActive = false
        lock(.portrait, scene: scene)
    }

    static func lockPortraitForPage(scene: UIWindowScene? = nil) {
        guard !isPlayerFullscreenActive else { return }
        lock(.portrait, scene: scene)
    }

    private static func targetScene(_ scene: UIWindowScene?) -> UIWindowScene? {
        scene ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }

    private static func requestSupportedOrientationUpdates(in scene: UIWindowScene?) {
        scene?.windows.forEach { window in
            window.rootViewController?.requestSupportedOrientationUpdate()
        }
    }
}

private extension UIViewController {
    func requestSupportedOrientationUpdate() {
        setNeedsUpdateOfSupportedInterfaceOrientations()
        presentedViewController?.requestSupportedOrientationUpdate()
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        AppOrientationController.supportedOrientations
    }
}

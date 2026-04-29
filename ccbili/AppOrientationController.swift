import UIKit

enum AppOrientationController {
    static var supportedOrientations: UIInterfaceOrientationMask = .portrait

    static func lock(_ orientations: UIInterfaceOrientationMask, scene: UIWindowScene? = nil) {
        supportedOrientations = orientations
        let targetScene = scene ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }

        targetScene?.windows.forEach {
            $0.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }

        if #available(iOS 16.0, *) {
            targetScene?.requestGeometryUpdate(.iOS(interfaceOrientations: orientations))
        } else {
            UIViewController.attemptRotationToDeviceOrientation()
        }
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

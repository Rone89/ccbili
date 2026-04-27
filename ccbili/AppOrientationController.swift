import UIKit

enum AppOrientationController {
    static var supportedOrientations: UIInterfaceOrientationMask = .portrait

    static func lock(_ orientations: UIInterfaceOrientationMask) {
        supportedOrientations = orientations
        UIViewController.attemptRotationToDeviceOrientation()
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

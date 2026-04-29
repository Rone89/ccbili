//
//  ccbiliApp.swift
//  ccbili
//
//  Created by chuzu  on 2026/4/25.
//

import SwiftUI

@main
struct ccbiliApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var authManager = AuthManager()

    var body: some Scene {
        WindowGroup {
            OrientationRootView(authManager: authManager, scenePhase: scenePhase)
        }
    }
}

private struct OrientationRootView: UIViewControllerRepresentable {
    let authManager: AuthManager
    let scenePhase: ScenePhase

    func makeUIViewController(context: Context) -> OrientationHostingController<RootContentView> {
        OrientationHostingController(rootView: rootView)
    }

    func updateUIViewController(_ controller: OrientationHostingController<RootContentView>, context: Context) {
        controller.rootView = rootView
        controller.setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    private var rootView: RootContentView {
        RootContentView(authManager: authManager, scenePhase: scenePhase)
    }
}

private struct RootContentView: View {
    let authManager: AuthManager
    let scenePhase: ScenePhase

    var body: some View {
        ContentView()
            .environment(authManager)
            .onAppear {
                BilibiliCookieStore.restoreToSharedStorage()
                Task {
                    await BilibiliCookieStore.restoreEverywhere()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .active:
                    Task {
                        await BilibiliCookieStore.restoreEverywhere()
                        await authManager.refreshLoginStatus(allowOfflineFallback: true)
                    }
                case .background:
                    Task {
                        await BilibiliCookieStore.syncWebCookiesToSharedStorage()
                        BilibiliCookieStore.persistSharedStorage()
                    }
                case .inactive:
                    break
                @unknown default:
                    break
                }
            }
    }
}

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
            ContentView()
                .environment(authManager)
                .onAppear {
                    BilibiliCookieStore.restoreToSharedStorage()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        BilibiliCookieStore.restoreToSharedStorage()
                        Task {
                            await authManager.refreshLoginStatus(allowOfflineFallback: true)
                        }
                    case .background:
                        BilibiliCookieStore.persistSharedStorage()
                    case .inactive:
                        break
                    @unknown default:
                        break
                    }
                }
        }
    }
}

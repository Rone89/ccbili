//
//  ContentView.swift
//  ccbili
//
//  Created by chuzu  on 2026/4/25.
//

import SwiftUI

private enum MainTab: Hashable {
    case home
    case search
    case profile
}

struct ContentView: View {
    @State private var selectedTab: MainTab = .home
    @State private var lastHomeTapDate: Date = .distantPast

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView()
            }
            .tabItem {
                Label("首页", systemImage: "house")
            }
            .tag(MainTab.home)

            NavigationStack {
                SearchView()
            }
            .tabItem {
                Label("搜索", systemImage: "magnifyingglass")
            }
            .tag(MainTab.search)

            NavigationStack {
                ProfileView()
            }
            .tabItem {
                Label("我的", systemImage: "person")
            }
            .tag(MainTab.profile)
        }
        .onAppear {
            AppOrientationController.lock(.portrait)
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            guard newValue == .home else { return }

            let now = Date()
            if oldValue == .home || now.timeIntervalSince(lastHomeTapDate) < 0.5 {
                NotificationCenter.default.post(name: .homeTabDidRetap, object: nil)
            }
            lastHomeTapDate = now
        }
    }
}

#Preview {
    ContentView()
        .environment(AuthManager())
}

extension Notification.Name {
    static let homeTabDidRetap = Notification.Name("homeTabDidRetap")
    static let homeRefreshRequested = Notification.Name("homeRefreshRequested")
}


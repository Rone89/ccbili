//
//  WebLoginView.swift
//  ccbili
//
//  Created by chuzu  on 2026/4/25.
//

import SwiftUI
import WebKit

struct WebLoginView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var pageTitle = "网页登录"
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ZStack {
                WebLoginWebView(
                    url: AppConfig.webBaseURL,
                    onTitleChange: { title in
                        if let title, !title.isEmpty {
                            pageTitle = title
                        }
                    },
                    onLoadingChange: { loading in
                        isLoading = loading
                    },
                    onLoginDetected: {
                        Task {
                            await authManager.refreshLoginStatus()
                            if authManager.isLoggedIn {
                                dismiss()
                            }
                        }
                    }
                )

                if isLoading {
                    VStack {
                        ProgressView("页面加载中...")
                            .padding()
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        Spacer()
                    }
                    .padding()
                }
            }
            .navigationTitle(pageTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("刷新") {
                        NotificationCenter.default.post(name: .webLoginReloadRequested, object: nil)
                    }
                }
            }
        }
    }
}

private struct WebLoginWebView: UIViewRepresentable {
    let url: URL
    let onTitleChange: (String?) -> Void
    let onLoadingChange: (Bool) -> Void
    let onLoginDetected: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onTitleChange: onTitleChange,
            onLoadingChange: onLoadingChange,
            onLoginDetected: onLoginDetected
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = AppConfig.defaultUserAgent

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.reloadWebView),
            name: .webLoginReloadRequested,
            object: nil
        )

        var request = URLRequest(url: url)
        request.setValue(AppConfig.defaultUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Referer")
        Task {
            await BilibiliCookieStore.seedWebCookieStore(configuration.websiteDataStore.httpCookieStore)
            await MainActor.run {
                webView.load(request)
            }
        }

        context.coordinator.webView = webView
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(
            coordinator,
            name: .webLoginReloadRequested,
            object: nil
        )
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?

        private let onTitleChange: (String?) -> Void
        private let onLoadingChange: (Bool) -> Void
        private let onLoginDetected: () -> Void

        init(
            onTitleChange: @escaping (String?) -> Void,
            onLoadingChange: @escaping (Bool) -> Void,
            onLoginDetected: @escaping () -> Void
        ) {
            self.onTitleChange = onTitleChange
            self.onLoadingChange = onLoadingChange
            self.onLoginDetected = onLoginDetected
        }

        @objc
        func reloadWebView() {
            webView?.reload()
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            onLoadingChange(true)
            onTitleChange(webView.title)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onLoadingChange(false)
            onTitleChange(webView.title)

            Task {
                await syncCookies(from: webView)
                await checkLoginStatus()
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onLoadingChange(false)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onLoadingChange(false)
        }

        private func syncCookies(from webView: WKWebView) async {
            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
            let cookies = await cookieStore.allCookies()

            let sharedStorage = HTTPCookieStorage.shared
            for cookie in cookies {
                sharedStorage.setCookie(cookie)
            }
            BilibiliCookieStore.persistAndShare(cookies: cookies)
        }

        private func checkLoginStatus() async {
            let url = AppConfig.apiBaseURL.appending(path: "/x/web-interface/nav")

            do {
                let response = try await APIClient.shared.get(
                    url: url,
                    as: BiliBaseResponse<NavUserInfoDTO>.self
                )

                if response.code == 0, response.data?.isLogin == true {
                    onLoginDetected()
                }
            } catch {
            }
        }
    }
}

private extension WKHTTPCookieStore {
    func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }
}

private extension Notification.Name {
    static let webLoginReloadRequested = Notification.Name("webLoginReloadRequested")
}

import SwiftUI

struct ProfileView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var isShowingQRCodeLogin = false
    @State private var isShowingWebLogin = false

    var body: some View {
        List {
            Section("账户") {
                if authManager.isLoading {
                    HStack {
                        ProgressView()
                        Text("正在检查登录状态...")
                    }
                } else if authManager.isLoggedIn {
                    Text("已登录：\(authManager.username ?? "未知用户")")

                    NavigationLink {
                        HistoryView()
                    } label: {
                        Label("历史观看", systemImage: "clock.arrow.circlepath")
                    }

                    Button("刷新登录状态") {
                        Task {
                            await authManager.refreshLoginStatus()
                        }
                    }

                    Button("退出登录", role: .destructive) {
                        authManager.logout()
                    }
                } else {
                    Text("当前未登录")

                    if let errorMessage = authManager.errorMessage, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }

                    Button("网页登录") {
                        isShowingWebLogin = true
                    }

                    Button("二维码登录") {
                        isShowingQRCodeLogin = true
                    }

                    Button("检查当前登录状态") {
                        Task {
                            await authManager.refreshLoginStatus()
                        }
                    }

                    Button("模拟登录") {
                        authManager.loginDemo()
                    }
                }
            }

            Section("说明") {
                Text("后续这里可以接入云端点赞、投币、收藏等能力")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("我的")
        .task {
            if !authManager.isLoggedIn {
                await authManager.refreshLoginStatus()
            }
        }
        .refreshable {
            await authManager.refreshLoginStatus()
        }
        .sheet(isPresented: $isShowingQRCodeLogin) {
            QRCodeLoginView()
                .environment(authManager)
        }
        .sheet(isPresented: $isShowingWebLogin) {
            WebLoginView()
                .environment(authManager)
        }
    }
}

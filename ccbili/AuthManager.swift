import Foundation
import Observation

@Observable
final class AuthManager {
    var isLoggedIn = UserDefaults.standard.bool(forKey: "auth.lastKnownLoggedIn")
    var username: String?
    var avatarURL: URL?

    var isLoading = false
    var errorMessage: String?

    func refreshLoginStatus(allowOfflineFallback: Bool = false) async {
        BilibiliCookieStore.restoreToSharedStorage()

        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        do {
            await BilibiliCookieStore.syncWebCookiesToSharedStorage()
            BilibiliCookieStore.restoreToSharedStorage()

            let url = AppConfig.apiBaseURL.appending(path: "/x/web-interface/nav")
            let response = try await APIClient.shared.get(
                url: url,
                as: BiliBaseResponse<NavUserInfoDTO>.self
            )

            guard response.code == 0, let data = response.data else {
                if allowOfflineFallback, UserDefaults.standard.bool(forKey: "auth.lastKnownLoggedIn") {
                    isLoggedIn = true
                } else {
                    isLoggedIn = false
                    username = nil
                    avatarURL = nil
                }
                persistLastKnownLoginState()
                return
            }

            if data.isLogin == true {
                isLoggedIn = true
                username = data.uname ?? "已登录用户"
                avatarURL = normalizedImageURL(from: data.face)
                persistLastKnownLoginState()
                BilibiliCookieStore.persistSharedStorage()
            } else if allowOfflineFallback, UserDefaults.standard.bool(forKey: "auth.lastKnownLoggedIn") {
                isLoggedIn = true
            } else {
                isLoggedIn = false
                username = nil
                avatarURL = nil
                persistLastKnownLoginState()
            }
        } catch {
            if !allowOfflineFallback {
                isLoggedIn = false
                username = nil
                avatarURL = nil
                persistLastKnownLoginState()
            }
            errorMessage = error.localizedDescription
        }
    }

    func loginDemo() {
        isLoggedIn = true
        username = "Demo User"
        avatarURL = nil
        errorMessage = nil
        persistLastKnownLoginState()
    }

    func logout() {
        clearBilibiliCookies()
        BilibiliCookieStore.clear()
        isLoggedIn = false
        username = nil
        avatarURL = nil
        errorMessage = nil
        persistLastKnownLoginState()
    }

    private func clearBilibiliCookies() {
        let storage = HTTPCookieStorage.shared
        let cookies = storage.cookies ?? []

        for cookie in cookies where cookie.domain.contains("bilibili.com") {
            storage.deleteCookie(cookie)
        }
    }

    private func persistLastKnownLoginState() {
        UserDefaults.standard.set(isLoggedIn, forKey: "auth.lastKnownLoggedIn")
        UserDefaults.standard.synchronize()
    }

    private func normalizedImageURL(from path: String?) -> URL? {
        guard let path, !path.isEmpty else {
            return nil
        }

        if path.hasPrefix("//") {
            return URL(string: "https:" + path)
        }

        return URL(string: path)
    }
}

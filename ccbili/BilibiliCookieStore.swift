import Foundation
import WebKit

enum BilibiliCookieStore {
    private static let storageKey = "bilibili.persisted.cookies.v2"
    private static let legacyStorageKey = "bilibili.persisted.cookies"

    static func restoreToSharedStorage() {
        for cookie in persistedCookies() {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }

    static func persistSharedStorage() {
        persist(cookies: bilibiliCookies(from: HTTPCookieStorage.shared.cookies ?? []))
    }

    static func persistEverywhere() async {
        await syncWebCookiesToSharedStorage()
        persistSharedStorage()
    }

    static func syncWebCookiesToSharedStorage() async {
        let cookieStore = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        persistAndShare(cookies: cookieStore)
    }

    static func restoreEverywhere() async {
        restoreToSharedStorage()
        await seedWebCookieStore(WKWebsiteDataStore.default().httpCookieStore)
        await syncWebCookiesToSharedStorage()
    }

    static func persistAndShare(cookies: [HTTPCookie]) {
        let filteredCookies = bilibiliCookies(from: cookies)
        guard !filteredCookies.isEmpty else { return }

        for cookie in filteredCookies {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
        persist(cookies: filteredCookies)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: legacyStorageKey)
        UserDefaults.standard.synchronize()
    }

    static func seedWebCookieStore(_ cookieStore: WKHTTPCookieStore) async {
        for cookie in persistedCookies() {
            await cookieStore.setCookie(cookie)
        }
    }

    static func cookieHeader() -> String? {
        restoreToSharedStorage()

        let cookies = bilibiliCookies(from: HTTPCookieStorage.shared.cookies ?? [])
        guard !cookies.isEmpty else { return nil }

        let header = HTTPCookie.requestHeaderFields(with: cookies)["Cookie"]
        return header?.isEmpty == false ? header : nil
    }

    private static func bilibiliCookies(from cookies: [HTTPCookie]) -> [HTTPCookie] {
        cookies.filter { cookie in
            cookie.domain.contains("bilibili.com") || cookie.domain.contains("biligame.com")
        }
    }

    private static func persist(cookies: [HTTPCookie]) {
        let incomingCookies = bilibiliCookies(from: cookies)
        guard !incomingCookies.isEmpty else { return }

        let mergedCookies = mergeCookies(existing: persistedCookies(), incoming: incomingCookies)
        guard !mergedCookies.isEmpty else {
            UserDefaults.standard.removeObject(forKey: storageKey)
            UserDefaults.standard.removeObject(forKey: legacyStorageKey)
            UserDefaults.standard.synchronize()
            return
        }

        let snapshots = mergedCookies.map(PersistentCookie.init(cookie:))

        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
        UserDefaults.standard.synchronize()
    }

    private static func persistedCookies() -> [HTTPCookie] {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let snapshots = try? JSONDecoder().decode([PersistentCookie].self, from: data) {
            return nonExpiredCookies(from: snapshots.compactMap(\.cookie))
        }

        guard let properties = UserDefaults.standard.array(forKey: legacyStorageKey) as? [[String: Any]] else {
            return []
        }

        let cookies = properties.compactMap { propertyMap in
            let typedProperties = Dictionary(uniqueKeysWithValues: propertyMap.map { key, value in
                (HTTPCookiePropertyKey(key), value)
            })
            return HTTPCookie(properties: typedProperties)
        }
        return nonExpiredCookies(from: cookies)
    }

    private static func nonExpiredCookies(from cookies: [HTTPCookie]) -> [HTTPCookie] {
        let now = Date()
        return cookies.filter { cookie in
            guard let expiresDate = cookie.expiresDate else { return true }
            return expiresDate > now
        }
    }

    private static func mergeCookies(existing: [HTTPCookie], incoming: [HTTPCookie]) -> [HTTPCookie] {
        var cookiesByKey: [String: HTTPCookie] = [:]
        for cookie in existing {
            cookiesByKey[cookieKey(for: cookie)] = cookie
        }
        for cookie in incoming {
            if isExpired(cookie) {
                cookiesByKey.removeValue(forKey: cookieKey(for: cookie))
            } else {
                cookiesByKey[cookieKey(for: cookie)] = cookie
            }
        }
        return nonExpiredCookies(from: Array(cookiesByKey.values))
    }

    private static func isExpired(_ cookie: HTTPCookie) -> Bool {
        guard let expiresDate = cookie.expiresDate else { return false }
        return expiresDate <= Date()
    }

    private static func cookieKey(for cookie: HTTPCookie) -> String {
        "\(cookie.domain)|\(cookie.path)|\(cookie.name)"
    }

    private struct PersistentCookie: Codable {
        let name: String
        let value: String
        let domain: String
        let path: String
        let expiresDate: Date?
        let isSecure: Bool
        let isHTTPOnly: Bool
        let sameSitePolicy: String?

        init(cookie: HTTPCookie) {
            name = cookie.name
            value = cookie.value
            domain = cookie.domain
            path = cookie.path
            expiresDate = cookie.expiresDate
            isSecure = cookie.isSecure
            isHTTPOnly = cookie.properties?[HTTPCookiePropertyKey("HttpOnly")] != nil
            sameSitePolicy = cookie.properties?[HTTPCookiePropertyKey("SameSite")] as? String
        }

        var cookie: HTTPCookie? {
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: name,
                .value: value,
                .domain: domain,
                .path: path
            ]

            if let expiresDate {
                properties[.expires] = expiresDate
            }

            if isSecure {
                properties[.secure] = "TRUE"
            }

            if isHTTPOnly {
                properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE"
            }

            if let sameSitePolicy {
                properties[HTTPCookiePropertyKey("SameSite")] = sameSitePolicy
            }

            return HTTPCookie(properties: properties)
        }
    }
}

extension WKHTTPCookieStore {
    func setCookie(_ cookie: HTTPCookie) async {
        await withCheckedContinuation { continuation in
            setCookie(cookie) {
                continuation.resume()
            }
        }
    }

    func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }
}

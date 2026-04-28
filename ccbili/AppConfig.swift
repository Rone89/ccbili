import Foundation

enum AppConfig {
    static let appName = "ccbili"

    static let webBaseURL = URL(string: "https://www.bilibili.com")!
    static let apiBaseURL = URL(string: "https://api.bilibili.com")!
    static let appBaseURL = URL(string: "https://app.bilibili.com")!
    static let passportBaseURL = URL(string: "https://passport.bilibili.com")!

    static let defaultUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
    static let desktopUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    static let dartUserAgent = "Dart/3.6 (dart:io)"
}

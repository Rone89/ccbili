import Foundation

enum AppSettings {
    static let playbackDiagnosticsEnabledKey = "playbackDiagnosticsEnabled"
    static let preferredPlaybackQualityKey = "preferredPlaybackQuality"
}

enum PlaybackPreferences {
    static var preferredQuality: Int {
        let storedQuality = UserDefaults.standard.integer(forKey: AppSettings.preferredPlaybackQualityKey)
        return storedQuality > 0 ? storedQuality : 112
    }

    static func savePreferredQuality(_ quality: Int) {
        UserDefaults.standard.set(quality, forKey: AppSettings.preferredPlaybackQualityKey)
    }
}

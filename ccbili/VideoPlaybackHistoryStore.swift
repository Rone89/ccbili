import Foundation

struct VideoPlaybackHistory: Codable, Equatable {
    let videoID: String
    let position: Double
    let updatedAt: Date

    var displayText: String {
        let totalSeconds = max(Int(position.rounded(.down)), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

enum VideoPlaybackHistoryStore {
    private static let key = "videoPlaybackHistory"

    static func history(for videoID: String) -> VideoPlaybackHistory? {
        load()[videoID]
    }

    static func save(videoID: String, position: Double) {
        guard position.isFinite, position > 3 else { return }
        var values = load()
        values[videoID] = VideoPlaybackHistory(videoID: videoID, position: position, updatedAt: Date())
        persist(values)
    }

    private static func load() -> [String: VideoPlaybackHistory] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let values = try? JSONDecoder().decode([String: VideoPlaybackHistory].self, from: data) else {
            return [:]
        }
        return values
    }

    private static func persist(_ values: [String: VideoPlaybackHistory]) {
        let sortedValues = values.values
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(200)
        let trimmed = Dictionary(uniqueKeysWithValues: sortedValues.map { ($0.videoID, $0) })
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

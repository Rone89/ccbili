import Foundation

struct VideoPlaybackHistory: Codable, Equatable {
    let videoID: String
    let position: Double
    let updatedAt: Date

    var progressFraction: Double {
        min(max(position, 0), 1)
    }

    var displayText: String {
        "\(Int((progressFraction * 100).rounded()))%"
    }
}

enum VideoPlaybackHistoryStore {
    private static let key = "videoPlaybackHistory"

    static func history(for videoID: String) -> VideoPlaybackHistory? {
        load()[videoID]
    }

    static func histories() -> [String: VideoPlaybackHistory] {
        load()
    }

    static func save(videoID: String, position: Double) {
        guard position.isFinite else { return }
        let progress = min(max(position, 0), 1)
        guard progress >= 0.03 else { return }
        if progress >= 0.98 {
            remove(videoID: videoID)
            return
        }

        var values = load()
        values[videoID] = VideoPlaybackHistory(videoID: videoID, position: progress, updatedAt: Date())
        persist(values)
    }

    static func remove(videoID: String) {
        var values = load()
        values.removeValue(forKey: videoID)
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

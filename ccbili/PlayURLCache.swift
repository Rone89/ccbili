import Foundation

actor PlayURLCache {
    static let shared = PlayURLCache()

    private let service = PlayURLService()
    private let ttl: TimeInterval = 8 * 60
    private var values: [String: Entry] = [:]
    private var tasks: [String: Task<PlayableVideoSource, Error>] = [:]

    func source(bvid: String, cid: Int, preferredQuality: Int? = nil) async throws -> PlayableVideoSource {
        let key = cacheKey(bvid: bvid, cid: cid, preferredQuality: preferredQuality, cookieFingerprint: cookieFingerprint())
        if let entry = values[key], Date().timeIntervalSince(entry.createdAt) < ttl {
            return entry.source
        }
        if let task = tasks[key] {
            return try await task.value
        }

        let task = Task {
            try await service.fetchPlayableSource(
                bvid: bvid,
                cid: cid,
                preferredQuality: preferredQuality
            )
        }
        tasks[key] = task
        do {
            let source = try await task.value
            values[key] = Entry(source: source, createdAt: Date())
            tasks[key] = nil
            return source
        } catch {
            tasks[key] = nil
            throw error
        }
    }

    func warm(bvid: String, cid: Int, preferredQuality: Int? = nil) {
        let key = cacheKey(bvid: bvid, cid: cid, preferredQuality: preferredQuality, cookieFingerprint: cookieFingerprint())
        if let entry = values[key], Date().timeIntervalSince(entry.createdAt) < ttl { return }
        if tasks[key] != nil { return }

        tasks[key] = Task {
            try await service.fetchPlayableSource(
                bvid: bvid,
                cid: cid,
                preferredQuality: preferredQuality
            )
        }
    }

    func remove(bvid: String, cid: Int, preferredQuality: Int? = nil) {
        let key = cacheKey(bvid: bvid, cid: cid, preferredQuality: preferredQuality, cookieFingerprint: cookieFingerprint())
        values[key] = nil
        tasks[key]?.cancel()
        tasks[key] = nil
    }

    func removeAll() {
        values.removeAll()
        for task in tasks.values {
            task.cancel()
        }
        tasks.removeAll()
    }

    private func cacheKey(bvid: String, cid: Int, preferredQuality: Int?, cookieFingerprint: String) -> String {
        "\(bvid)-\(cid)-\(preferredQuality ?? 112)-\(cookieFingerprint)"
    }

    private func cookieFingerprint() -> String {
        guard let cookieHeader = BilibiliCookieStore.cookieHeader(),
              cookieHeader.contains("SESSDATA=") else {
            return "guest"
        }

        return "login-\(cookieHeader.hashValue)"
    }

    private struct Entry {
        let source: PlayableVideoSource
        let createdAt: Date
    }
}

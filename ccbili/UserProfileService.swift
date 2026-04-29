import Foundation

struct UserProfileService {
    struct ArchivePage {
        let videos: [VideoItem]
        let page: Int
        let hasMore: Bool
    }

    func fetchProfile(mid: Int, fallback: SearchUserItem? = nil) async throws -> UserProfile {
        var components = URLComponents(
            url: AppConfig.apiBaseURL.appending(path: "/x/web-interface/card"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "mid", value: String(mid))]

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        let response = try await APIClient.shared.get(url: url, as: UserCardResponseDTO.self)
        guard response.code == 0 else {
            throw APIError.serverMessage(response.message)
        }

        let follower = response.data?.follower ?? 0
        let card = response.data?.card
        return UserProfile(
            mid: mid,
            name: card?.name ?? fallback?.name ?? "未知用户",
            sign: fallback?.sign ?? "这个人还没有签名",
            followerText: "粉丝 \(formattedCount(follower))",
            followingText: "关注数待获取",
            videoText: fallback?.videoText ?? "投稿待获取",
            avatarURL: normalizedImageURL(from: card?.face) ?? fallback?.avatarURL
        )
    }

    func fetchArchive(mid: Int, page: Int = 1) async throws -> ArchivePage {
        var components = URLComponents(
            url: AppConfig.apiBaseURL.appending(path: "/x/space/wbi/arc/search"),
            resolvingAgainstBaseURL: false
        )

        let queryItems = try await WBI.shared.signedQueryItems(from: [
            "mid": String(mid),
            "pn": String(page),
            "ps": "20",
            "order": "pubdate"
        ])
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        let response = try await APIClient.shared.get(url: url, as: UserArchiveResponseDTO.self)
        guard response.code == 0 else {
            throw APIError.serverMessage(response.message)
        }

        let videos = (response.data?.list?.vlist ?? []).compactMap { video -> VideoItem? in
            guard let bvid = video.bvid, !bvid.isEmpty else { return nil }
            let subtitleParts = [video.length, formattedDate(from: video.created)].compactMap { $0 }
            return VideoItem(
                id: bvid,
                title: video.title ?? "未知标题",
                subtitle: subtitleParts.joined(separator: " · "),
                bvid: bvid,
                aid: video.aid,
                cid: nil,
                coverURL: normalizedImageURL(from: video.pic)
            )
        }

        let currentPage = response.data?.page?.pn ?? page
        let pageSize = response.data?.page?.ps ?? 20
        let totalCount = response.data?.page?.count ?? videos.count
        return ArchivePage(videos: videos, page: currentPage, hasMore: currentPage * pageSize < totalCount)
    }

    private func normalizedImageURL(from path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("//") {
            return URL(string: "https:" + path)
        }
        return URL(string: path)
    }

    private func formattedCount(_ value: Int) -> String {
        if value >= 10_000 {
            return String(format: "%.1f万", Double(value) / 10_000)
        }
        return String(value)
    }

    private func formattedDate(from timestamp: Int?) -> String? {
        guard let timestamp else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

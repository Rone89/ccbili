import Foundation

struct SearchService {
    struct SearchPage {
        let items: [VideoItem]
        let page: Int
        let hasMore: Bool
    }

    func searchAll(keyword: String, page: Int = 1) async throws -> [VideoItem] {
        try await searchVideos(keyword: keyword, page: page).items
    }

    func searchVideos(keyword: String, page: Int = 1) async throws -> SearchPage {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return SearchPage(items: [], page: page, hasMore: false)
        }

        var components = URLComponents(
            url: AppConfig.apiBaseURL.appending(path: "/x/web-interface/wbi/search/type"),
            resolvingAgainstBaseURL: false
        )

        let queryItems = try await WBI.shared.signedQueryItems(from: [
            "keyword": trimmed,
            "page": String(page),
            "search_type": "video"
        ])
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        let response = try await APIClient.shared.get(
            url: url,
            as: SearchVideoResponseDTO.self
        )

        guard response.code == 0 else {
            throw APIError.serverMessage(response.message)
        }

        let items = (response.data?.result ?? []).compactMap { result -> VideoItem? in
            guard let bvid = result.bvid, !bvid.isEmpty else {
                return nil
            }

            let cleanTitle = cleanSearchText(result.title ?? "未知标题")

            let subtitleParts = [result.author, result.duration]
                .compactMap { value -> String? in
                    guard let value, !value.isEmpty else { return nil }
                    return cleanSearchText(value)
                }
            let subtitle = subtitleParts.isEmpty ? "未知 UP 主" : subtitleParts.joined(separator: " · ")
            let coverURL = normalizedImageURL(from: result.pic)

            return VideoItem(
                id: bvid,
                title: cleanTitle,
                subtitle: subtitle,
                bvid: bvid,
                aid: result.aid,
                cid: nil,
                coverURL: coverURL
            )
        }

        let currentPage = response.data?.page ?? page
        let numPages = response.data?.numPages ?? currentPage
        return SearchPage(items: items, page: currentPage, hasMore: currentPage < numPages)
    }

    private func cleanSearchText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "<em class=\"keyword\">", with: "")
            .replacingOccurrences(of: "</em>", with: "")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
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

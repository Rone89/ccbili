import Foundation
import Observation
import SwiftUI

@Observable
final class HomeViewModel {
    var items: [VideoItem] = HomeViewModel.placeholderItems
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?
    var recentlyInsertedIDs: Set<String> = []

    private static let placeholderPrefix = "placeholder-home-"

    private static let placeholderItems: [VideoItem] = (0..<6).map { index in
        VideoItem(
            id: "\(placeholderPrefix)\(index)",
            title: "占位标题",
            subtitle: "占位作者",
            bvid: nil,
            aid: nil,
            cid: nil,
            coverURL: nil
        )
    }

    func load(forceRefresh: Bool = false) async {
        if !forceRefresh {
            guard !isLoading else { return }
        }

        guard !isLoadingMore else { return }

        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        do {
            let mapped = try await fetchRecommendations()
            withAnimation(.easeInOut(duration: 0.28)) {
                recentlyInsertedIDs = []
                items = mapped
            }
        } catch APIError.cancelled {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreIfNeeded(currentItem item: VideoItem) async {
        guard !isPlaceholderItem(item) else { return }
        guard let lastID = items.last?.id, item.id == lastID else { return }
        guard !isLoading else { return }
        guard !isLoadingMore else { return }

        isLoadingMore = true
        defer {
            isLoadingMore = false
        }

        do {
            let mapped = try await fetchRecommendations()

            let existingIDs = Set(items.map(\.id))
            let newItems = mapped.filter { !existingIDs.contains($0.id) }

            if !newItems.isEmpty {
                withAnimation(.easeInOut(duration: 0.28)) {
                    items.append(contentsOf: newItems)
                }
            }
        } catch APIError.cancelled {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func isPlaceholderItem(_ item: VideoItem) -> Bool {
        item.id.hasPrefix(Self.placeholderPrefix)
    }

    func warmPlaybackSourceIfNeeded(for item: VideoItem) async {
        guard !isPlaceholderItem(item),
              let bvid = item.resolvedBVID,
              let cid = item.cid else {
            return
        }
        await PlayURLCache.shared.warm(
            bvid: bvid,
            cid: cid,
            preferredQuality: PlaybackPreferences.preferredQuality
        )
    }

    private func fetchRecommendations() async throws -> [VideoItem] {
        var components = URLComponents(
            url: AppConfig.apiBaseURL.appending(path: "/x/web-interface/wbi/index/top/feed/rcmd"),
            resolvingAgainstBaseURL: false
        )

        let queryItems = try await WBI.shared.signedQueryItems(from: [
            "version": "1",
            "feed_version": "V8",
            "homepage_ver": "1",
            "ps": "20",
            "fresh_idx": String(Int.random(in: 1000...999999)),
            "brush": String(Int.random(in: 1000...999999)),
            "fresh_type": "4"
        ])
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        let response = try await APIClient.shared.get(
            url: url,
            as: BiliBaseResponse<HomeRecommendationResponse>.self
        )

        guard response.code == 0 else {
            throw APIError.serverMessage(response.message)
        }

        return response.data?.item.compactMap { item -> VideoItem? in
            guard item.goto == "av" else { return nil }
            guard let bvid = item.bvid, !bvid.isEmpty else { return nil }

            let subtitle = item.owner?.name ?? "未知 UP 主"
            let coverURL = normalizedImageURL(from: item.pic)

            return VideoItem(
                id: bvid,
                title: item.title,
                subtitle: subtitle,
                bvid: bvid,
                aid: item.id,
                cid: nil,
                coverURL: coverURL
            )
        } ?? []
    }

    private func normalizedImageURL(from path: String?) -> URL? {
        guard var path, !path.isEmpty else {
            return nil
        }

        if path.hasPrefix("//") {
            path = "https:" + path
        } else if path.hasPrefix("http://") {
            path = "https://" + path.dropFirst("http://".count)
        }

        guard var components = URLComponents(string: path) else {
            return URL(string: path)
        }

        return components.url
    }
}

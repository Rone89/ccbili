import Foundation
import Observation

@Observable
final class SearchViewModel {
    enum Scope: String, CaseIterable, Identifiable {
        case videos = "视频"
        case users = "用户"

        var id: String { rawValue }
    }

    var keyword = ""
    var scope: Scope = .videos
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?
    var searchHistory: [String] = []
    var results: [VideoItem] = []
    var userResults: [SearchUserItem] = []
    var hasSearched = false
    var canLoadMore = false

    private let searchService = SearchService()
    private let historyKey = "searchKeywordHistory"
    private var currentPage = 0
    private var currentKeyword = ""

    init() {
        loadHistory()
    }

    func search() async {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            results = []
            userResults = []
            hasSearched = false
            canLoadMore = false
            errorMessage = "请输入关键词"
            return
        }

        isLoading = true
        errorMessage = nil
        hasSearched = true
        canLoadMore = false
        currentKeyword = trimmed
        currentPage = 0

        defer {
            isLoading = false
        }

        do {
            switch scope {
            case .videos:
                let page = try await searchService.searchVideos(keyword: trimmed, page: 1)
                results = page.items
                userResults = []
                currentPage = page.page
                canLoadMore = page.hasMore
            case .users:
                let page = try await searchService.searchUsers(keyword: trimmed, page: 1)
                userResults = page.items
                results = []
                currentPage = page.page
                canLoadMore = page.hasMore
            }
            saveHistoryKeyword(trimmed)
        } catch {
            errorMessage = error.localizedDescription
            results = []
            userResults = []
        }
    }

    func loadMoreIfNeeded(currentItem: VideoItem) async {
        guard scope == .videos, currentItem.id == results.last?.id else { return }
        await loadMore()
    }

    func loadMoreUsersIfNeeded(currentItem: SearchUserItem) async {
        guard scope == .users, currentItem.id == userResults.last?.id else { return }
        await loadMore()
    }

    func loadMore() async {
        guard canLoadMore, !isLoading, !isLoadingMore, !currentKeyword.isEmpty else { return }

        isLoadingMore = true
        errorMessage = nil

        defer {
            isLoadingMore = false
        }

        do {
            switch scope {
            case .videos:
                let page = try await searchService.searchVideos(keyword: currentKeyword, page: currentPage + 1)
                let existingIDs = Set(results.map(\.id))
                results.append(contentsOf: page.items.filter { !existingIDs.contains($0.id) })
                currentPage = page.page
                canLoadMore = page.hasMore
            case .users:
                let page = try await searchService.searchUsers(keyword: currentKeyword, page: currentPage + 1)
                let existingIDs = Set(userResults.map(\.id))
                userResults.append(contentsOf: page.items.filter { !existingIDs.contains($0.id) })
                currentPage = page.page
                canLoadMore = page.hasMore
            }
        } catch {
            errorMessage = "更多结果加载失败：\(error.localizedDescription)"
        }
    }

    func applyHistory(_ text: String) {
        keyword = text
    }

    func clearHistory() {
        searchHistory.removeAll()
        UserDefaults.standard.removeObject(forKey: historyKey)
    }

    private func loadHistory() {
        searchHistory = UserDefaults.standard.stringArray(forKey: historyKey) ?? ["动画", "音乐", "游戏"]
    }

    private func saveHistoryKeyword(_ keyword: String) {
        searchHistory.removeAll { $0.caseInsensitiveCompare(keyword) == .orderedSame }
        searchHistory.insert(keyword, at: 0)
        searchHistory = Array(searchHistory.prefix(12))
        UserDefaults.standard.set(searchHistory, forKey: historyKey)
    }
}

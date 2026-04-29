import Foundation
import Observation

@Observable
final class SearchViewModel {
    var keyword = ""
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?
    var searchHistory: [String] = []
    var results: [VideoItem] = []
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
            let page = try await searchService.searchVideos(keyword: trimmed, page: 1)
            results = page.items
            currentPage = page.page
            canLoadMore = page.hasMore
            saveHistoryKeyword(trimmed)
        } catch {
            errorMessage = error.localizedDescription
            results = []
        }
    }

    func loadMoreIfNeeded(currentItem: VideoItem) async {
        guard currentItem.id == results.last?.id else { return }
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
            let page = try await searchService.searchVideos(keyword: currentKeyword, page: currentPage + 1)
            let existingIDs = Set(results.map(\.id))
            results.append(contentsOf: page.items.filter { !existingIDs.contains($0.id) })
            currentPage = page.page
            canLoadMore = page.hasMore
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

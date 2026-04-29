import Foundation
import Observation

@Observable
final class UserProfileViewModel {
    var profile: UserProfile?
    var videos: [VideoItem] = []
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?
    var canLoadMore = false

    private let mid: Int
    private let fallback: SearchUserItem?
    private let service = UserProfileService()
    private var currentPage = 0

    init(mid: Int, fallback: SearchUserItem? = nil) {
        self.mid = mid
        self.fallback = fallback
        if let fallback {
            profile = UserProfile(
                mid: fallback.mid,
                name: fallback.name,
                sign: fallback.sign,
                followerText: fallback.followerText,
                followingText: "关注数待获取",
                videoText: fallback.videoText,
                avatarURL: fallback.avatarURL
            )
        }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        currentPage = 0
        canLoadMore = false

        defer {
            isLoading = false
        }

        do {
            async let loadedProfile = service.fetchProfile(mid: mid, fallback: fallback)
            async let archivePage = service.fetchArchive(mid: mid, page: 1)
            profile = try await loadedProfile
            let page = try await archivePage
            videos = page.videos
            currentPage = page.page
            canLoadMore = page.hasMore
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreIfNeeded(currentItem: VideoItem) async {
        guard currentItem.id == videos.last?.id else { return }
        await loadMore()
    }

    func loadMore() async {
        guard canLoadMore, !isLoading, !isLoadingMore else { return }

        isLoadingMore = true
        errorMessage = nil
        defer {
            isLoadingMore = false
        }

        do {
            let page = try await service.fetchArchive(mid: mid, page: currentPage + 1)
            let existingIDs = Set(videos.map(\.id))
            videos.append(contentsOf: page.videos.filter { !existingIDs.contains($0.id) })
            currentPage = page.page
            canLoadMore = page.hasMore
        } catch {
            errorMessage = "更多投稿加载失败：\(error.localizedDescription)"
        }
    }
}

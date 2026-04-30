import Foundation
import Observation

@Observable
final class VideoDetailViewModel {
    let item: VideoItem

    var isLoading = false
    var isLoadingPlaybackSource = false
    var errorMessage: String?
    var playbackErrorMessage: String?
    var lastUpdatedAt: Date?

    var descriptionText = ""
    var uploadTimeText = "上传时间待接入"
    var author: VideoAuthor?
    var comments: [VideoComment] = []
    var relatedVideos: [RelatedVideo] = []
    var playbackItem: VideoItem
    var playURL: URL?
    var playbackSource: PlayableVideoSource?
    var playbackFallbackMessage: String?
    var stats = VideoInteractionStats()
    var viewerState = VideoViewerInteractionState()

    private let playURLCache = PlayURLCache.shared
    private var playbackSourceTask: Task<Void, Never>?
    private var playbackSourceLoadedAt: Date?

    init(item: VideoItem) {
        self.item = item
        self.playbackItem = item
    }

    var hasLoadedContent: Bool {
        !descriptionText.isEmpty ||
        author != nil ||
        !relatedVideos.isEmpty
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        playbackErrorMessage = nil

        defer {
            isLoading = false
        }

        do {
            guard let bvid = item.resolvedBVID else {
                throw APIError.serverMessage("缺少有效的 bvid")
            }

            let detailURL = try buildDetailURL(bvid: bvid)
            async let detailResponse: BiliBaseResponse<VideoDetailResponseDTO> = APIClient.shared.get(
                url: detailURL,
                as: BiliBaseResponse<VideoDetailResponseDTO>.self
            )

            let relatedURL = try buildRelatedURL(bvid: bvid)
            async let relatedResponse: BiliBaseResponse<[RelatedVideoDTO]> = APIClient.shared.get(
                url: relatedURL,
                as: BiliBaseResponse<[RelatedVideoDTO]>.self
            )

            let detail = try await detailResponse

            guard detail.code == 0 else {
                throw APIError.serverMessage(detail.message)
            }

            guard let detailData = detail.data else {
                throw APIError.invalidResponse
            }

            descriptionText = detailData.desc ?? "暂无简介"
            uploadTimeText = formatUploadTime(from: detailData.pubdate ?? detailData.ctime)
            stats = VideoInteractionStats(stat: detailData.stat)
            viewerState = VideoViewerInteractionState(reqUser: detailData.reqUser)

            let resolvedCID = detailData.cid ?? detailData.pages?.first?.cid
            let ownerMID = detailData.owner?.mid
            let ownerName = detailData.owner?.name ?? "未知 UP 主"
            let ownerFaceURL = normalizedImageURL(from: detailData.owner?.face)

            playbackItem = VideoItem(
                id: detailData.bvid ?? bvid,
                title: detailData.title ?? item.title,
                subtitle: ownerName,
                bvid: detailData.bvid ?? bvid,
                aid: detailData.aid,
                cid: resolvedCID
            )

            preparePlaybackSource(
                bvid: detailData.bvid ?? bvid,
                cid: resolvedCID
            )

            async let loadedAuthor = buildAuthor(
                mid: ownerMID,
                fallbackName: ownerName,
                fallbackAvatarURL: ownerFaceURL
            )

            author = await loadedAuthor

            let related = try await relatedResponse
            if related.code == 0 {
                relatedVideos = (related.data ?? []).prefix(5).compactMap { relatedItem in
                    guard let relatedBVID = relatedItem.bvid, !relatedBVID.isEmpty else {
                        return nil
                    }

                    return RelatedVideo(
                        id: relatedBVID,
                        title: relatedItem.title ?? "未知标题",
                        subtitle: relatedItem.owner?.name ?? "未知 UP 主",
                        coverURL: normalizedImageURL(from: relatedItem.pic)
                    )
                }
            } else {
                relatedVideos = []
            }

            lastUpdatedAt = Date()
        } catch {
            playbackSource = nil
            playURL = nil
            errorMessage = error.localizedDescription
        }
    }

    func preparePlaybackSource(bvid: String? = nil, cid: Int? = nil) {
        playbackSourceTask?.cancel()
        let resolvedBVID = bvid ?? playbackItem.resolvedBVID
        let resolvedCID = cid ?? playbackItem.cid

        guard let resolvedBVID, let resolvedCID else {
            playbackSource = nil
            playURL = nil
            playbackErrorMessage = "缺少 cid，暂时无法播放"
            return
        }

        isLoadingPlaybackSource = true
        playbackErrorMessage = nil
        playbackFallbackMessage = nil

        playbackSourceTask = Task { [playURLCache] in
            do {
                let preferredQuality = PlaybackPreferences.preferredQuality
                let source = try await Self.fetchPlayableSourceWithFallback(
                    bvid: resolvedBVID,
                    cid: resolvedCID,
                    preferredQuality: preferredQuality,
                    playURLCache: playURLCache
                )

                guard !Task.isCancelled else { return }

                await MainActor.run {
                    self.playbackSource = source
                    self.playURL = source.url
                    self.playbackSourceLoadedAt = Date()
                    if source.quality != preferredQuality {
                        self.playbackFallbackMessage = "已自动切换到\(source.qualityDescription ?? "可播放清晰度")"
                    }
                    self.isLoadingPlaybackSource = false
                }
            } catch {
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    self.playbackSource = nil
                    self.playURL = nil
                    self.playbackSourceLoadedAt = nil
                    self.playbackErrorMessage = error.localizedDescription
                    self.isLoadingPlaybackSource = false
                }
            }
        }
    }

    func refreshPlaybackSourceAfterAuthenticationChange() async {
        guard let bvid = playbackItem.resolvedBVID, let cid = playbackItem.cid else { return }
        let sourceAge = playbackSourceLoadedAt.map { Date().timeIntervalSince($0) } ?? .infinity
        let shouldRefreshExpiredSource = sourceAge > 60
        if playbackSource?.quality == PlaybackPreferences.preferredQuality,
           BiliAuthContext.cookieValue(named: "SESSDATA")?.isEmpty == false,
           !shouldRefreshExpiredSource {
            return
        }
        await playURLCache.removeAll()
        preparePlaybackSource(bvid: bvid, cid: cid)
    }

    @MainActor
    func switchPlaybackQuality(to option: VideoQualityOption) async {
        guard option.quality != playbackSource?.quality else { return }
        guard let bvid = playbackItem.resolvedBVID, let cid = playbackItem.cid else {
            playbackErrorMessage = "缺少 cid，暂时无法切换清晰度"
            return
        }

        isLoadingPlaybackSource = true
        playbackErrorMessage = nil
        playbackFallbackMessage = nil

        do {
            let source = try await Self.fetchPlayableSourceWithFallback(
                bvid: bvid,
                cid: cid,
                preferredQuality: option.quality,
                playURLCache: playURLCache
            )

            playbackSource = source
            playURL = source.url
            playbackSourceLoadedAt = Date()
            if let selectedQuality = source.quality {
                PlaybackPreferences.savePreferredQuality(selectedQuality)
            }
            if source.quality != option.quality {
                playbackFallbackMessage = "已自动切换到\(source.qualityDescription ?? "可播放清晰度")"
            }
        } catch {
            playbackErrorMessage = error.localizedDescription
        }

        isLoadingPlaybackSource = false
    }

    private static func fetchPlayableSourceWithFallback(
        bvid: String,
        cid: Int,
        preferredQuality: Int,
        playURLCache: PlayURLCache
    ) async throws -> PlayableVideoSource {
        let candidates = fallbackQualities(startingWith: preferredQuality)
        var lastError: Error?

        for quality in candidates {
            do {
                let source = try await playURLCache.source(
                    bvid: bvid,
                    cid: cid,
                    preferredQuality: quality
                )
                return source
            } catch {
                lastError = error
                await playURLCache.remove(bvid: bvid, cid: cid, preferredQuality: quality)
            }
        }

        throw lastError ?? APIError.serverMessage("未获取到可播放的视频地址")
    }

    private static func fallbackQualities(startingWith preferredQuality: Int) -> [Int] {
        var qualities = [preferredQuality]
        qualities.append(contentsOf: [112, 116, 80, 64, 32, 16].filter { $0 != preferredQuality })
        return qualities
    }

    private func buildDetailURL(bvid: String) throws -> URL {
        var components = URLComponents(
            url: AppConfig.apiBaseURL.appending(path: "/x/web-interface/view"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "bvid", value: bvid)
        ]

        guard let url = components?.url else {
            throw APIError.invalidURL
        }
        return url
    }

    private func buildRelatedURL(bvid: String) throws -> URL {
        var components = URLComponents(
            url: AppConfig.apiBaseURL.appending(path: "/x/web-interface/archive/related"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "bvid", value: bvid)
        ]

        guard let url = components?.url else {
            throw APIError.invalidURL
        }
        return url
    }

    private func buildAuthor(mid: Int?, fallbackName: String, fallbackAvatarURL: URL?) async -> VideoAuthor {
        guard let mid else {
            return VideoAuthor(
                mid: nil,
                name: fallbackName,
                followerText: "粉丝数待获取",
                avatarURL: fallbackAvatarURL
            )
        }

        do {
            var components = URLComponents(
                url: AppConfig.apiBaseURL.appending(path: "/x/web-interface/card"),
                resolvingAgainstBaseURL: false
            )
            components?.queryItems = [
                URLQueryItem(name: "mid", value: String(mid))
            ]

            guard let url = components?.url else {
                throw APIError.invalidURL
            }

            let response = try await APIClient.shared.get(
                url: url,
                as: UserCardResponseDTO.self
            )

            guard response.code == 0 else {
                throw APIError.serverMessage(response.message)
            }

            let follower = response.data?.follower ?? 0
            let face = normalizedImageURL(from: response.data?.card?.face) ?? fallbackAvatarURL

            return VideoAuthor(
                mid: mid,
                name: fallbackName,
                followerText: "粉丝 \(formattedCount(follower))",
                avatarURL: face
            )
        } catch {
            return VideoAuthor(
                mid: mid,
                name: fallbackName,
                followerText: "粉丝数获取失败",
                avatarURL: fallbackAvatarURL
            )
        }
    }

    private func formattedCount(_ value: Int) -> String {
        if value >= 10_000 {
            return String(format: "%.1f万", Double(value) / 10_000)
        }
        return "\(value)"
    }

    private func formatUploadTime(from timestamp: Int?) -> String {
        guard let timestamp else {
            return "上传时间待接入"
        }

        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private func normalizedImageURL(from path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }

        if path.hasPrefix("//") {
            return URL(string: "https:" + path)
        }

        return URL(string: path)
    }
}

struct VideoInteractionStats: Equatable {
    var views: Int?
    var likes: Int?
    var coins: Int?
    var favorites: Int?
    var shares: Int?

    init() {}

    init(stat: VideoDetailStatDTO?) {
        views = stat?.view
        likes = stat?.like
        coins = stat?.coin
        favorites = stat?.favorite
        shares = stat?.share
    }
}

struct VideoViewerInteractionState: Equatable {
    var didLike = false
    var didCoin = false
    var didFavorite = false

    init() {}

    init(reqUser: VideoDetailReqUserDTO?) {
        didLike = (reqUser?.like ?? 0) > 0
        didCoin = (reqUser?.coin ?? 0) > 0
        didFavorite = (reqUser?.favorite ?? 0) > 0
    }
}

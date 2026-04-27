import Foundation

struct VideoQualityOption: Identifiable, Equatable, Hashable {
    let quality: Int
    let description: String

    var id: Int {
        quality
    }
}

struct PlayableVideoSource: Equatable {
    let url: URL
    let audioURL: URL?
    let headers: [String: String]
    let quality: Int?
    let qualityDescription: String?
    let availableQualities: [VideoQualityOption]
    let bvid: String
    let cid: Int
}

struct PlayURLService {
    private let defaultPreferredQuality = 116

    func fetchPlayableSource(
        bvid: String,
        cid: Int,
        preferredQuality: Int? = nil
    ) async throws -> PlayableVideoSource {
        let quality = preferredQuality ?? defaultPreferredQuality
        let referer = "\(AppConfig.webBaseURL.absoluteString)/video/\(bvid)"

        let headers = [
            "Referer": referer,
            "Origin": AppConfig.webBaseURL.absoluteString,
            "User-Agent": AppConfig.defaultUserAgent
        ]

        if let dashSource = try await fetchDASHSource(
            bvid: bvid,
            cid: cid,
            preferredQuality: quality,
            headers: headers
        ) {
            return dashSource
        }

        if let durlSource = try await fetchDURLSource(
            bvid: bvid,
            cid: cid,
            preferredQuality: min(quality, 80),
            headers: headers
        ) {
            return durlSource
        }
        throw APIError.serverMessage("未获取到可播放的视频地址")
    }

    func fetchPlayableURL(bvid: String, cid: Int) async throws -> URL {
        try await fetchPlayableSource(bvid: bvid, cid: cid).url
    }

    private func fetchDASHSource(
        bvid: String,
        cid: Int,
        preferredQuality: Int,
        headers: [String: String]
    ) async throws -> PlayableVideoSource? {
        let data = try await fetchPlayURLData(
            bvid: bvid,
            cid: cid,
            preferredQuality: preferredQuality,
            fnval: "4048",
            headers: headers
        )

        guard let videoURL = bestDashVideoURL(from: data) else {
            return nil
        }

        return PlayableVideoSource(
            url: videoURL,
            audioURL: bestDashAudioURL(from: data),
            headers: headers,
            quality: data.quality,
            qualityDescription: qualityText(from: data),
            availableQualities: qualityOptions(from: data),
            bvid: bvid,
            cid: cid
        )
    }

    private func fetchDURLSource(
        bvid: String,
        cid: Int,
        preferredQuality: Int,
        headers: [String: String]
    ) async throws -> PlayableVideoSource? {
        let data = try await fetchPlayURLData(
            bvid: bvid,
            cid: cid,
            preferredQuality: preferredQuality,
            fnval: "0",
            headers: headers
        )

        if let durlString = data.durl?.first?.url,
           let durlURL = URL(string: durlString) {
            return PlayableVideoSource(
                url: durlURL,
                audioURL: nil,
                headers: headers,
                quality: data.quality,
                qualityDescription: qualityText(from: data),
                availableQualities: qualityOptions(from: data),
                bvid: bvid,
                cid: cid
            )
        }

        return nil
    }

    private func fetchPlayURLData(
        bvid: String,
        cid: Int,
        preferredQuality: Int,
        fnval: String,
        headers: [String: String]
    ) async throws -> PlayURLDataDTO {
        var components = URLComponents(
            url: AppConfig.apiBaseURL.appending(path: "/x/player/wbi/playurl"),
            resolvingAgainstBaseURL: false
        )

        let queryItems = try await WBI.shared.signedQueryItems(from: [
            "bvid": bvid,
            "cid": String(cid),
            "qn": String(preferredQuality),
            "fnval": fnval,
            "fourk": "1",
            "platform": "pc",
            "high_quality": "1",
            "try_look": "1"
        ])

        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        let response = try await APIClient.shared.get(
            url: url,
            headers: headers,
            as: PlayURLResponseDTO.self
        )

        guard response.code == 0, let data = response.data else {
            throw APIError.serverMessage(response.message.isEmpty ? "播放地址获取失败" : response.message)
        }

        return data
    }

    private func bestDashVideoURL(from data: PlayURLDataDTO) -> URL? {
        guard let videos = data.dash?.video, !videos.isEmpty else {
            return nil
        }

        let sortedVideos = videos.sorted { lhs, rhs in
            if (lhs.id ?? 0) != (rhs.id ?? 0) {
                return (lhs.id ?? 0) > (rhs.id ?? 0)
            }

            return (lhs.bandwidth ?? 0) > (rhs.bandwidth ?? 0)
        }

        for video in sortedVideos {
            if let baseURLString = video.baseURL,
               let url = URL(string: baseURLString) {
                return url
            }

            if let backupURLString = video.backupURL?.first,
               let url = URL(string: backupURLString) {
                return url
            }
        }

        return nil
    }

    private func bestDashAudioURL(from data: PlayURLDataDTO) -> URL? {
        guard let audios = data.dash?.audio, !audios.isEmpty else {
            return nil
        }

        let sortedAudios = audios.sorted { lhs, rhs in
            if (lhs.id ?? 0) != (rhs.id ?? 0) {
                return (lhs.id ?? 0) > (rhs.id ?? 0)
            }

            return (lhs.bandwidth ?? 0) > (rhs.bandwidth ?? 0)
        }

        for audio in sortedAudios {
            if let baseURLString = audio.baseURL,
               let url = URL(string: baseURLString) {
                return url
            }

            if let backupURLString = audio.backupURL?.first,
               let url = URL(string: backupURLString) {
                return url
            }
        }

        return nil
    }

    private func qualityOptions(from data: PlayURLDataDTO) -> [VideoQualityOption] {
        guard let acceptQuality = data.acceptQuality, !acceptQuality.isEmpty else {
            if let quality = data.quality {
                return [
                    VideoQualityOption(
                        quality: quality,
                        description: qualityText(for: quality)
                    )
                ]
            }

            return []
        }

        let preferredOrder = [127, 126, 125, 120, 116, 112, 80, 74, 64, 32, 16, 6]
        let sortedQualities = acceptQuality.sorted { lhs, rhs in
            let lhsIndex = preferredOrder.firstIndex(of: lhs) ?? Int.max
            let rhsIndex = preferredOrder.firstIndex(of: rhs) ?? Int.max

            if lhsIndex != rhsIndex {
                return lhsIndex < rhsIndex
            }

            return lhs > rhs
        }

        return sortedQualities.map { quality in
            let index = acceptQuality.firstIndex(of: quality) ?? 0
            let description: String

            if let acceptDescription = data.acceptDescription,
               acceptDescription.indices.contains(index) {
                description = acceptDescription[index]
            } else {
                description = qualityText(for: quality)
            }

            return VideoQualityOption(
                quality: quality,
                description: description
            )
        }
    }

    private func qualityText(from data: PlayURLDataDTO) -> String? {
        if let quality = data.quality,
           let acceptQuality = data.acceptQuality,
           let acceptDescription = data.acceptDescription,
           let index = acceptQuality.firstIndex(of: quality),
           acceptDescription.indices.contains(index) {
            return acceptDescription[index]
        }

        guard let quality = data.quality else {
            return nil
        }

        return qualityText(for: quality)
    }

    private func qualityText(for quality: Int) -> String {
        switch quality {
        case 6:
            return "240P 极速"
        case 16:
            return "360P 流畅"
        case 32:
            return "480P 清晰"
        case 64:
            return "720P 高清"
        case 74:
            return "720P60"
        case 80:
            return "1080P 高清"
        case 112:
            return "1080P+ 高码率"
        case 116:
            return "1080P60"
        case 120:
            return "4K 超清"
        case 125:
            return "HDR"
        case 126:
            return "杜比视界"
        case 127:
            return "8K 超高清"
        default:
            return "清晰度 \(quality)"
        }
    }
}


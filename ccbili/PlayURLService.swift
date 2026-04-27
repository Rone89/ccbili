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
    private let defaultPreferredQuality = 80

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

        if quality <= 80 {
            if let durlSource = try await fetchDURLSource(
                bvid: bvid,
                cid: cid,
                preferredQuality: quality,
                headers: headers
            ) {
                return await sourceByMergingDASHQualities(
                    into: durlSource,
                    bvid: bvid,
                    cid: cid,
                    headers: headers
                )
            }
        }

        if let dashSource = try await fetchDASHSource(
            bvid: bvid,
            cid: cid,
            preferredQuality: quality,
            headers: headers
        ) {
            return dashSource
        }

        if quality > 80 {
            if let durlSource = try await fetchDURLSource(
                bvid: bvid,
                cid: cid,
                preferredQuality: 80,
                headers: headers
            ) {
                return durlSource
            }
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

        guard let video = bestDashVideo(from: data, preferredQuality: preferredQuality) else {
            return nil
        }

        if let audio = bestDashAudio(from: data) {
            guard let videoURL = streamURL(from: video.baseURL, backups: video.backupURL),
                  let audioURL = streamURL(from: audio.baseURL, backups: audio.backupURL) else {
                return nil
            }

            let mergedURL = try await DashRemuxService().remuxToMP4(
                videoURL: videoURL,
                audioURL: audioURL,
                headers: headers,
                bvid: bvid,
                cid: cid,
                quality: data.quality
            )

            return PlayableVideoSource(
                url: mergedURL,
                audioURL: nil,
                headers: headers,
                quality: data.quality,
                qualityDescription: qualityText(from: data),
                availableQualities: qualityOptions(from: data),
                bvid: bvid,
                cid: cid
            )
        }

        guard let videoURL = streamURL(from: video.baseURL, backups: video.backupURL) else {
            return nil
        }

        return PlayableVideoSource(
            url: videoURL,
            audioURL: nil,
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

    private func sourceByMergingDASHQualities(
        into source: PlayableVideoSource,
        bvid: String,
        cid: Int,
        headers: [String: String]
    ) async -> PlayableVideoSource {
        do {
            let dashData = try await fetchPlayURLData(
                bvid: bvid,
                cid: cid,
                preferredQuality: 116,
                fnval: "4048",
                headers: headers
            )
            let mergedQualities = mergedQualityOptions(
                source.availableQualities,
                qualityOptions(from: dashData)
            )

            return PlayableVideoSource(
                url: source.url,
                audioURL: source.audioURL,
                headers: source.headers,
                quality: source.quality,
                qualityDescription: source.qualityDescription,
                availableQualities: mergedQualities,
                bvid: source.bvid,
                cid: source.cid
            )
        } catch {
            return source
        }
    }

    private func mergedQualityOptions(
        _ primary: [VideoQualityOption],
        _ secondary: [VideoQualityOption]
    ) -> [VideoQualityOption] {
        var descriptionsByQuality: [Int: String] = [:]
        for option in primary + secondary {
            descriptionsByQuality[option.quality] = option.description
        }

        let preferredOrder = [127, 126, 125, 120, 116, 112, 80, 74, 64, 32, 16, 6]
        return descriptionsByQuality.keys.sorted { lhs, rhs in
            let lhsIndex = preferredOrder.firstIndex(of: lhs) ?? Int.max
            let rhsIndex = preferredOrder.firstIndex(of: rhs) ?? Int.max

            if lhsIndex != rhsIndex {
                return lhsIndex < rhsIndex
            }

            return lhs > rhs
        }.map { quality in
            VideoQualityOption(
                quality: quality,
                description: descriptionsByQuality[quality] ?? qualityText(for: quality)
            )
        }
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

    private func bestDashVideo(
        from data: PlayURLDataDTO,
        preferredQuality: Int
    ) -> PlayURLDashVideoDTO? {
        guard let videos = data.dash?.video, !videos.isEmpty else {
            return nil
        }

        let matchingVideos = videos.filter { $0.id == preferredQuality }
        let candidates = matchingVideos.isEmpty ? videos : matchingVideos

        let sortedVideos = candidates.sorted { lhs, rhs in
            if (lhs.id ?? 0) != (rhs.id ?? 0) {
                return (lhs.id ?? 0) > (rhs.id ?? 0)
            }

            return (lhs.bandwidth ?? 0) > (rhs.bandwidth ?? 0)
        }

        return sortedVideos.first(where: { streamURL(from: $0.baseURL, backups: $0.backupURL) != nil })
    }

    private func bestDashAudio(from data: PlayURLDataDTO) -> PlayURLDashAudioDTO? {
        guard let audios = data.dash?.audio, !audios.isEmpty else {
            return nil
        }

        let sortedAudios = audios.sorted { lhs, rhs in
            if (lhs.id ?? 0) != (rhs.id ?? 0) {
                return (lhs.id ?? 0) > (rhs.id ?? 0)
            }

            return (lhs.bandwidth ?? 0) > (rhs.bandwidth ?? 0)
        }

        return sortedAudios.first(where: { streamURL(from: $0.baseURL, backups: $0.backupURL) != nil })
    }

    private func streamURL(from baseURL: String?, backups: [String]?) -> URL? {
        if let baseURL, let url = URL(string: baseURL) {
            return url
        }

        if let backupURL = backups?.first(where: { !$0.isEmpty }) {
            return URL(string: backupURL)
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

        let qualities = acceptQuality
        let preferredOrder = [127, 126, 125, 120, 116, 112, 80, 74, 64, 32, 16, 6]
        let sortedQualities = qualities.sorted { lhs, rhs in
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


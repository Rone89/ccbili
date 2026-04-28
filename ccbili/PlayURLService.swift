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
    let isDASHSeparated: Bool
    let duration: TimeInterval?
    let videoInitRange: String?
    let videoIndexRange: String?
    let audioInitRange: String?
    let audioIndexRange: String?
    let bandwidth: Int?
    let width: Int?
    let height: Int?
    let frameRate: String?
    let videoCodec: String?
    let audioCodec: String?
    let headers: [String: String]
    let quality: Int?
    let qualityDescription: String?
    let availableQualities: [VideoQualityOption]
    let debugDescription: String?
    let bvid: String
    let cid: Int
}

struct PlayURLService {
    private let defaultPreferredQuality = 80
    private let qualityFallbackOrder = [112, 116, 80, 74, 64, 32, 16, 6]

    func fetchPlayableSource(
        bvid: String,
        cid: Int,
        preferredQuality: Int? = nil
    ) async throws -> PlayableVideoSource {
        let quality = preferredQuality ?? defaultPreferredQuality
        let referer = "\(AppConfig.webBaseURL.absoluteString)/video/\(bvid)"

        var headers = [
            "Referer": referer,
            "Origin": AppConfig.webBaseURL.absoluteString,
            "User-Agent": AppConfig.desktopUserAgent,
            "Accept-Encoding": "br,gzip"
        ]
        var isLoggedIn = false
        if let cookieHeader = BilibiliCookieStore.cookieHeader() {
            headers["Cookie"] = cookieHeader
            isLoggedIn = cookieHeader.contains("SESSDATA=")
        }

        if quality <= 80 {
            if let durlSource = try await fetchDURLSource(
                bvid: bvid,
                cid: cid,
                preferredQuality: quality,
                shouldTryLook: !isLoggedIn,
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
            shouldTryLook: !isLoggedIn,
            headers: headers
        ) {
            if (dashSource.quality ?? quality) <= 80,
               let durlSource = try await fetchDURLSource(
                bvid: bvid,
                cid: cid,
                preferredQuality: dashSource.quality ?? 80,
                shouldTryLook: !isLoggedIn,
                headers: headers
               ) {
                return await sourceByMergingDASHQualities(
                    into: durlSource,
                    bvid: bvid,
                    cid: cid,
                    headers: headers
                )
            }
            return dashSource
        }

        if quality > 80 {
            if let durlSource = try await fetchDURLSource(
                bvid: bvid,
                cid: cid,
                preferredQuality: 80,
                shouldTryLook: !isLoggedIn,
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

    func fetchPreferredHighQualitySource(bvid: String, cid: Int) async throws -> PlayableVideoSource {
        try await fetchPlayableSource(
            bvid: bvid,
            cid: cid,
            preferredQuality: 112
        )
    }

    private func fetchDASHSource(
        bvid: String,
        cid: Int,
        preferredQuality: Int,
        shouldTryLook: Bool,
        headers: [String: String]
    ) async throws -> PlayableVideoSource? {
        let data = try await fetchPlayURLData(
            bvid: bvid,
            cid: cid,
            preferredQuality: preferredQuality,
            fnval: "4048",
            shouldTryLook: shouldTryLook,
            headers: headers
        )

        guard let video = bestDashVideo(from: data, preferredQuality: preferredQuality) else {
            return nil
        }
        let selectedQuality = video.id ?? data.quality

        if let audio = bestDashAudio(from: data) {
            guard let videoURL = streamURL(from: video.baseURL, backups: video.backupURL),
                  let audioURL = streamURL(from: audio.baseURL, backups: audio.backupURL) else {
                return nil
            }

            return PlayableVideoSource(
                url: videoURL,
                audioURL: audioURL,
                isDASHSeparated: true,
                duration: data.duration.map { TimeInterval($0) / 1000 },
                videoInitRange: video.segmentBase?.initialization,
                videoIndexRange: video.segmentBase?.indexRange,
                audioInitRange: audio.segmentBase?.initialization,
                audioIndexRange: audio.segmentBase?.indexRange,
                bandwidth: video.bandwidth,
                width: video.width,
                height: video.height,
                frameRate: video.frameRate,
                videoCodec: video.codecs,
                audioCodec: audio.codecs,
                headers: headers,
                quality: selectedQuality,
                qualityDescription: selectedQuality.map(qualityText(for:)) ?? qualityText(from: data),
                availableQualities: qualityOptions(from: data),
                debugDescription: playURLDebugDescription(data: data, selectedVideo: video, sourceType: "DASH-to-HLS-local", headers: headers),
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
            isDASHSeparated: false,
            duration: data.duration.map { TimeInterval($0) / 1000 },
            videoInitRange: video.segmentBase?.initialization,
            videoIndexRange: video.segmentBase?.indexRange,
            audioInitRange: nil,
            audioIndexRange: nil,
            bandwidth: video.bandwidth,
            width: video.width,
            height: video.height,
            frameRate: video.frameRate,
            videoCodec: video.codecs,
            audioCodec: nil,
            headers: headers,
            quality: selectedQuality,
            qualityDescription: selectedQuality.map(qualityText(for:)) ?? qualityText(from: data),
            availableQualities: qualityOptions(from: data),
            debugDescription: playURLDebugDescription(data: data, selectedVideo: video, sourceType: "DASH-NoAudio", headers: headers),
            bvid: bvid,
            cid: cid
        )
    }

    private func fetchDURLSource(
        bvid: String,
        cid: Int,
        preferredQuality: Int,
        shouldTryLook: Bool,
        headers: [String: String]
    ) async throws -> PlayableVideoSource? {
        let data = try await fetchPlayURLData(
            bvid: bvid,
            cid: cid,
            preferredQuality: preferredQuality,
            fnval: "0",
            shouldTryLook: shouldTryLook,
            headers: headers
        )

        if let durlString = data.durl?.first?.url,
           let durlURL = URL(string: durlString) {
            return PlayableVideoSource(
                url: durlURL,
                audioURL: nil,
                isDASHSeparated: false,
                duration: data.duration.map { TimeInterval($0) / 1000 },
                videoInitRange: nil,
                videoIndexRange: nil,
                audioInitRange: nil,
                audioIndexRange: nil,
                bandwidth: nil,
                width: nil,
                height: nil,
                frameRate: nil,
                videoCodec: nil,
                audioCodec: nil,
                headers: headers,
                quality: data.quality,
                qualityDescription: qualityText(from: data),
                availableQualities: qualityOptions(from: data),
                debugDescription: playURLDebugDescription(data: data, selectedVideo: nil, sourceType: "DURL", headers: headers),
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
                shouldTryLook: !(headers["Cookie"]?.contains("SESSDATA=") ?? false),
                headers: headers
            )
            let mergedQualities = mergedQualityOptions(
                source.availableQualities,
                qualityOptions(from: dashData)
            )

            return PlayableVideoSource(
                url: source.url,
                audioURL: source.audioURL,
                isDASHSeparated: source.isDASHSeparated,
                duration: source.duration,
                videoInitRange: source.videoInitRange,
                videoIndexRange: source.videoIndexRange,
                audioInitRange: source.audioInitRange,
                audioIndexRange: source.audioIndexRange,
                bandwidth: source.bandwidth,
                width: source.width,
                height: source.height,
                frameRate: source.frameRate,
                videoCodec: source.videoCodec,
                audioCodec: source.audioCodec,
                headers: source.headers,
                quality: source.quality,
                qualityDescription: source.qualityDescription,
                availableQualities: mergedQualities,
                debugDescription: source.debugDescription,
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

        let preferredOrder = [112, 116, 80, 74, 64, 32, 16, 6, 120, 125, 126, 127]
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
        shouldTryLook: Bool,
        headers: [String: String]
    ) async throws -> PlayURLDataDTO {
        do {
            return try await fetchWBIPlayURLData(
                bvid: bvid,
                cid: cid,
                preferredQuality: preferredQuality,
                fnval: fnval,
                shouldTryLook: shouldTryLook,
                headers: headers
            )
        } catch {
            return try await fetchLegacyPlayURLData(
                bvid: bvid,
                cid: cid,
                preferredQuality: preferredQuality,
                fnval: fnval,
                shouldTryLook: shouldTryLook,
                headers: headers
            )
        }
    }

    private func fetchLegacyPlayURLData(
        bvid: String,
        cid: Int,
        preferredQuality: Int,
        fnval: String,
        shouldTryLook: Bool,
        headers: [String: String]
    ) async throws -> PlayURLDataDTO {
        var components = URLComponents(
            url: AppConfig.apiBaseURL.appending(path: "/x/player/playurl"),
            resolvingAgainstBaseURL: false
        )

        var queryItems = [
            URLQueryItem(name: "bvid", value: bvid),
            URLQueryItem(name: "cid", value: String(cid)),
            URLQueryItem(name: "qn", value: String(preferredQuality)),
            URLQueryItem(name: "fnval", value: fnval),
            URLQueryItem(name: "fnver", value: "0"),
            URLQueryItem(name: "otype", value: "json"),
            URLQueryItem(name: "fourk", value: "1"),
            URLQueryItem(name: "platform", value: "pc"),
            URLQueryItem(name: "high_quality", value: "1")
        ]
        if shouldTryLook {
            queryItems.append(URLQueryItem(name: "try_look", value: "1"))
        }

        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        let response = try await APIClient.shared.get(
            url: url,
            headers: headers,
            as: PlayURLResponseDTO.self
        )

        guard response.code == 0, var data = response.data else {
            throw APIError.serverMessage(response.message.isEmpty ? "播放地址获取失败" : response.message)
        }

        data.sourceAPI = "legacy"

        return data
    }

    private func fetchWBIPlayURLData(
        bvid: String,
        cid: Int,
        preferredQuality: Int,
        fnval: String,
        shouldTryLook: Bool,
        headers: [String: String]
    ) async throws -> PlayURLDataDTO {
        var components = URLComponents(
            url: AppConfig.apiBaseURL.appending(path: "/x/player/wbi/playurl"),
            resolvingAgainstBaseURL: false
        )

        var parameters = [
            "bvid": bvid,
            "cid": String(cid),
            "qn": String(preferredQuality),
            "fnval": fnval,
            "fnver": "0",
            "otype": "json",
            "fourk": "1",
            "voice_balance": "1",
            "gaia_source": "pre-load",
            "isGaiaAvoided": "true",
            "web_location": "1315873"
        ]
        if shouldTryLook {
            parameters["try_look"] = "1"
        }

        let queryItems = try await WBI.shared.signedQueryItems(from: parameters)

        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        let response = try await APIClient.shared.get(
            url: url,
            headers: headers,
            as: PlayURLResponseDTO.self
        )

        guard response.code == 0, var data = response.data else {
            throw APIError.serverMessage(response.message.isEmpty ? "播放地址获取失败" : response.message)
        }

        data.sourceAPI = "wbi"

        return data
    }

    private func bestDashVideo(
        from data: PlayURLDataDTO,
        preferredQuality: Int
    ) -> PlayURLDashVideoDTO? {
        guard let videos = data.dash?.video, !videos.isEmpty else {
            return nil
        }

        let availableQualities = Set(videos.compactMap(\.id))
        let selectedQuality = qualityFallbackCandidates(for: preferredQuality)
            .first(where: { availableQualities.contains($0) })
        let candidates = selectedQuality.map { quality in
            videos.filter { $0.id == quality }
        } ?? videos

        let sortedVideos = candidates.sorted { lhs, rhs in
            if (lhs.id ?? 0) != (rhs.id ?? 0) {
                return (lhs.id ?? 0) > (rhs.id ?? 0)
            }

            let lhsCodecPriority = dashCodecPriority(lhs.codecs)
            let rhsCodecPriority = dashCodecPriority(rhs.codecs)
            if lhsCodecPriority != rhsCodecPriority {
                return lhsCodecPriority < rhsCodecPriority
            }

            return (lhs.bandwidth ?? 0) > (rhs.bandwidth ?? 0)
        }

        return sortedVideos.first(where: { streamURL(from: $0.baseURL, backups: $0.backupURL) != nil })
    }

    private func dashCodecPriority(_ codecs: String?) -> Int {
        guard let codecs = codecs?.lowercased() else { return 9 }

        if codecs.hasPrefix("avc1") {
            return 0
        }

        if codecs.hasPrefix("hvc1") || codecs.hasPrefix("hev1") {
            return 1
        }

        if codecs.hasPrefix("av01") {
            return 2
        }

        return 8
    }

    private func qualityFallbackCandidates(for preferredQuality: Int) -> [Int] {
        var candidates = [preferredQuality]
        candidates.append(contentsOf: qualityFallbackOrder.filter { $0 != preferredQuality })
        return candidates
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
        let preferredOrder = [112, 116, 80, 74, 64, 32, 16, 6, 120, 125, 126, 127]
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

    private func playURLDebugDescription(
        data: PlayURLDataDTO,
        selectedVideo: PlayURLDashVideoDTO?,
        sourceType: String,
        headers: [String: String]
    ) -> String {
        let accept = (data.acceptQuality ?? [])
            .map(String.init)
            .joined(separator: ",")
        let dashQualities = (data.dash?.video ?? [])
            .compactMap(\.id)
            .uniqued()
            .map(String.init)
            .joined(separator: ",")
        let selected = selectedVideo?.id.map(String.init) ?? data.quality.map(String.init) ?? "nil"
        let selectedCodec = selectedVideo?.codecs ?? "nil"
        let selectedQualityCodecs = (data.dash?.video ?? [])
            .filter { $0.id == selectedVideo?.id }
            .compactMap(\.codecs)
            .uniqued()
            .joined(separator: "/")
        let resolution = selectedVideo.map { video in
            "\(video.width ?? 0)x\(video.height ?? 0)@\(video.frameRate ?? "?")"
        } ?? "durl"
        let durlCount = data.durl?.count ?? 0

        let cookie = headers["Cookie"] ?? ""
        let cookieFlags = [
            cookie.contains("SESSDATA=") ? "sess" : "noSess",
            cookie.contains("buvid3=") ? "b3" : "noB3",
            cookie.contains("buvid4=") ? "b4" : "noB4"
        ].joined(separator: ",")

        return "\(sourceType)/\(data.sourceAPI ?? "?") selected=\(selected) codec=\(selectedCodec) codecs=[\(selectedQualityCodecs)] res=\(resolution) durl=\(durlCount) cookies=\(cookieFlags) accept=[\(accept)] dash=[\(dashQualities)]"
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

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}


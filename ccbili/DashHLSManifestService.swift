import Foundation

struct DashHLSManifestService {
    func makeManifest(for source: PlayableVideoSource) async throws -> URL {
        try LocalHLSProxyServer.shared.resetForForegroundPlayback()

        guard let audioURL = source.audioURL,
              let videoInitRange = byteRange(from: source.videoInitRange),
              let videoIndexRange = byteRange(from: source.videoIndexRange),
              let audioInitRange = byteRange(from: source.audioInitRange),
              let audioIndexRange = byteRange(from: source.audioIndexRange) else {
            throw APIError.serverMessage("DASH HLS 清单信息不完整")
        }

        async let videoSegments = segments(
            mediaURL: source.url,
            indexRange: videoIndexRange,
            headers: source.headers
        )
        async let audioSegments = segments(
            mediaURL: audioURL,
            indexRange: audioIndexRange,
            headers: source.headers
        )
        let parsedVideoSegments = try await videoSegments
        let parsedAudioSegments = try await audioSegments
        guard !parsedVideoSegments.isEmpty, !parsedAudioSegments.isEmpty else {
            throw APIError.serverMessage("DASH HLS 分片索引为空")
        }
        HLSPlaybackDiagnostics.shared.recordManifest(
            videoSegments: parsedVideoSegments.count,
            audioSegments: parsedAudioSegments.count,
            targetDuration: max(1, Int(ceil(parsedVideoSegments.map(\.duration).max() ?? 1))),
            videoIndex: source.videoIndexRange,
            audioIndex: source.audioIndexRange
        )

        let proxiedVideoURL = try LocalHLSProxyServer.shared.register(
            mediaURL: source.url,
            headers: source.headers,
            mode: .redirect
        )
        let proxiedAudioURL = try LocalHLSProxyServer.shared.register(
            mediaURL: audioURL,
            headers: source.headers,
            mode: .redirect
        )

        let videoPlaylistURL = try LocalHLSProxyServer.shared.reservePlaylistURL(name: "video.m3u8")
        let audioPlaylistURL = try LocalHLSProxyServer.shared.reservePlaylistURL(name: "audio.m3u8")
        let manifests = manifestSet(
            source: source,
            proxiedVideoURL: proxiedVideoURL,
            videoInitRange: videoInitRange,
            videoSegments: parsedVideoSegments,
            proxiedAudioURL: proxiedAudioURL,
            audioInitRange: audioInitRange,
            audioSegments: parsedAudioSegments,
            videoPlaylistURL: videoPlaylistURL,
            audioPlaylistURL: audioPlaylistURL
        )
        LocalHLSProxyServer.shared.registerPlaylist(manifests.videoPlaylist, for: videoPlaylistURL)
        LocalHLSProxyServer.shared.registerPlaylist(manifests.audioPlaylist, for: audioPlaylistURL)
        let masterURL = try LocalHLSProxyServer.shared.registerPlaylist(manifests.masterPlaylist, name: "master.m3u8")
        prefetchStartupRanges(
            videoURL: proxiedVideoURL,
            videoInitRange: videoInitRange,
            videoSegments: parsedVideoSegments,
            audioURL: proxiedAudioURL,
            audioInitRange: audioInitRange,
            audioSegments: parsedAudioSegments
        )
        try await LocalHLSProxyServer.shared.waitUntilReady()
        return masterURL
    }

    private func segments(mediaURL: URL, indexRange: ByteRange, headers: [String: String]) async throws -> [HLSSegment] {
        let data = try await rangeData(from: mediaURL, range: indexRange, headers: headers)
        return try SIDXParser().parse(data: data, mediaOffset: indexRange.offset + indexRange.length)
    }

    private func rangeData(from url: URL, range: ByteRange, headers: [String: String]) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        for (key, value) in enrichedHeaders(headers) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("bytes=\(range.offset)-\(range.offset + range.length - 1)", forHTTPHeaderField: "Range")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.serverMessage("DASH HLS 索引段下载失败")
        }
        return data
    }

    private func enrichedHeaders(_ headers: [String: String]) -> [String: String] {
        var result = headers
        let cookies = HTTPCookieStorage.shared.cookies ?? []
        if let cookieHeader = HTTPCookie.requestHeaderFields(with: cookies)["Cookie"], !cookieHeader.isEmpty {
            result["Cookie"] = cookieHeader
        }
        result["Accept"] = "*/*"
        return result
    }

    private func manifestSet(
        source: PlayableVideoSource,
        proxiedVideoURL: URL,
        videoInitRange: ByteRange,
        videoSegments: [HLSSegment],
        proxiedAudioURL: URL,
        audioInitRange: ByteRange,
        audioSegments: [HLSSegment],
        videoPlaylistURL: URL,
        audioPlaylistURL: URL
    ) -> BilibiliDASHHLSManifestSet {
        let codecs = [source.videoCodec, source.audioCodec]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: ",")

        return generateBilibiliDASHMasterManifest(
            videoInitUrl: proxiedVideoURL.absoluteString,
            videoInitByteRange: DASHHLSByteRange(offset: videoInitRange.offset, length: videoInitRange.length),
            videoSegments: hlsSegments(from: videoSegments, mediaURL: proxiedVideoURL),
            audioInitUrl: proxiedAudioURL.absoluteString,
            audioInitByteRange: DASHHLSByteRange(offset: audioInitRange.offset, length: audioInitRange.length),
            audioSegments: hlsSegments(from: audioSegments, mediaURL: proxiedAudioURL),
            bandwidth: source.bandwidth ?? 2_000_000,
            codecs: source.videoCodec ?? codecs,
            audioCodec: source.audioCodec,
            videoPlaylistURL: videoPlaylistURL,
            audioPlaylistURL: audioPlaylistURL,
            videoQuality: videoQualityText(for: source),
            resolution: resolutionText(width: source.width, height: source.height),
            frameRate: normalizedFrameRate(source.frameRate)
        )
    }

    private func hlsSegments(from segments: [HLSSegment], mediaURL: URL) -> [DASHHLSSegment] {
        segments.map { segment in
            DASHHLSSegment(
                url: mediaURL.absoluteString,
                duration: segment.duration,
                byteRange: DASHHLSByteRange(offset: segment.range.offset, length: segment.range.length)
            )
        }
    }

    private func prefetchStartupRanges(
        videoURL: URL,
        videoInitRange: ByteRange,
        videoSegments: [HLSSegment],
        audioURL: URL,
        audioInitRange: ByteRange,
        audioSegments: [HLSSegment]
    ) {
        LocalHLSProxyServer.shared.prefetch(mediaURL: videoURL, rangeHeader: rangeHeader(for: videoInitRange))
        LocalHLSProxyServer.shared.prefetch(mediaURL: audioURL, rangeHeader: rangeHeader(for: audioInitRange))
        if let firstVideoSegment = videoSegments.first {
            LocalHLSProxyServer.shared.prefetch(mediaURL: videoURL, rangeHeader: rangeHeader(for: firstVideoSegment.range))
        }
        if let firstAudioSegment = audioSegments.first {
            LocalHLSProxyServer.shared.prefetch(mediaURL: audioURL, rangeHeader: rangeHeader(for: firstAudioSegment.range))
        }
    }

    private func rangeHeader(for range: ByteRange) -> String {
        "bytes=\(range.offset)-\(range.offset + range.length - 1)"
    }

    private func byteRange(from text: String?) -> ByteRange? {
        guard let text else { return nil }
        let parts = text.split(separator: "-").compactMap { Int64($0) }
        guard parts.count == 2, parts[1] >= parts[0] else { return nil }
        return ByteRange(offset: parts[0], length: parts[1] - parts[0] + 1)
    }

    private func resolutionText(width: Int?, height: Int?) -> String? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return "\(width)x\(height)"
    }

    private func normalizedFrameRate(_ value: String?) -> String? {
        guard let value, let doubleValue = Double(value), doubleValue > 0 else { return nil }
        return String(format: "%.3f", doubleValue)
    }

    private func videoQualityText(for source: PlayableVideoSource) -> String {
        if let qualityDescription = source.qualityDescription {
            return qualityDescription
        }
        switch source.quality {
        case 125:
            return "HDR"
        case 126:
            return "DolbyVision"
        case 120:
            return "4K"
        default:
            return "SDR"
        }
    }

}

private struct ByteRange {
    let offset: Int64
    let length: Int64
}

private struct HLSSegment {
    let range: ByteRange
    let duration: TimeInterval
}

private struct SIDXParser {
    func parse(data: Data, mediaOffset: Int64) throws -> [HLSSegment] {
        var reader = DataReader(data: data)
        guard reader.readUInt32() == data.count else {
            throw APIError.serverMessage("DASH HLS sidx size 异常")
        }
        guard reader.readString(length: 4) == "sidx" else {
            throw APIError.serverMessage("DASH HLS 缺少 sidx")
        }
        let versionAndFlags = reader.readUInt32()
        let version = UInt8((versionAndFlags >> 24) & 0xff)
        _ = reader.readUInt32()
        let timescale = reader.readUInt32()
        guard timescale > 0 else {
            throw APIError.serverMessage("DASH HLS timescale 异常")
        }

        let firstOffset: UInt64
        if version == 0 {
            _ = reader.readUInt32()
            firstOffset = UInt64(reader.readUInt32())
        } else {
            _ = reader.readUInt64()
            firstOffset = reader.readUInt64()
        }

        _ = reader.readUInt16()
        let referenceCount = Int(reader.readUInt16())
        var offset = mediaOffset + Int64(firstOffset)
        var segments: [HLSSegment] = []
        segments.reserveCapacity(referenceCount)

        for _ in 0..<referenceCount {
            let reference = reader.readUInt32()
            let referenceType = (reference >> 31) & 0x1
            let size = Int64(reference & 0x7fffffff)
            let subsegmentDuration = reader.readUInt32()
            _ = reader.readUInt32()
            guard referenceType == 0, size > 0 else { continue }
            segments.append(
                HLSSegment(
                    range: ByteRange(offset: offset, length: size),
                    duration: TimeInterval(subsegmentDuration) / TimeInterval(timescale)
                )
            )
            offset += size
        }
        return segments
    }
}

private struct DataReader {
    private let data: Data
    private var offset = 0

    init(data: Data) {
        self.data = data
    }

    mutating func readUInt16() -> UInt16 {
        let value = data[offset..<offset + 2].reduce(UInt16(0)) { ($0 << 8) | UInt16($1) }
        offset += 2
        return value
    }

    mutating func readUInt32() -> UInt32 {
        let value = data[offset..<offset + 4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        offset += 4
        return value
    }

    mutating func readUInt64() -> UInt64 {
        let value = data[offset..<offset + 8].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        offset += 8
        return value
    }

    mutating func readString(length: Int) -> String {
        let subdata = data[offset..<offset + length]
        offset += length
        return String(data: subdata, encoding: .ascii) ?? ""
    }
}

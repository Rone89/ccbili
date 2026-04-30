import Foundation

struct DASHHLSSegment {
    let url: String
    let duration: Double
    let byteRange: DASHHLSByteRange?

    init(url: String, duration: Double, byteRange: DASHHLSByteRange? = nil) {
        self.url = url
        self.duration = duration
        self.byteRange = byteRange
    }
}

struct DASHHLSByteRange {
    let offset: Int64
    let length: Int64
}

struct HLSManifestVariant {
    let playlistURL: URL
    let bandwidth: Int
    let resolution: String?
    let frameRate: String?
    let codecs: String?
    let videoQuality: String
}

struct BilibiliDASHHLSManifestSet {
    let masterPlaylist: String
    let videoPlaylist: String
    let audioPlaylist: String
}

func generateHLSManifest(
    initUrl: String,
    segments: [DASHHLSSegment],
    videoQuality: String
) -> String {
    generateHLSManifest(
        initUrl: initUrl,
        initByteRange: nil,
        segments: segments,
        videoQuality: videoQuality
    )
}

func generateHLSManifest(
    initUrl: String,
    initByteRange: DASHHLSByteRange?,
    segments: [DASHHLSSegment],
    videoQuality: String
) -> String {
    let escapedInitURL = escapedAbsoluteURL(initUrl)
    let targetDuration = max(1, Int(ceil(segments.map(\.duration).max() ?? 1)))
    var mapTag = "#EXT-X-MAP:URI=\"\(escapedInitURL)\""
    if let initByteRange {
        mapTag += ",BYTERANGE=\"\(initByteRange.length)@\(initByteRange.offset)\""
    }

    var lines: [String] = []
    lines.reserveCapacity(segments.count * 3 + 8)
    lines.append("#EXTM3U")
    lines.append("#EXT-X-VERSION:7")
    lines.append("#EXT-X-PLAYLIST-TYPE:VOD")
    lines.append("#EXT-X-TARGETDURATION:\(targetDuration)")
    lines.append("#EXT-X-MEDIA-SEQUENCE:0")
    lines.append("#EXT-X-INDEPENDENT-SEGMENTS")
    lines.append("#EXT-X-START:TIME-OFFSET=0,PRECISE=YES")
    lines.append(mapTag)

    for segment in segments where segment.duration > 0 {
        lines.append("#EXTINF:\(String(format: "%.6f", segment.duration)),")
        if let byteRange = segment.byteRange {
            lines.append("#EXT-X-BYTERANGE:\(byteRange.length)@\(byteRange.offset)")
        }
        lines.append(escapedAbsoluteURL(segment.url))
    }

    lines.append("#EXT-X-ENDLIST")
    return lines.joined(separator: "\n") + "\n"
}

func generateBilibiliDASHMasterManifest(
    videoInitUrl: String,
    videoSegments: [DASHHLSSegment],
    audioInitUrl: String,
    audioSegments: [DASHHLSSegment],
    bandwidth: Int,
    codecs: String,
    audioCodec: String? = "mp4a.40.2",
    videoPlaylistURL: URL,
    audioPlaylistURL: URL,
    videoQuality: String = "SDR",
    resolution: String? = nil,
    frameRate: String? = nil
) -> BilibiliDASHHLSManifestSet {
    let videoPlaylist = generateHLSManifest(
        initUrl: videoInitUrl,
        segments: videoSegments,
        videoQuality: videoQuality
    )
    let audioPlaylist = generateHLSManifest(
        initUrl: audioInitUrl,
        segments: audioSegments,
        videoQuality: "SDR"
    )
    let masterPlaylist = generateHLSMasterManifest(
        audioPlaylistURL: audioPlaylistURL,
        videoVariant: HLSManifestVariant(
            playlistURL: videoPlaylistURL,
            bandwidth: bandwidth,
            resolution: resolution,
            frameRate: frameRate,
            codecs: hlsCodecs(videoCodecs: codecs, audioCodec: audioCodec),
            videoQuality: videoQuality
        )
    )

    return BilibiliDASHHLSManifestSet(
        masterPlaylist: masterPlaylist,
        videoPlaylist: videoPlaylist,
        audioPlaylist: audioPlaylist
    )
}

func generateBilibiliDASHMasterManifest(
    videoInitUrl: String,
    videoInitByteRange: DASHHLSByteRange?,
    videoSegments: [DASHHLSSegment],
    audioInitUrl: String,
    audioInitByteRange: DASHHLSByteRange?,
    audioSegments: [DASHHLSSegment],
    bandwidth: Int,
    codecs: String,
    audioCodec: String? = "mp4a.40.2",
    videoPlaylistURL: URL,
    audioPlaylistURL: URL,
    videoQuality: String = "SDR",
    resolution: String? = nil,
    frameRate: String? = nil
) -> BilibiliDASHHLSManifestSet {
    let videoPlaylist = generateHLSManifest(
        initUrl: videoInitUrl,
        initByteRange: videoInitByteRange,
        segments: videoSegments,
        videoQuality: videoQuality
    )
    let audioPlaylist = generateHLSManifest(
        initUrl: audioInitUrl,
        initByteRange: audioInitByteRange,
        segments: audioSegments,
        videoQuality: "SDR"
    )
    let masterPlaylist = generateHLSMasterManifest(
        audioPlaylistURL: audioPlaylistURL,
        videoVariant: HLSManifestVariant(
            playlistURL: videoPlaylistURL,
            bandwidth: bandwidth,
            resolution: resolution,
            frameRate: frameRate,
            codecs: hlsCodecs(videoCodecs: codecs, audioCodec: audioCodec),
            videoQuality: videoQuality
        )
    )

    return BilibiliDASHHLSManifestSet(
        masterPlaylist: masterPlaylist,
        videoPlaylist: videoPlaylist,
        audioPlaylist: audioPlaylist
    )
}

func generateHLSMasterManifest(
    audioPlaylistURL: URL,
    videoVariant: HLSManifestVariant
) -> String {
    let audioGroupID = "audio_group"
    var streamInfo = "BANDWIDTH=\(max(videoVariant.bandwidth, 256_000)),AUDIO=\"\(audioGroupID)\""
    if let resolution = videoVariant.resolution { streamInfo += ",RESOLUTION=\(resolution)" }
    if let frameRate = videoVariant.frameRate { streamInfo += ",FRAME-RATE=\(frameRate)" }
    if let codecs = videoVariant.codecs, !codecs.isEmpty { streamInfo += ",CODECS=\"\(codecs)\"" }
    if let videoRange = hlsVideoRange(for: videoVariant.videoQuality) {
        streamInfo += ",VIDEO-RANGE=\(videoRange)"
    }

    return """
    #EXTM3U
    #EXT-X-VERSION:7
    #EXT-X-INDEPENDENT-SEGMENTS
    #EXT-X-START:TIME-OFFSET=0,PRECISE=YES
    #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="\(audioGroupID)",NAME="Bilibili Audio",DEFAULT=YES,AUTOSELECT=YES,URI="\(escapedAbsoluteURL(audioPlaylistURL.absoluteString))"
    #EXT-X-STREAM-INF:\(streamInfo)
    \(escapedAbsoluteURL(videoVariant.playlistURL.absoluteString))
    """
}

private func hlsVideoRange(for videoQuality: String) -> String? {
    let normalized = videoQuality.lowercased()
    if normalized.contains("dolbyvision")
        || normalized.contains("dolby")
        || normalized.contains("hdr")
        || normalized.contains("pq")
        || normalized.contains("杜比")
        || normalized.contains("视界")
        || normalized.contains("高动态") {
        return "PQ"
    }
    return nil
}

private func hlsCodecs(videoCodecs: String, audioCodec: String?) -> String? {
    var codecs = videoCodecs
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    if let audioCodec = audioCodec?.trimmingCharacters(in: .whitespacesAndNewlines),
       !audioCodec.isEmpty,
       !codecs.contains(where: isAudioCodec) {
        codecs.append(audioCodec)
    }

    return codecs.isEmpty ? nil : codecs.joined(separator: ",")
}

private func isAudioCodec(_ codec: String) -> Bool {
    let normalized = codec.lowercased()
    return normalized.hasPrefix("mp4a")
        || normalized.hasPrefix("ac-3")
        || normalized.hasPrefix("ec-3")
        || normalized.hasPrefix("alac")
        || normalized.hasPrefix("opus")
}

private func escapedAbsoluteURL(_ value: String) -> String {
    guard let url = URL(string: value), url.scheme != nil else {
        preconditionFailure("HLS manifest URL must be absolute: \(value)")
    }
    return url.absoluteString.replacingOccurrences(of: "\"", with: "%22")
}

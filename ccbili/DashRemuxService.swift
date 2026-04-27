import AVFoundation
import Foundation

struct DashRemuxService {
    func remuxToMP4(
        videoURL: URL,
        audioURL: URL,
        headers: [String: String],
        bvid: String,
        cid: Int,
        quality: Int?
    ) async throws -> URL {
        let directory = try workingDirectory(bvid: bvid, cid: cid, quality: quality)
        let outputURL = directory.appendingPathComponent("merged.mp4")
        if FileManager.default.fileExists(atPath: outputURL.path) {
            return outputURL
        }

        let videoFile = directory.appendingPathComponent("video.mp4")
        let audioFile = directory.appendingPathComponent("audio.m4a")

        async let videoDownload: Void = downloadIfNeeded(from: videoURL, to: videoFile, headers: headers)
        async let audioDownload: Void = downloadIfNeeded(from: audioURL, to: audioFile, headers: headers)
        _ = try await (videoDownload, audioDownload)

        return try await merge(videoFile: videoFile, audioFile: audioFile, outputURL: outputURL)
    }

    private func workingDirectory(bvid: String, cid: Int, quality: Int?) throws -> URL {
        let qualityValue = quality.map(String.init) ?? "auto"
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let directory = caches
            .appendingPathComponent("DashRemux", isDirectory: true)
            .appendingPathComponent("\(bvid)-\(cid)-\(qualityValue)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func downloadIfNeeded(from url: URL, to destination: URL, headers: [String: String]) async throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        for (key, value) in enrichedHeaders(headers) {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.serverMessage("DASH 分离流下载失败")
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
    }

    private func enrichedHeaders(_ headers: [String: String]) -> [String: String] {
        var result = headers
        let cookies = HTTPCookieStorage.shared.cookies ?? []
        if let cookieHeader = HTTPCookie.requestHeaderFields(with: cookies)["Cookie"], !cookieHeader.isEmpty {
            result["Cookie"] = cookieHeader
        }
        result["Accept"] = "*/*"
        result["Connection"] = "keep-alive"
        return result
    }

    private func merge(videoFile: URL, audioFile: URL, outputURL: URL) async throws -> URL {
        let videoAsset = AVURLAsset(url: videoFile)
        let audioAsset = AVURLAsset(url: audioFile)
        let composition = AVMutableComposition()

        guard let sourceVideoTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
              let compositionVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            throw APIError.serverMessage("DASH 视频轨读取失败")
        }

        let videoTimeRange = try await sourceVideoTrack.load(.timeRange)
        try compositionVideoTrack.insertTimeRange(videoTimeRange, of: sourceVideoTrack, at: .zero)
        compositionVideoTrack.preferredTransform = try await sourceVideoTrack.load(.preferredTransform)

        guard let sourceAudioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first,
              let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            throw APIError.serverMessage("DASH 音频轨读取失败")
        }

        let audioTimeRange = try await sourceAudioTrack.load(.timeRange)
        let audioDuration = CMTimeCompare(audioTimeRange.duration, videoTimeRange.duration) < 0
            ? audioTimeRange.duration
            : videoTimeRange.duration
        try compositionAudioTrack.insertTimeRange(
            CMTimeRange(start: audioTimeRange.start, duration: audioDuration),
            of: sourceAudioTrack,
            at: .zero
        )

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw APIError.serverMessage("DASH 合流导出器创建失败")
        }

        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true

        try await exporter.exportAsync()
        return outputURL
    }
}

private extension AVAssetExportSession {
    func exportAsync() async throws {
        try await withCheckedThrowingContinuation { continuation in
            exportAsynchronously {
                switch self.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    continuation.resume(throwing: self.error ?? APIError.serverMessage("DASH 合流导出失败"))
                default:
                    continuation.resume(throwing: APIError.serverMessage("DASH 合流状态异常"))
                }
            }
        }
    }
}

import AVFoundation
import FFmpegKit
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
        let outputURL = directory.appendingPathComponent("merged-v2.mp4")
        if isPlayableFile(outputURL) {
            return outputURL
        }
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let videoFile = directory.appendingPathComponent("video.mp4")
        let audioFile = try sharedAudioFile(bvid: bvid, cid: cid)

        async let videoDownload: Void = downloadIfNeeded(from: videoURL, to: videoFile, headers: headers)
        async let audioDownload: Void = downloadIfNeeded(from: audioURL, to: audioFile, headers: headers)
        _ = try await (videoDownload, audioDownload)

        do {
            return try await ffmpegMerge(videoFile: videoFile, audioFile: audioFile, outputURL: outputURL)
        } catch {
            print("FFmpeg DASH merge failed: \(error.localizedDescription)")
            return try await merge(videoFile: videoFile, audioFile: audioFile, outputURL: outputURL)
        }
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

    private func sharedAudioFile(bvid: String, cid: Int) throws -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let directory = caches
            .appendingPathComponent("DashRemux", isDirectory: true)
            .appendingPathComponent("\(bvid)-\(cid)-audio", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("audio.m4a")
    }

    private func downloadIfNeeded(from url: URL, to destination: URL, headers: [String: String]) async throws {
        if isPlayableFile(destination) {
            return
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
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

        try FileManager.default.moveItem(at: temporaryURL, to: destination)
    }

    private func isPlayableFile(_ url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return false
        }
        return size.intValue > 1024
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

    private func ffmpegMerge(videoFile: URL, audioFile: URL, outputURL: URL) async throws -> URL {
        let temporaryOutputURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent("merged-\(UUID().uuidString)-ffmpeg.mp4")
        if FileManager.default.fileExists(atPath: temporaryOutputURL.path) {
            try FileManager.default.removeItem(at: temporaryOutputURL)
        }

        let arguments = [
            "ffmpeg",
            "-y",
            "-i", videoFile.path,
            "-i", audioFile.path,
            "-map", "0:v:0",
            "-map", "1:a:0",
            "-c:v", "copy",
            "-c:a", "copy",
            "-shortest",
            temporaryOutputURL.path
        ]

        try await runFFmpeg(arguments)
        guard isPlayableFile(temporaryOutputURL) else {
            throw APIError.serverMessage("DASH FFmpeg 合流输出为空")
        }
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        try FileManager.default.moveItem(at: temporaryOutputURL, to: outputURL)
        return outputURL
    }

    private func runFFmpeg(_ arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .utility) {
                var cStrings = arguments.map { strdup($0) }
                defer {
                    for pointer in cStrings {
                        free(pointer)
                    }
                }

                var argv = cStrings.map { UnsafeMutablePointer<CChar>?($0) }
                let returnCode = ffmpeg_execute(Int32(argv.count), &argv)
                if returnCode == 0 {
                    continuation.resume()
                    return
                }

                continuation.resume(throwing: APIError.serverMessage("DASH FFmpeg 合流失败 \(returnCode)"))
            }
        }
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

        let temporaryOutputURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent("merged-\(UUID().uuidString).mp4")

        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw APIError.serverMessage("DASH 合流导出器创建失败")
        }

        exporter.outputURL = temporaryOutputURL
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true

        try await exporter.exportAsync()
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        try FileManager.default.moveItem(at: temporaryOutputURL, to: outputURL)
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

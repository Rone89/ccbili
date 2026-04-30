//
//  RemoteImageView.swift
//  ccbili
//
//  Created by chuzu  on 2026/4/25.
//

import SwiftUI
import ImageIO
import UIKit

struct RemoteImageView<Placeholder: View, FailureView: View>: View {
    let url: URL?
    let maxPixelLength: CGFloat
    @ViewBuilder let placeholder: () -> Placeholder
    let failureView: (String) -> FailureView

    @State private var image: UIImage?
    @State private var phase: Phase = .idle
    @State private var errorText = "图片加载失败"

    private enum Phase {
        case idle
        case loading
        case success
        case failure
    }

    init(
        url: URL?,
        maxPixelLength: CGFloat = 900,
        @ViewBuilder placeholder: @escaping () -> Placeholder,
        @ViewBuilder failureView: @escaping (String) -> FailureView
    ) {
        self.url = url
        self.maxPixelLength = maxPixelLength
        self.placeholder = placeholder
        self.failureView = failureView
    }

    var body: some View {
        Group {
            switch phase {
            case .success:
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    failureView(errorText)
                }

            case .failure:
                failureView(errorText)

            case .idle, .loading:
                placeholder()
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }

    @MainActor
    private func loadImage() async {
        guard let url else {
            errorText = "图片地址为空"
            phase = .failure
            return
        }

        if case .loading = phase {
            return
        }

        image = nil
        errorText = "图片加载失败"
        phase = .loading

        do {
            let loadedImage = try await RemoteImagePipeline.shared.image(
                from: url,
                maxPixelLength: maxPixelLength
            )

            guard !Task.isCancelled else {
                return
            }

            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                image = loadedImage
                phase = .success
            }
        } catch is CancellationError {
        } catch {
            errorText = error.localizedDescription
            phase = .failure
        }
    }
}

private final class RemoteImagePipeline {
    static let shared = RemoteImagePipeline()

    private let session: URLSession
    private let imageCache = NSCache<NSString, UIImage>()

    private init() {
        var configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 15
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.urlCache = URLCache(
            memoryCapacity: 80 * 1024 * 1024,
            diskCapacity: 300 * 1024 * 1024,
            diskPath: "ccbili-image-cache"
        )

        session = URLSession(configuration: configuration)
        imageCache.countLimit = 260
        imageCache.totalCostLimit = 80 * 1024 * 1024
    }

    func image(from originalURL: URL, maxPixelLength: CGFloat) async throws -> UIImage {
        let originalCacheKey = cacheKey(for: originalURL, maxPixelLength: maxPixelLength)
        if let cachedImage = imageCache.object(forKey: originalCacheKey) {
            return cachedImage
        }

        var lastError: Error?
        for candidateURL in imageCandidateURLs(from: originalURL) {
            do {
                let candidateCacheKey = cacheKey(for: candidateURL, maxPixelLength: maxPixelLength)
                if let cachedImage = imageCache.object(forKey: candidateCacheKey) {
                    imageCache.setObject(cachedImage, forKey: originalCacheKey, cost: cacheCost(for: cachedImage))
                    return cachedImage
                }

                var request = URLRequest(url: candidateURL)
                request.setValue(AppConfig.defaultUserAgent, forHTTPHeaderField: "User-Agent")
                request.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")
                request.cachePolicy = .returnCacheDataElseLoad
                request.setValue("image/avif,image/webp,image/apng,image/jpeg,image/png,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")

                let (data, response) = try await session.data(for: request)
                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode) {
                    lastError = APIError.invalidStatusCode(httpResponse.statusCode)
                    continue
                }

                guard response is HTTPURLResponse else {
                    lastError = APIError.invalidResponse
                    continue
                }

                let decodedImage = try await decodeImage(from: data, maxPixelLength: maxPixelLength)
                let cost = cacheCost(for: decodedImage)
                imageCache.setObject(decodedImage, forKey: candidateCacheKey, cost: cost)
                imageCache.setObject(decodedImage, forKey: originalCacheKey, cost: cost)
                return decodedImage
            } catch {
                lastError = error
            }
        }
        throw lastError ?? APIError.invalidResponse
    }

    private func decodeImage(from data: Data, maxPixelLength: CGFloat) async throws -> UIImage {
        try await Task.detached(priority: .utility) {
            let sourceOptions = [
                kCGImageSourceShouldCache: false
            ] as CFDictionary

            guard let imageSource = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
                throw APIError.serverMessage("图片解码失败")
            }

            let thumbnailOptions = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maxPixelLength.rounded(.up)))
            ] as CFDictionary

            if let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, thumbnailOptions) {
                return UIImage(cgImage: thumbnail)
            }

            if let image = UIImage(data: data) {
                return image
            }

            throw APIError.serverMessage("图片解码失败")
        }.value
    }

    private func cacheKey(for url: URL, maxPixelLength: CGFloat) -> NSString {
        "\(url.absoluteString)#\(Int(maxPixelLength.rounded(.up)))" as NSString
    }

    private func cacheCost(for image: UIImage) -> Int {
        if let cgImage = image.cgImage {
            return cgImage.bytesPerRow * cgImage.height
        }

        return Int(image.size.width * image.size.height * image.scale * image.scale * 4)
    }

    private func imageCandidateURLs(from url: URL) -> [URL] {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return [url]
        }
        if components.scheme == "http" {
            components.scheme = "https"
        }

        var candidates = components.url.map { [$0] } ?? [url]

        let originalPath = components.path
        let strippedPath = originalPath.split(separator: "@", maxSplits: 1).first.map(String.init) ?? originalPath
        if strippedPath != originalPath {
            components.path = strippedPath
            if let strippedURL = components.url {
                candidates.append(strippedURL)
            }
        }

        let basePath = components.path
        for replacement in [".jpg", ".png", ".webp"] where !basePath.hasSuffix(replacement) {
            var replacementComponents = components
            replacementComponents.path = basePath.replacingOccurrences(
                of: #"\.(webp|avif|jpg|jpeg|png)$"#,
                with: replacement,
                options: .regularExpression
            )
            if let replacementURL = replacementComponents.url {
                candidates.append(replacementURL)
            }
        }

        var unique = [URL]()
        var seen = Set<String>()
        for candidate in candidates where seen.insert(candidate.absoluteString).inserted {
            unique.append(candidate)
        }
        return unique
    }
}

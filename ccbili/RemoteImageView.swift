//
//  RemoteImageView.swift
//  ccbili
//
//  Created by chuzu  on 2026/4/25.
//

import SwiftUI
import UIKit

struct RemoteImageView<Placeholder: View, FailureView: View>: View {
    let url: URL?
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

        var configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 15
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.urlCache = URLCache(
            memoryCapacity: 80 * 1024 * 1024,
            diskCapacity: 300 * 1024 * 1024,
            diskPath: "ccbili-image-cache"
        )

        let session = URLSession(configuration: configuration)

        do {
            let (data, response) = try await loadImageData(originalURL: url, session: session)

            guard let httpResponse = response as? HTTPURLResponse else {
                errorText = "响应无效"
                phase = .failure
                return
            }

            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "未知类型"

            guard (200...299).contains(httpResponse.statusCode) else {
                errorText = "状态码 \(httpResponse.statusCode)"
                phase = .failure
                return
            }

            guard let loadedImage = UIImage(data: data) else {
                errorText = "解码失败\n\(contentType)"
                phase = .failure
                return
            }

            await MainActor.run {
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    image = loadedImage
                    phase = .success
                }
            }
        } catch {
            errorText = error.localizedDescription
            phase = .failure
        }
    }

    private func loadImageData(originalURL: URL, session: URLSession) async throws -> (Data, URLResponse) {
        var lastError: Error?
        for candidateURL in imageCandidateURLs(from: originalURL) {
            do {
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
                if UIImage(data: data) != nil {
                    return (data, response)
                }
                lastError = APIError.serverMessage("图片解码失败")
            } catch {
                lastError = error
            }
        }
        throw lastError ?? APIError.invalidResponse
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

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

        var request = URLRequest(url: url)
        request.setValue(AppConfig.defaultUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")
        request.cachePolicy = .returnCacheDataElseLoad
        request.setValue("image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)

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
}

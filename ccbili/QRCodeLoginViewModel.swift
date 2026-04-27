//
//  QRCodeLoginViewModel.swift
//  ccbili
//
//  Created by chuzu  on 2026/4/25.
//

import Foundation
import Observation

@Observable
final class QRCodeLoginViewModel {
    var qrCodeImageURL: URL?
    var qrcodeKey: String?

    var statusText = "正在加载二维码..."
    var isLoading = false
    var isPolling = false
    var isLoginCompleted = false
    var errorMessage: String?

    private let loginService = LoginService()
    private var pollingTask: Task<Void, Never>?

    func loadQRCode() async {
        pollingTask?.cancel()
        qrCodeImageURL = nil
        qrcodeKey = nil
        isLoading = true
        isPolling = false
        isLoginCompleted = false
        errorMessage = nil
        statusText = "正在加载二维码..."

        defer {
            isLoading = false
        }

        do {
            let data = try await loginService.generateQRCode()

            guard let urlString = data.url, !urlString.isEmpty else {
                throw APIError.serverMessage("接口已返回成功，但缺少二维码链接")
            }

            guard let url = URL(string: urlString) else {
                throw APIError.serverMessage("二维码链接格式无效：\(urlString)")
            }

            guard let qrcodeKey = data.qrcodeKey, !qrcodeKey.isEmpty else {
                throw APIError.serverMessage("接口已返回成功，但缺少 qrcode_key")
            }

            self.qrCodeImageURL = url
            self.qrcodeKey = qrcodeKey
            self.statusText = "请使用哔哩哔哩 App 扫码登录"

            startPolling()
        } catch {
            self.errorMessage = error.localizedDescription
            self.statusText = "二维码加载失败"
        }
    }

    func cancelPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        isPolling = false
    }

    private func startPolling() {
        guard let qrcodeKey else { return }

        isPolling = true

        pollingTask = Task {
            while !Task.isCancelled {
                do {
                    let result = try await loginService.pollQRCodeLogin(qrcodeKey: qrcodeKey)

                    switch result.code {
                    case 0:
                        BilibiliCookieStore.persistSharedStorage()
                        statusText = "登录成功"
                        isLoginCompleted = true
                        isPolling = false
                        pollingTask?.cancel()
                        return

                    case 86038:
                        statusText = "二维码已失效，请刷新后重试"
                        isPolling = false
                        return

                    case 86090:
                        statusText = "二维码已扫码，请在 App 中确认"

                    case 86101:
                        statusText = "请使用哔哩哔哩 App 扫码"

                    case nil:
                        statusText = "轮询结果缺少状态码"

                    default:
                        statusText = result.message ?? "等待扫码中..."
                    }
                } catch {
                    errorMessage = error.localizedDescription
                    statusText = "轮询登录状态失败"
                    isPolling = false
                    return
                }

                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

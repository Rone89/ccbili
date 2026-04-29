import Foundation

struct ReplyService {
    func fetchVideoReplies(oid: Int, type: Int = 1, sort: Int = 1) async throws -> [VideoComment] {
        var components = URLComponents(
            url: AppConfig.apiBaseURL.appending(path: "/x/v2/reply/main"),
            resolvingAgainstBaseURL: false
        )

        components?.queryItems = [
            URLQueryItem(name: "oid", value: String(oid)),
            URLQueryItem(name: "type", value: String(type)),
            URLQueryItem(name: "mode", value: String(sort + 2)),
            URLQueryItem(name: "pagination_str", value: #"{"offset":""}"#)
        ]

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        let response = try await APIClient.shared.get(
            url: url,
            as: ReplyListResponse.self
        )

        guard response.code == 0 else {
            throw APIError.serverMessage(response.message)
        }

        let comments = (response.data?.replies ?? []).map { reply in
            VideoComment(
                id: String(reply.rpid ?? 0),
                username: reply.member?.uname ?? "未知用户",
                message: reply.content?.message ?? "",
                userID: reply.member?.mid,
                avatarURL: normalizedImageURL(from: reply.member?.avatar),
                timeText: formattedCommentTime(from: reply.ctime),
                likeCount: reply.like ?? 0,
                replyCount: reply.rcount ?? reply.replies?.count ?? 0,
                previewReplies: (reply.replies ?? []).prefix(2).map { child in
                    VideoCommentPreviewReply(
                        username: child.member?.uname ?? "未知用户",
                        message: child.content?.message ?? ""
                    )
                }
            )
        }

        return comments
    }

    private func normalizedImageURL(from path: String?) -> URL? {
        guard let path, !path.isEmpty else {
            return nil
        }

        if path.hasPrefix("//") {
            return URL(string: "https:" + path)
        }

        return URL(string: path)
    }

    private func formattedCommentTime(from timestamp: Int?) -> String {
        guard let timestamp else {
            return "时间未知"
        }

        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

import SwiftUI

struct VideoListRowView: View {
    let title: String
    let subtitle: String
    let accessoryText: String?
    let coverURL: URL?
    let continueWatchingText: String?
    let progress: Double?

    init(
        title: String,
        subtitle: String,
        accessoryText: String? = nil,
        coverURL: URL? = nil,
        continueWatchingText: String? = nil,
        progress: Double? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accessoryText = accessoryText
        self.coverURL = coverURL
        self.continueWatchingText = continueWatchingText
        self.progress = progress
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RemoteImageView(
                url: coverURL,
                placeholder: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.quaternary.opacity(0.25))
                        ProgressView()
                    }
                },
                failureView: { errorText in
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.quaternary.opacity(0.25))

                        VStack(spacing: 6) {
                            Image(systemName: "photo")
                                .font(.title3)
                                .foregroundStyle(.secondary)

                            Text(errorText)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                                .padding(.horizontal, 6)
                        }
                    }
                }
            )
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if let progress {
                    GeometryReader { proxy in
                        Rectangle()
                            .fill(Color(red: 251 / 255, green: 114 / 255, blue: 153 / 255))
                            .frame(width: proxy.size.width * min(max(progress, 0), 1))
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                    .frame(height: 3)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let continueWatchingText {
                    Label(continueWatchingText, systemImage: "play.circle")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color(red: 251 / 255, green: 114 / 255, blue: 153 / 255))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 2)
        }
        .contentShape(Rectangle())
    }
}

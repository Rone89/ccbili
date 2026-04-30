import SwiftUI

struct VideoListRowView: View {
    enum LayoutStyle {
        case standard
        case homeCard
    }

    let title: String
    let subtitle: String
    let accessoryText: String?
    let coverURL: URL?
    let continueWatchingText: String?
    let progress: Double?
    let layoutStyle: LayoutStyle

    private let homeCardTotalHeight: CGFloat = 172
    private let homeCardCoverHeight: CGFloat = 100
    private let homeCardInfoHeight: CGFloat = 72
    private let homeCardCornerRadius: CGFloat = 14
    private let homeCardHorizontalPadding: CGFloat = 10

    init(
        title: String,
        subtitle: String,
        accessoryText: String? = nil,
        coverURL: URL? = nil,
        continueWatchingText: String? = nil,
        progress: Double? = nil,
        layoutStyle: LayoutStyle = .standard
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accessoryText = accessoryText
        self.coverURL = coverURL
        self.continueWatchingText = continueWatchingText
        self.progress = progress
        self.layoutStyle = layoutStyle
    }

    var body: some View {
        switch layoutStyle {
        case .standard:
            standardBody
        case .homeCard:
            homeCardBody
        }
    }

    private var standardBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            coverImage(cornerRadius: 14, failureFontSize: 9)
            .frame(maxWidth: .infinity)
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .bottomLeading) { progressBar }

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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
    }

    private var homeCardBody: some View {
        VStack(spacing: 0) {
            coverImage(cornerRadius: 0, failureFontSize: 8)
                .frame(maxWidth: .infinity)
                .frame(height: homeCardCoverHeight)
                .clipped()
                .overlay(alignment: .bottomLeading) { progressBar }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 5) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, homeCardHorizontalPadding)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: homeCardInfoHeight, maxHeight: homeCardInfoHeight, alignment: .topLeading)
            .background(Color(.secondarySystemGroupedBackground))
        }
        .frame(maxWidth: .infinity)
        .frame(height: homeCardTotalHeight)
        .background(Color(.secondarySystemGroupedBackground))
        .overlay {
            RoundedRectangle(cornerRadius: homeCardCornerRadius, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.08), lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: homeCardCornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: homeCardCornerRadius, style: .continuous))
    }

    private func coverImage(cornerRadius: CGFloat, failureFontSize: CGFloat) -> some View {
        RemoteImageView(
            url: coverURL,
            maxPixelLength: layoutStyle == .homeCard ? 420 : 560,
            placeholder: {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(.tertiarySystemGroupedBackground))
            },
            failureView: { errorText in
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color(.tertiarySystemGroupedBackground))

                    VStack(spacing: 4) {
                        Image(systemName: "photo")
                            .font(.title3)
                            .foregroundStyle(.secondary)

                        Text(errorText)
                            .font(.system(size: failureFontSize))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .padding(.horizontal, 6)
                    }
                }
            }
        )
    }

    @ViewBuilder
    private var progressBar: some View {
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
}

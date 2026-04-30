import SwiftUI

struct HomeRecommendationCardView: View {
    let item: VideoItem

    private let totalHeight: CGFloat = 172
    private let coverHeight: CGFloat = 100
    private let infoHeight: CGFloat = 72
    private let cornerRadius: CGFloat = 14
    private let horizontalPadding: CGFloat = 10

    private var isPlaceholder: Bool {
        item.bvid == nil && item.aid == nil
    }

    var body: some View {
        VStack(spacing: 0) {
            coverSection
                .frame(maxWidth: .infinity)

            infoSection
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: infoHeight, maxHeight: infoHeight, alignment: .topLeading)
                .background(Color(.secondarySystemGroupedBackground))
        }
        .frame(maxWidth: .infinity)
        .frame(height: totalHeight)
        .background(Color(.secondarySystemGroupedBackground))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.08), lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private var coverSection: some View {
        if isPlaceholder {
            ZStack {
                Rectangle()
                    .fill(Color(.tertiarySystemGroupedBackground))

                VStack(spacing: 8) {
                    ProgressView()

                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color(.systemGray5))
                        .frame(width: 68, height: 8)
                }
            }
            .frame(height: coverHeight)
            .clipped()
        } else {
            RemoteImageView(
                url: item.coverURL,
                maxPixelLength: 640,
                placeholder: {
                    Rectangle()
                        .fill(Color(.tertiarySystemGroupedBackground))
                },
                failureView: { errorText in
                    ZStack {
                        Rectangle()
                            .fill(Color(.tertiarySystemGroupedBackground))

                        VStack(spacing: 4) {
                            Image(systemName: "photo")
                                .font(.title3)
                                .foregroundStyle(.secondary)

                            Text(errorText)
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 6)
                        }
                    }
                }
            )
            .frame(height: coverHeight)
            .clipped()
        }
    }

    @ViewBuilder
    private var infoSection: some View {
        if isPlaceholder {
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(.quaternarySystemFill))
                    .frame(maxWidth: .infinity)
                    .frame(height: 11)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(.quaternarySystemFill))
                    .frame(width: 76, height: 9)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 5) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    Text(item.subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct PressedCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.988 : 1)
            .opacity(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

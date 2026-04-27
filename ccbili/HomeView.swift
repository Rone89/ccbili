import SwiftUI

struct HomeView: View {
    @Binding var isTabBarHidden: Bool

    init(isTabBarHidden: Binding<Bool> = .constant(false)) {
        _isTabBarHidden = isTabBarHidden
    }
    @Environment(AuthManager.self) private var authManager

    @State private var viewModel = HomeViewModel()
    @State private var scrollTargetID = UUID()
    @State private var scrollOffset: CGFloat = 0

    private let columns = [
        GridItem(.flexible(), spacing: 10, alignment: .top),
        GridItem(.flexible(), spacing: 10, alignment: .top)
    ]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                GeometryReader { geometry in
                    Color.clear
                        .preference(
                            key: HomeScrollOffsetPreferenceKey.self,
                            value: geometry.frame(in: .named("homeScroll")).minY
                        )
                }
                .frame(height: 0)

                Color.clear
                    .frame(height: 1)
                    .id(scrollTargetID)

                VStack(alignment: .leading, spacing: 18) {
                    titleSection

                    if let errorMessage = viewModel.errorMessage {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("加载失败", systemImage: "exclamationmark.triangle.fill")
                                .font(.headline)
                                .foregroundStyle(.red)

                            Text(errorMessage)
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color(.separator).opacity(0.08), lineWidth: 0.5)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("为你推荐")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.primary)

                        gridSection
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .coordinateSpace(name: "homeScroll")
            .onPreferenceChange(HomeScrollOffsetPreferenceKey.self) { value in
                scrollOffset = value
            }
            .onReceive(NotificationCenter.default.publisher(for: .homeTabDidRetap)) { _ in
                Task {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(scrollTargetID, anchor: .top)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .scrollContentBackground(.hidden)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("推荐")
                        .font(.headline.weight(.semibold))
                        .opacity(compactBarOpacity)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await refreshHome()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("刷新推荐")
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                topBarBackground
            }
            .task {
                if viewModel.isPlaceholderItem(viewModel.items.first ?? VideoItem(id: "", title: "", subtitle: "")) {
                    await viewModel.load()
                }

                if authManager.isLoggedIn && authManager.avatarURL == nil {
                    await authManager.refreshLoginStatus()
                }
            }
            .refreshable {
                await refreshHome()

                if authManager.isLoggedIn && authManager.avatarURL == nil {
                    await authManager.refreshLoginStatus()
                }
            }
        }
    }

    private var gridSection: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(viewModel.items) { item in
                NavigationLink {
                    VideoDetailView(item: item, isTabBarHidden: $isTabBarHidden)
                } label: {
                    HomeRecommendationCardView(item: item)
                }
                .buttonStyle(PressedCardButtonStyle())
                .task {
                    await viewModel.loadMoreIfNeeded(currentItem: item)
                }
            }
        }
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                Text("首页")
                    .font(.system(size: 44, weight: .bold, design: .default))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer()

                Button {
                } label: {
                    currentUserAvatarView
                }
                .buttonStyle(.plain)
                .accessibilityLabel("个人头像")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("持续刷新你可能感兴趣的内容")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)

                    Text("为你持续发现新内容")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var currentUserAvatarView: some View {
        Group {
            if let avatarURL = authManager.avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .empty:
                        Circle()
                            .fill(Color(.tertiarySystemGroupedBackground))
                            .overlay {
                                ProgressView()
                                    .controlSize(.small)
                            }

                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()

                    case .failure:
                        defaultAvatarView

                    @unknown default:
                        defaultAvatarView
                    }
                }
            } else {
                defaultAvatarView
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(Circle())
        .overlay {
            Circle()
                .strokeBorder(.white.opacity(0.35), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 5)
    }

    private var defaultAvatarView: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 142 / 255, green: 170 / 255, blue: 232 / 255),
                        Color(red: 105 / 255, green: 113 / 255, blue: 196 / 255)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: "person.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
            }
    }

    private var compactBarOpacity: CGFloat {
        min(max(-scrollOffset / 56, 0), 1)
    }

    private var topBarBackgroundOpacity: CGFloat {
        min(max((-scrollOffset - 2) / 36, 0), 1)
    }

    private var topBarBackground: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(topBarBackgroundOpacity)

            LinearGradient(
                colors: [
                    Color.black.opacity(topBarBackgroundOpacity * 0.08),
                    Color.black.opacity(topBarBackgroundOpacity * 0.03),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(height: 0)
        .background(
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(topBarBackgroundOpacity)

                LinearGradient(
                    colors: [
                        Color.black.opacity(topBarBackgroundOpacity * 0.08),
                        Color.black.opacity(topBarBackgroundOpacity * 0.03),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(height: 52)
        )
        .overlay(alignment: .bottom) {
            Divider()
                .opacity(topBarBackgroundOpacity * 0.18)
        }
    }

    private func refreshHome() async {
        await viewModel.load(forceRefresh: true)
    }
}

private struct HomeScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}


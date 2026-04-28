import SwiftUI
import AVKit

struct VideoDetailView: View {
    @Environment(AuthManager.self) private var authManager

    @State private var viewModel: VideoDetailViewModel
    @State private var favoriteViewModel = VideoFavoriteViewModel()
    @State private var player: AVPlayer?
    @State private var playerURL: URL?
    @State private var playbackPosition: Double = 0

    @State private var interactionService = VideoInteractionService()
    @State private var isSubmittingLike = false
    @State private var isSubmittingCoin = false

    @State private var didLike = false
    @State private var didCoin = false

    @State private var likeErrorMessage: String?
    @State private var coinErrorMessage: String?
    @State private var selectedTab: DetailTab = .intro
    @State private var commentSortMode: CommentSortMode = .hot
    @State private var playerScrollOffset: CGFloat = 0
    @State private var isVideoPlaying = false
    @State private var isVideoFullscreen = false

    private let biliPink = Color(red: 251 / 255, green: 114 / 255, blue: 153 / 255)
    private let replyService = ReplyService()
    private let detailCardCornerRadius: CGFloat = 20
    private let cardCornerRadius: CGFloat = 18
    private let pageHorizontalInset: CGFloat = 16
    private let titleHorizontalInset: CGFloat = 16

    init(item: VideoItem) {
        _viewModel = State(initialValue: VideoDetailViewModel(item: item))
    }

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = max(proxy.size.width - pageHorizontalInset * 2, 0)
            let playerHeight = contentWidth * 9 / 16
            let displayedPlayerWidth = isVideoFullscreen ? proxy.size.width : contentWidth
            let displayedPlayerHeight = isVideoFullscreen ? proxy.size.height : playerHeight
            let playerOffsetX = isVideoFullscreen ? 0 : pageHorizontalInset
            let playerOffsetY = isVideoFullscreen ? 0 : (isVideoPlaying ? 0 : playerScrollOffset)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    playerPlaceholderSection(height: playerHeight)
                        .frame(width: contentWidth)
                        .background(
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: PlayerOffsetPreferenceKey.self,
                                    value: geometry.frame(in: .named("videoDetailScroll")).minY
                                )
                            }
                        )

                    titleCardSection
                        .frame(width: contentWidth)

                    authorSection
                        .frame(width: contentWidth)

                    actionSection
                        .frame(width: contentWidth)

                    errorSection
                        .frame(width: contentWidth)

                    tabSection
                        .frame(width: contentWidth)

                    animatedTabContentSection
                        .frame(width: contentWidth)
                }
                .padding(.horizontal, pageHorizontalInset)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .coordinateSpace(name: "videoDetailScroll")
            .onPreferenceChange(PlayerOffsetPreferenceKey.self) { value in
                playerScrollOffset = value
            }
            .background(Color(.systemGroupedBackground))
            .overlay(alignment: .topLeading) {
                if isVideoFullscreen {
                    Color.black
                        .ignoresSafeArea()
                        .zIndex(9)
                }

                playerCardSection(height: displayedPlayerHeight)
                    .frame(width: displayedPlayerWidth, height: displayedPlayerHeight)
                    .clipShape(RoundedRectangle(cornerRadius: isVideoFullscreen ? 0 : detailCardCornerRadius, style: .continuous))
                    .shadow(color: .black.opacity(isVideoPlaying && !isVideoFullscreen ? 0.16 : 0), radius: 16, x: 0, y: 8)
                    .offset(x: playerOffsetX, y: playerOffsetY)
                    .zIndex(10)
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.88), value: isVideoPlaying)
            .animation(.easeInOut(duration: 0.25), value: isVideoFullscreen)
        }
        .statusBarHidden(isVideoFullscreen)
        .navigationTitle("视频详情")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            AppOrientationController.lock(.portrait)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            let orientation = UIDevice.current.orientation
            if orientation == .landscapeLeft || orientation == .landscapeRight {
                isVideoFullscreen = true
            } else if orientation == .portrait || orientation == .portraitUpsideDown {
                isVideoFullscreen = false
            }
        }
        .task {
            favoriteViewModel.load(videoID: viewModel.playbackItem.id)

            if !viewModel.hasLoadedContent {
                await viewModel.load()
                favoriteViewModel.load(videoID: viewModel.playbackItem.id)
            } else {
                configurePlayer(for: viewModel.playURL)
            }

            if authManager.isLoggedIn && authManager.avatarURL == nil {
                await authManager.refreshLoginStatus()
            }
        }
        .refreshable {
            await viewModel.load()
            favoriteViewModel.load(videoID: viewModel.playbackItem.id)
        }
        .onChange(of: viewModel.playURL) { _, newValue in
            configurePlayer(for: newValue)
        }
        .onChange(of: commentSortMode) { _, newValue in
            Task {
                await reloadComments(sortMode: newValue)
            }
        }
        .onDisappear {
            isVideoFullscreen = false
            configurePlayer(for: nil)
            AppOrientationController.lock(.portrait)
        }
    }

    // MARK: - Player

    private func playerCardSection(height: CGFloat) -> some View {
        videoHeaderSection(height: height)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: detailCardCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: detailCardCornerRadius, style: .continuous)
                    .strokeBorder(Color(.separator).opacity(0.08), lineWidth: 0.5)
            }
    }

    private func playerPlaceholderSection(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: detailCardCornerRadius, style: .continuous)
            .fill(Color.black.opacity(0.92))
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay {
                RoundedRectangle(cornerRadius: detailCardCornerRadius, style: .continuous)
                    .strokeBorder(Color(.separator).opacity(0.08), lineWidth: 0.5)
            }
    }

    @ViewBuilder
    private func videoHeaderSection(height: CGFloat) -> some View {
        if let source = viewModel.playbackSource {
            BilibiliVLCPlayerView(
                source: source,
                enablesAutoFullscreen: false,
                initialPosition: playbackPosition,
                onPositionChange: { position in
                    playbackPosition = position
                },
                onPlaybackStateChange: { isPlaying in
                    isVideoPlaying = isPlaying
                },
                onFullscreenRequest: {
                    toggleVideoFullscreen()
                }
            )
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(.black)
        } else {
            unavailablePlayerPlaceholder(height: height)
        }
    }

    private func unavailablePlayerPlaceholder(height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(.secondarySystemGroupedBackground),
                            Color(.tertiarySystemGroupedBackground)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            VStack {
                HStack {
                    Spacer()

                    Label(
                        viewModel.isLoadingPlaybackSource ? "准备中" : "未就绪",
                        systemImage: viewModel.isLoadingPlaybackSource ? "arrow.triangle.2.circlepath" : "wifi.exclamationmark"
                    )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.35), in: Capsule())
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)

                Spacer()

                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 74, height: 74)

                        if viewModel.isLoadingPlaybackSource {
                            ProgressView()
                                .controlSize(.large)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(.primary)
                                .offset(x: 2)
                        }
                    }

                    VStack(spacing: 4) {
                        Text("视频播放区域")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text(viewModel.playbackErrorMessage ?? playbackPlaceholderText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }

                Spacer()

                bottomPlaybackOverlay
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    private var playbackPlaceholderText: String {
        if viewModel.isLoadingPlaybackSource {
            return "正在获取 1080P 播放地址，评论和推荐会先加载"
        }

        return "正在获取播放地址"
    }

    private var bottomPlaybackOverlay: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 3) {
                    Text("等待播放")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)

                    Text("播放器正在准备中")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.18))

                    Capsule()
                        .fill(.white.opacity(0.92))
                        .frame(width: proxy.size.width * 0.12)
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            LinearGradient(
                colors: [
                    .clear,
                    .black.opacity(0.18),
                    .black.opacity(0.42)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Title

    private var titleCardSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(viewModel.playbackItem.title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            HStack(spacing: 8) {
                metaChip(systemImage: "calendar", text: viewModel.uploadTimeText)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, titleHorizontalInset)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.08), lineWidth: 0.5)
        }
    }

    // MARK: - Author

    private var authorSection: some View {
        Group {
            if let author = viewModel.author {
                HStack(spacing: 12) {
                    AsyncImage(url: author.avatarURL) { phase in
                        switch phase {
                        case .empty:
                            Circle()
                                .fill(Color(.quaternarySystemFill))
                                .overlay {
                                    ProgressView()
                                }
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            Circle()
                                .fill(Color(.quaternarySystemFill))
                                .overlay {
                                    Image(systemName: "person.fill")
                                        .foregroundStyle(.secondary)
                                }
                        @unknown default:
                            Circle()
                                .fill(Color(.quaternarySystemFill))
                        }
                    }
                    .frame(width: 46, height: 46)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(author.name)
                            .font(.subheadline.weight(.semibold))

                        Text(author.followerText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("关注") {
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .buttonBorderShape(.capsule)
                    .tint(biliPink)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                )
            } else {
                Text("暂无 UP 主信息")
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    private var actionSection: some View {
        HStack(spacing: 10) {
            actionIconButton(
                title: "收藏",
                systemImage: favoriteViewModel.isFavorite ? "star.fill" : "star",
                tint: favoriteViewModel.isFavorite ? .yellow : .secondary,
                isLoading: favoriteViewModel.isLoading
            ) {
                Task {
                    await favoriteCurrentVideo()
                }
            }

            actionIconButton(
                title: "点赞",
                systemImage: didLike ? "hand.thumbsup.fill" : "hand.thumbsup",
                tint: didLike ? .blue : .secondary,
                isLoading: isSubmittingLike
            ) {
                Task {
                    await likeCurrentVideo()
                }
            }

            actionIconButton(
                title: "投币",
                systemImage: didCoin ? "bitcoinsign.circle.fill" : "bitcoinsign.circle",
                tint: didCoin ? .yellow : .secondary,
                isLoading: isSubmittingCoin
            ) {
                Task {
                    await coinCurrentVideo()
                }
            }

            actionIconButton(
                title: "分享",
                systemImage: "square.and.arrow.up",
                tint: .secondary,
                isLoading: false
            ) {
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Errors

    @ViewBuilder
    private var errorSection: some View {
        if let favoriteError = favoriteViewModel.errorMessage, !favoriteError.isEmpty {
            errorCard(title: "收藏错误", message: favoriteError)
        }

        if let likeErrorMessage, !likeErrorMessage.isEmpty {
            errorCard(title: "点赞错误", message: likeErrorMessage)
        }

        if let coinErrorMessage, !coinErrorMessage.isEmpty {
            errorCard(title: "投币错误", message: coinErrorMessage)
        }

        if let errorMessage = viewModel.errorMessage, !errorMessage.isEmpty {
            errorCard(title: "加载错误", message: errorMessage)
        }
    }

    // MARK: - Tabs

    private var tabSection: some View {
        Picker("详情分区", selection: $selectedTab) {
            Text("简介").tag(DetailTab.intro)
            Text("评论").tag(DetailTab.comments)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var animatedTabContentSection: some View {
        switch selectedTab {
        case .intro:
            introContent
        case .comments:
            commentsContent
        case .related:
            EmptyView()
        }
    }

    // MARK: - Intro

    private var introContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if viewModel.descriptionText.isEmpty {
                Text("暂无简介")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(viewModel.descriptionText)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineSpacing(3)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("相关推荐")
                    .font(.headline)

                if viewModel.relatedVideos.isEmpty {
                    Text("暂无相关推荐")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.relatedVideos) { related in
                            NavigationLink {
                                VideoDetailView(
                                    item: VideoItem(
                                        id: related.id,
                                        title: related.title,
                                        subtitle: related.subtitle,
                                        bvid: related.id
                                    )
                                )
                            } label: {
                                relatedMiniCard(
                                    title: related.title,
                                    subtitle: related.subtitle,
                                    coverURL: related.coverURL
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
        )
    }

    // MARK: - Comments

    private var commentsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("评论")
                    .font(.headline)

                Spacer()

                Menu {
                    ForEach(CommentSortMode.allCases, id: \.self) { mode in
                        Button {
                            commentSortMode = mode
                        } label: {
                            if mode == commentSortMode {
                                Label(mode.title, systemImage: "checkmark")
                            } else {
                                Text(mode.title)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(commentSortMode.title)
                            .font(.caption)
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Color(.tertiarySystemGroupedBackground),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
            }

            Button {
            } label: {
                HStack(spacing: 10) {
                    currentUserAvatarView

                    HStack {
                        Text("说点什么吧...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Spacer()

                        HStack(spacing: 10) {
                            Image(systemName: "face.smiling")
                            Image(systemName: "photo")
                        }
                        .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(
                        Color(.tertiarySystemGroupedBackground),
                        in: Capsule()
                    )
                }
            }
            .buttonStyle(.plain)

            Divider()

            if viewModel.isLoading && viewModel.comments.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在加载评论...")
                        .foregroundStyle(.secondary)
                }
            } else if viewModel.comments.isEmpty {
                Text("暂无评论")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.comments) { comment in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 10) {
                            NavigationLink {
                                UserSpaceWebView(userID: comment.userID, username: comment.username)
                            } label: {
                                AsyncImage(url: comment.avatarURL) { phase in
                                    switch phase {
                                    case .empty:
                                        Circle()
                                            .fill(Color(.quaternarySystemFill))
                                            .overlay {
                                                ProgressView()
                                            }
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    case .failure:
                                        Circle()
                                            .fill(Color(.quaternarySystemFill))
                                            .overlay {
                                                Image(systemName: "person.fill")
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(.secondary)
                                            }
                                    @unknown default:
                                        Circle()
                                            .fill(Color(.quaternarySystemFill))
                                    }
                                }
                                .frame(width: 34, height: 34)
                                .clipShape(Circle())
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .leading, spacing: 6) {
                                NavigationLink {
                                    UserSpaceWebView(userID: comment.userID, username: comment.username)
                                } label: {
                                    Text(comment.username)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                }
                                .buttonStyle(.plain)

                                Text(comment.message)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                Text(comment.timeText)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)

                                HStack(spacing: 16) {
                                    Label("回复", systemImage: "bubble.left")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)

                                    Label("点赞", systemImage: "hand.thumbsup")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)

                                    Spacer()

                                    Button("查看其他回复") {
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                .padding(.top, 2)
                            }

                            Spacer()
                        }

                        Divider()
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
        )
    }

    private var currentUserAvatarView: some View {
        Group {
            if let avatarURL = authManager.avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .empty:
                        Circle()
                            .fill(Color(.quaternarySystemFill))
                            .overlay {
                                ProgressView()
                            }
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Circle()
                            .fill(Color(.quaternarySystemFill))
                            .overlay {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                    @unknown default:
                        Circle()
                            .fill(Color(.quaternarySystemFill))
                    }
                }
            } else {
                Circle()
                    .fill(Color(.quaternarySystemFill))
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(Circle())
    }

    // MARK: - Related

    private func relatedMiniCard(title: String, subtitle: String, coverURL: URL?) -> some View {
        HStack(spacing: 10) {
            RemoteImageView(
                url: coverURL,
                placeholder: {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(.quaternarySystemFill))
                },
                failureView: { _ in
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(.quaternarySystemFill))
                        .overlay {
                            Image(systemName: "play.rectangle")
                                .foregroundStyle(.secondary)
                        }
                }
            )
            .transaction { transaction in
                transaction.animation = nil
            }
            .frame(width: 116, height: 66)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.tertiarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    // MARK: - Shared UI

    private func actionIconButton(
        title: String,
        systemImage: String,
        tint: Color,
        isLoading: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .controlSize(.regular)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 20, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                }
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(Color(.separator).opacity(0.08), lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityLabel(title)
    }

    private func metaChip(systemImage: String, text: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Color(.tertiarySystemGroupedBackground),
                in: Capsule()
            )
    }

    private func errorCard(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.red)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.red)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
        )
    }

    // MARK: - Player

    private func configurePlayer(for url: URL?) {
        player?.pause()
        player = nil
        playerURL = nil
    }

    // MARK: - Actions

    private func favoriteCurrentVideo() async {
        await favoriteViewModel.favorite(video: viewModel.playbackItem)
    }

    private func likeCurrentVideo() async {
        guard let aid = viewModel.playbackItem.aid else {
            likeErrorMessage = "缺少 aid，暂时无法点赞"
            return
        }

        isSubmittingLike = true
        likeErrorMessage = nil

        defer {
            isSubmittingLike = false
        }

        do {
            try await interactionService.like(aid: aid, like: true)
            didLike = true
        } catch {
            likeErrorMessage = error.localizedDescription
        }
    }

    private func coinCurrentVideo() async {
        guard let aid = viewModel.playbackItem.aid else {
            coinErrorMessage = "缺少 aid，暂时无法投币"
            return
        }

        isSubmittingCoin = true
        coinErrorMessage = nil

        defer {
            isSubmittingCoin = false
        }

        do {
            try await interactionService.coin(aid: aid, multiply: 1, like: false)
            didCoin = true
        } catch {
            coinErrorMessage = error.localizedDescription
        }
    }

    private func reloadComments(sortMode: CommentSortMode) async {
        guard let aid = viewModel.playbackItem.aid else { return }

        do {
            let loadedComments = try await replyService.fetchVideoReplies(
                oid: aid,
                type: 1,
                sort: sortMode.replySortValue
            )
            viewModel.comments = loadedComments
        } catch {
            viewModel.comments = [
                VideoComment(
                    id: "comment-load-failed-\(sortMode.title)",
                    username: "系统提示",
                    message: "评论加载失败：\(error.localizedDescription)",
                    userID: nil,
                    avatarURL: nil,
                    timeText: "时间未知"
                )
            ]
        }
    }
}

private enum DetailTab: Hashable {
    case intro
    case comments
    case related
}

private struct PlayerOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }

    private func toggleVideoFullscreen() {
        let shouldEnterFullscreen = !isVideoFullscreen
        withAnimation(.easeInOut(duration: 0.25)) {
            isVideoFullscreen = shouldEnterFullscreen
        }
    }
}

private enum CommentSortMode: CaseIterable {
    case hot
    case latest

    var title: String {
        switch self {
        case .hot:
            return "按热度"
        case .latest:
            return "按时间"
        }
    }

    var replySortValue: Int {
        switch self {
        case .hot:
            return 1
        case .latest:
            return 2
        }
    }
}


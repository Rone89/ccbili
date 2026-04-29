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
    @State private var isSwitchingQuality = false

    @State private var didLike = false
    @State private var didCoin = false

    @State private var likeErrorMessage: String?
    @State private var coinErrorMessage: String?
    @State private var selectedTab: DetailTab = .intro
    @State private var commentSortMode: CommentSortMode = .hot
    @State private var isVideoPlaying = false
    @State private var videoAspectRatio: CGFloat = 16 / 9
    @State private var restoredPlaybackPosition: Double?
    @State private var lastSavedPlaybackSecond = 0
    @State private var expandedCommentReplies: [String: [VideoCommentPreviewReply]] = [:]
    @State private var loadingReplyCommentIDs: Set<String> = []

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
            let playerWidth = proxy.size.width
            let playerHeight = min(playerWidth / videoAspectRatio, proxy.size.height * 0.7)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    playerCardSection(height: playerHeight)
                        .frame(width: playerWidth)
                        .padding(.horizontal, -pageHorizontalInset)

                    videoInfoSection
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
            .background(Color(.systemGroupedBackground))
            .animation(.spring(response: 0.32, dampingFraction: 0.88), value: isVideoPlaying)
        }
        .navigationTitle("瑙嗛璇︽儏")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            AppOrientationController.lock(.portrait)
            if let history = VideoPlaybackHistoryStore.history(for: viewModel.playbackItem.id) {
                restoredPlaybackPosition = history.position
                playbackPosition = history.position
            }
        }
        .task {
            favoriteViewModel.load(videoID: viewModel.playbackItem.id)

            if !viewModel.hasLoadedContent {
                await viewModel.load()
                favoriteViewModel.load(videoID: viewModel.playbackItem.id)
                didLike = viewModel.viewerState.didLike
                didCoin = viewModel.viewerState.didCoin
                favoriteViewModel.isFavorite = viewModel.viewerState.didFavorite
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
            savePlaybackHistoryIfNeeded()
            configurePlayer(for: nil)
            AppOrientationController.lock(.portrait)
        }
    }

    // MARK: - Player

    private func playerCardSection(height: CGFloat) -> some View {
        videoHeaderSection(height: height)
            .frame(maxWidth: .infinity)
            .frame(height: height)
    }

    @ViewBuilder
    private func videoHeaderSection(height: CGFloat) -> some View {
        if let source = viewModel.playbackSource {
            BilibiliVLCPlayerView(
                source: source,
                enablesAutoFullscreen: false,
                initialPosition: restoredPlaybackPosition ?? playbackPosition,
                onPositionChange: { position in
                    playbackPosition = position
                    savePlaybackHistoryIfNeeded()
                },
                onPlaybackStateChange: { isPlaying in
                    isVideoPlaying = isPlaying
                },
                onVideoSizeChange: { videoSize in
                    updateVideoAspectRatio(videoSize)
                }
            )
                .frame(maxWidth: .infinity)
                .frame(height: height)
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
                        viewModel.isLoadingPlaybackSource ? "鍑嗗涓? : "鏈氨缁?,
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
                        Text("瑙嗛鎾斁鍖哄煙")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text(viewModel.playbackErrorMessage ?? playbackPlaceholderText)
                            .font(.footnote)
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
            return "姝ｅ湪鑾峰彇 1080P 鎾斁鍦板潃锛岃瘎璁哄拰鎺ㄨ崘浼氬厛鍔犺浇"
        }

        return "姝ｅ湪鑾峰彇鎾斁鍦板潃"
    }

    private var bottomPlaybackOverlay: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 3) {
                    Text("绛夊緟鎾斁")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)

                    Text("鎾斁鍣ㄦ鍦ㄥ噯澶囦腑")
                        .font(.footnote)
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

    private func updateVideoAspectRatio(_ videoSize: CGSize) {
        guard videoSize.width > 0, videoSize.height > 0 else {
            return
        }

        withAnimation(.easeInOut(duration: 0.25)) {
            videoAspectRatio = videoSize.width / videoSize.height
        }
    }

    // MARK: - Info

    private var videoInfoSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            authorSummaryRow

            Text(viewModel.playbackItem.title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            HStack(spacing: 8) {
                metaChip(systemImage: "play.rectangle", text: statsText(viewModel.stats.views, fallback: "鎾斁鏁板緟鎺ュ叆"))
                metaChip(systemImage: "calendar", text: viewModel.uploadTimeText)
                qualityPicker
            }

            if let fallbackMessage = viewModel.playbackFallbackMessage {
                Label(fallbackMessage, systemImage: "arrow.down.circle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
            }

            if let history = VideoPlaybackHistoryStore.history(for: viewModel.playbackItem.id) {
                Label("涓婃鐪嬪埌 \(history.displayText)", systemImage: "clock.arrow.circlepath")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
            }

            actionSection
        }
        .padding(14)
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

    private var authorSummaryRow: some View {
        HStack(spacing: 12) {
            authorAvatarView
                .frame(width: 42, height: 42)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.author?.name ?? viewModel.playbackItem.subtitle)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(viewModel.author?.followerText ?? "绮変笣鏁板緟鎺ュ叆")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("+ 鍏虫敞") {}
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(biliPink, in: Capsule())
        }
    }

    private var authorAvatarView: some View {
        AsyncImage(url: viewModel.author?.avatarURL) { phase in
            switch phase {
            case .empty:
                Circle()
                    .fill(Color(.quaternarySystemFill))
                    .overlay { ProgressView() }
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                Circle()
                    .fill(Color(.quaternarySystemFill))
                    .overlay { Image(systemName: "person.fill").foregroundStyle(.secondary) }
            @unknown default:
                Circle().fill(Color(.quaternarySystemFill))
            }
        }
    }

    private var qualityPicker: some View {
        Menu {
            ForEach(availableQualityOptions) { option in
                Button {
                    Task {
                        await switchPlaybackQuality(to: option)
                    }
                } label: {
                    if option.quality == viewModel.playbackSource?.quality {
                        Label(option.description, systemImage: "checkmark")
                    } else {
                        Text(option.description)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if isSwitchingQuality || viewModel.isLoadingPlaybackSource {
                    ProgressView()
                        .controlSize(.small)
                }

                Text(viewModel.playbackSource?.qualityDescription ?? "娓呮櫚搴?)
                    .font(.caption.weight(.semibold))

                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(availableQualityOptions.isEmpty || isSwitchingQuality || viewModel.isLoadingPlaybackSource)
    }

    private var availableQualityOptions: [VideoQualityOption] {
        if let options = viewModel.playbackSource?.availableQualities, !options.isEmpty {
            return options
        }

        if let source = viewModel.playbackSource,
           let quality = source.quality,
           let description = source.qualityDescription {
            return [VideoQualityOption(quality: quality, description: description)]
        }

        return []
    }

    @MainActor
    private func switchPlaybackQuality(to option: VideoQualityOption) async {
        guard !isSwitchingQuality else { return }
        let currentPosition = playbackPosition
        isSwitchingQuality = true
        await viewModel.switchPlaybackQuality(to: option)
        playbackPosition = currentPosition
        restoredPlaybackPosition = currentPosition
        isSwitchingQuality = false
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
                            .font(.callout.weight(.semibold))

                        Text(author.followerText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("鍏虫敞") {
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
                Text("鏆傛棤 UP 涓讳俊鎭?)
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
                title: statsText(viewModel.stats.favorites, fallback: "鏀惰棌"),
                systemImage: favoriteViewModel.isFavorite ? "star.fill" : "star",
                tint: favoriteViewModel.isFavorite ? .yellow : .secondary,
                isLoading: favoriteViewModel.isLoading
            ) {
                Task {
                    await favoriteCurrentVideo()
                }
            }

            actionIconButton(
                title: statsText(viewModel.stats.likes, fallback: "鐐硅禐"),
                systemImage: didLike ? "hand.thumbsup.fill" : "hand.thumbsup",
                tint: didLike ? .blue : .secondary,
                isLoading: isSubmittingLike
            ) {
                Task {
                    await likeCurrentVideo()
                }
            }

            actionIconButton(
                title: statsText(viewModel.stats.coins, fallback: "鎶曞竵"),
                systemImage: didCoin ? "bitcoinsign.circle.fill" : "bitcoinsign.circle",
                tint: didCoin ? .yellow : .secondary,
                isLoading: isSubmittingCoin
            ) {
                Task {
                    await coinCurrentVideo()
                }
            }

            actionIconButton(
                title: statsText(viewModel.stats.shares, fallback: "鍒嗕韩"),
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
            errorCard(title: "鏀惰棌閿欒", message: favoriteError)
        }

        if let likeErrorMessage, !likeErrorMessage.isEmpty {
            errorCard(title: "鐐硅禐閿欒", message: likeErrorMessage)
        }

        if let coinErrorMessage, !coinErrorMessage.isEmpty {
            errorCard(title: "鎶曞竵閿欒", message: coinErrorMessage)
        }

        if let errorMessage = viewModel.errorMessage, !errorMessage.isEmpty {
            errorCard(title: "鍔犺浇閿欒", message: errorMessage)
        }
    }

    // MARK: - Tabs

    private var tabSection: some View {
        Picker("璇︽儏鍒嗗尯", selection: $selectedTab) {
            Text("绠€浠?).tag(DetailTab.intro)
            Text("璇勮").tag(DetailTab.comments)
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
                Text("鏆傛棤绠€浠?)
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                Text(viewModel.descriptionText)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineSpacing(3)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("鐩稿叧鎺ㄨ崘")
                    .font(.headline)

                if viewModel.relatedVideos.isEmpty {
                    Text("鏆傛棤鐩稿叧鎺ㄨ崘")
                        .font(.body)
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
                Text("璇勮")
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
                            .font(.footnote)
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.footnote)
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
                        Text("璇寸偣浠€涔堝惂...")
                            .font(.body)
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
                    Text("姝ｅ湪鍔犺浇璇勮...")
                        .foregroundStyle(.secondary)
                }
            } else if viewModel.comments.isEmpty {
                Text("鏆傛棤璇勮")
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
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(.primary)
                                }
                                .buttonStyle(.plain)

                                Text(comment.message)
                                    .font(.body)
                                    .foregroundStyle(.secondary)

                                Text(comment.timeText)
                                    .font(.footnote)
                                    .foregroundStyle(.tertiary)

                                if !comment.previewReplies.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(comment.previewReplies, id: \.self) { reply in
                                            Text("\(reply.username)锛歕(reply.message)")
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                    }
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }

                                HStack(spacing: 16) {
                                    Label("鍥炲", systemImage: "bubble.left")
                                        .font(.footnote)
                                        .foregroundStyle(.tertiary)

                                    Label(statsText(comment.likeCount, fallback: "鐐硅禐"), systemImage: "hand.thumbsup")
                                        .font(.footnote)
                                        .foregroundStyle(.tertiary)

                                    Spacer()

                                    if comment.replyCount > 0 {
                                        Button(loadingReplyCommentIDs.contains(comment.id) ? "姝ｅ湪鍔犺浇..." : "鏌ョ湅 \(comment.replyCount) 鏉″洖澶?) {
                                            Task {
                                                await loadReplies(for: comment)
                                            }
                                        }
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.top, 2)

                                if let expandedReplies = expandedCommentReplies[comment.id], !expandedReplies.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(expandedReplies, id: \.self) { reply in
                                            Text("\(reply.username)锛歕(reply.message)")
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(3)
                                        }
                                    }
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
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
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(subtitle)
                    .font(.footnote)
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
            .font(.footnote)
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
                .font(.body)
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
            likeErrorMessage = "缂哄皯 aid锛屾殏鏃舵棤娉曠偣璧?
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
            viewModel.stats.likes = (viewModel.stats.likes ?? 0) + 1
        } catch {
            likeErrorMessage = error.localizedDescription
        }
    }

    private func coinCurrentVideo() async {
        guard let aid = viewModel.playbackItem.aid else {
            coinErrorMessage = "缂哄皯 aid锛屾殏鏃舵棤娉曟姇甯?
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
            viewModel.stats.coins = (viewModel.stats.coins ?? 0) + 1
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
                    username: "绯荤粺鎻愮ず",
                    message: "璇勮鍔犺浇澶辫触锛歕(error.localizedDescription)",
                    userID: nil,
                    avatarURL: nil,
                    timeText: "鏃堕棿鏈煡"
                )
            ]
        }
    }

    private func savePlaybackHistoryIfNeeded() {
        let currentSecond = Int(playbackPosition.rounded(.down))
        guard abs(currentSecond - lastSavedPlaybackSecond) >= 5 else { return }
        lastSavedPlaybackSecond = currentSecond
        VideoPlaybackHistoryStore.save(videoID: viewModel.playbackItem.id, position: playbackPosition)
    }

    private func loadReplies(for comment: VideoComment) async {
        guard let aid = viewModel.playbackItem.aid, let root = Int(comment.id) else { return }
        if expandedCommentReplies[comment.id] != nil {
            expandedCommentReplies[comment.id] = nil
            return
        }
        loadingReplyCommentIDs.insert(comment.id)
        defer { loadingReplyCommentIDs.remove(comment.id) }

        do {
            let replies = try await replyService.fetchReplyReplies(oid: aid, root: root)
            expandedCommentReplies[comment.id] = replies
        } catch {
            expandedCommentReplies[comment.id] = [
                VideoCommentPreviewReply(username: "绯荤粺鎻愮ず", message: "鍥炲鍔犺浇澶辫触锛歕(error.localizedDescription)")
            ]
        }
    }

    private func statsText(_ value: Int?, fallback: String) -> String {
        guard let value else { return fallback }
        if value >= 10_000 {
            let number = Double(value) / 10_000
            return String(format: "%.1f涓?, number)
        }
        return String(value)
    }

}

private enum DetailTab: Hashable {
    case intro
    case comments
    case related
}

private enum CommentSortMode: CaseIterable {
    case hot
    case latest

    var title: String {
        switch self {
        case .hot:
            return "鎸夌儹搴?
        case .latest:
            return "鎸夋椂闂?
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

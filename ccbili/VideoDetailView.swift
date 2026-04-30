import SwiftUI

struct VideoDetailView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.scenePhase) private var scenePhase

    @State private var viewModel: VideoDetailViewModel
    @State private var favoriteViewModel = VideoFavoriteViewModel()
    @State private var playbackProgress = VideoPlaybackProgressTracker()

    @State private var interactionService = VideoInteractionService()
    @State private var isSubmittingLike = false
    @State private var isSubmittingCoin = false
    @State private var isSwitchingQuality = false

    @State private var didLike = false
    @State private var didCoin = false

    @State private var likeErrorMessage: String?
    @State private var coinErrorMessage: String?
    @State private var commentSortMode: CommentSortMode = .hot
    @State private var restoredPlaybackPosition: Double?
    @State private var commentsSheetHeight: CGFloat = 360
    @State private var isShowingCommentsSheet = false
    @State private var selectedReplySheet: CommentReplySheetSelection?
    @State private var isLoadingComments = false
    @State private var isLoadingMoreComments = false
    @State private var commentsNextOffset: String?
    @State private var canLoadMoreComments = false
    @State private var commentErrorMessage: String?

    private let biliPink = Color(red: 251 / 255, green: 114 / 255, blue: 153 / 255)
    private let replyService = ReplyService()
    private let cardCornerRadius: CGFloat = 22
    private let pageHorizontalInset: CGFloat = 16
    private let playerAspectRatio: CGFloat = 16 / 9
    private let commentsSheetTopGap: CGFloat = 12
    private let relatedVideosDisplayLimit = 6

    init(item: VideoItem) {
        _viewModel = State(initialValue: VideoDetailViewModel(item: item))
    }

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = max(proxy.size.width - pageHorizontalInset * 2, 0)
            let playerWidth = proxy.size.width
            let playerHeight = min(playerWidth / playerAspectRatio, proxy.size.height * 0.7)
            let commentsAvailableHeight = proxy.size.height - playerHeight - commentsSheetTopGap - proxy.safeAreaInsets.bottom
            let availableCommentsHeight = max(commentsAvailableHeight, 1)
            ZStack(alignment: .top) {
                playerCardSection(height: playerHeight)
                    .frame(width: playerWidth)
                    .zIndex(0)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        videoInfoSection
                            .frame(width: contentWidth)

                        errorSection
                            .frame(width: contentWidth)

                        commentsButtonSection
                            .frame(width: contentWidth)

                        introContent
                            .frame(width: contentWidth)
                    }
                    .padding(.horizontal, pageHorizontalInset)
                    .padding(.top, playerHeight + 12)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .zIndex(1)
            }
            .background(Color(.systemGroupedBackground).opacity(0.62))
            .onAppear {
                commentsSheetHeight = availableCommentsHeight
            }
            .onChange(of: availableCommentsHeight) { _, newValue in
                commentsSheetHeight = newValue
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .restoresInteractivePopGesture()
        .onAppear {
            AppOrientationController.lockPortraitForPage()
            if let history = VideoPlaybackHistoryStore.history(for: viewModel.playbackItem.id) {
                restoredPlaybackPosition = history.position
                playbackProgress.position = history.position
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
            }

            if authManager.isLoggedIn && authManager.avatarURL == nil {
                await authManager.refreshLoginStatus()
            }
        }
        .onChange(of: commentSortMode) { _, newValue in
            guard isShowingCommentsSheet else { return }

            Task {
                await reloadComments(sortMode: newValue)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }

            Task {
                await BilibiliCookieStore.restoreEverywhere()
                await authManager.refreshLoginStatus(allowOfflineFallback: true)
                await viewModel.refreshPlaybackSourceAfterAuthenticationChange()
            }
        }
        .sheet(isPresented: $isShowingCommentsSheet) {
            commentsSheet
                .presentationDetents([.height(commentsSheetHeight)])
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled)
        }
        .onDisappear {
            savePlaybackHistoryIfNeeded(force: true)
            AppOrientationController.lockPortraitForPage()
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
                initialPosition: restoredPlaybackPosition ?? playbackProgress.position,
                onPositionChange: { position in
                    handlePlaybackPositionChange(position)
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
                        viewModel.isLoadingPlaybackSource ? "准备中" : "未就绪",
                        systemImage: viewModel.isLoadingPlaybackSource ? "arrow.triangle.2.circlepath" : "wifi.exclamationmark"
                    )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .liquidGlassSurface(cornerRadius: 999)
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

                    Text(viewModel.isLoadingPlaybackSource ? "正在解析视频地址" : "视频暂时无法播放")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    } else {
                        Text("请稍后重试，或尝试切换网络环境")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
        }
        .frame(height: height)
    }

    // MARK: - Info

    private var videoInfoSection: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                authorSummaryRow

                videoTitleText

                HStack(spacing: 8) {
                    metaChip(systemImage: "play.rectangle", text: statsText(viewModel.stats.views, fallback: "播放数待接入"))
                    metaChip(systemImage: "calendar", text: viewModel.uploadTimeText)
                    qualityPicker
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            actionSection
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .detailContainerGlass(cornerRadius: cardCornerRadius, interactive: true)
    }

    private var videoTitleText: some View {
        Text(normalizedVideoTitle)
            .font(.headline.weight(.semibold))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .lineLimit(nil)
            .allowsTightening(true)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    private var normalizedVideoTitle: String {
        viewModel.playbackItem.title
            .replacingOccurrences(
                of: #"\s*[\r\n]+\s*"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"[ \t]{2,}"#,
                with: " ",
                options: .regularExpression
            )
    }

    private var authorSummaryRow: some View {
        HStack(spacing: 12) {
            authorProfileLink {
                authorAvatarView
                    .frame(width: 42, height: 42)
                    .clipShape(Circle())
            }

            authorProfileLink {
                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.author?.name ?? viewModel.playbackItem.subtitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(viewModel.author?.followerText ?? "粉丝数待接入")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("+ 关注") {}
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .liquidGlassSurface(cornerRadius: 999, tint: biliPink.opacity(0.72), interactive: true)
        }
    }

    private var authorAvatarView: some View {
        RemoteImageView(
            url: viewModel.author?.avatarURL,
            maxPixelLength: 96,
            placeholder: {
                Circle()
                    .fill(Color(.quaternarySystemFill))
            },
            failureView: { _ in
                Circle()
                    .fill(Color(.quaternarySystemFill))
                    .overlay { Image(systemName: "person.fill").foregroundStyle(.secondary) }
            }
        )
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

                Text(viewModel.playbackSource?.qualityDescription ?? "清晰度")
                    .font(.caption.weight(.semibold))

                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .liquidGlassSurface(cornerRadius: 999, interactive: true)
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
        let currentPosition = playbackProgress.position
        isSwitchingQuality = true
        await viewModel.switchPlaybackQuality(to: option)
        playbackProgress.position = currentPosition
        restoredPlaybackPosition = currentPosition
        isSwitchingQuality = false
    }

    // MARK: - Actions

    private var actionSection: some View {
        HStack(spacing: 10) {
            actionIconButton(
                title: statsText(viewModel.stats.favorites, fallback: "收藏"),
                systemImage: favoriteViewModel.isFavorite ? "star.fill" : "star",
                tint: favoriteViewModel.isFavorite ? .yellow : .secondary,
                isLoading: favoriteViewModel.isLoading
            ) {
                Task {
                    await favoriteCurrentVideo()
                }
            }

            actionIconButton(
                title: statsText(viewModel.stats.likes, fallback: "点赞"),
                systemImage: didLike ? "hand.thumbsup.fill" : "hand.thumbsup",
                tint: didLike ? .blue : .secondary,
                isLoading: isSubmittingLike
            ) {
                Task {
                    await likeCurrentVideo()
                }
            }

            actionIconButton(
                title: statsText(viewModel.stats.coins, fallback: "投币"),
                systemImage: didCoin ? "bitcoinsign.circle.fill" : "bitcoinsign.circle",
                tint: didCoin ? .yellow : .secondary,
                isLoading: isSubmittingCoin
            ) {
                Task {
                    await coinCurrentVideo()
                }
            }

            ShareLink(item: shareURL) {
                actionIconLabel(
                    systemImage: "square.and.arrow.up",
                    tint: .secondary,
                    isLoading: false
                )
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded {
                viewModel.stats.shares = (viewModel.stats.shares ?? 0) + 1
            })
            .accessibilityLabel(statsText(viewModel.stats.shares, fallback: "分享"))
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

    // MARK: - Comments Entry

    private var commentsButtonSection: some View {
        Button {
            isShowingCommentsSheet = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.subheadline.weight(.semibold))

                Text("查看评论")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                if isLoadingComments {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "chevron.up")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .frame(height: 48)
            .frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
            .detailContainerGlass(cornerRadius: cardCornerRadius, interactive: true)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private var commentsSheet: some View {
        NavigationStack {
            List {
                commentsHeaderRow
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                commentInputRow
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 10, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                if isLoadingComments && viewModel.comments.isEmpty {
                    commentsLoadingRow(text: "正在加载评论...")
                        .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else if let commentErrorMessage, viewModel.comments.isEmpty {
                    commentsErrorRow(message: commentErrorMessage)
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else if viewModel.comments.isEmpty {
                    commentsEmptyRow
                        .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(viewModel.comments) { comment in
                        commentRow(comment)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .onAppear {
                                guard comment.id == viewModel.comments.last?.id else { return }

                                Task {
                                    await loadMoreCommentsIfNeeded(currentComment: comment)
                                }
                            }
                    }

                    commentsFooterRow
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 12, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .navigationTitle("评论")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        isShowingCommentsSheet = false
                    }
                }
            }
            .task {
                guard viewModel.comments.isEmpty, !isLoadingComments else { return }
                await reloadComments(sortMode: commentSortMode)
            }
            .sheet(item: $selectedReplySheet) { selection in
                CommentRepliesSheet(
                    aid: selection.aid,
                    root: selection.root,
                    comment: selection.comment,
                    replyService: replyService
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
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
                        ForEach(viewModel.relatedVideos.prefix(relatedVideosDisplayLimit)) { related in
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
        .detailContainerGlass(cornerRadius: cardCornerRadius, interactive: true)
    }

    // MARK: - Comments

    private var commentsHeaderRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("评论")
                    .font(.headline)

                Text(viewModel.comments.isEmpty ? "一起聊聊这条视频" : "\(viewModel.comments.count) 条正在显示")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
                .liquidGlassSurface(cornerRadius: 999, interactive: true)
            }
            .buttonStyle(.plain)
        }
    }

    private var commentInputRow: some View {
        Button {
        } label: {
            HStack(spacing: 10) {
                currentUserAvatarView

                HStack {
                    Text("说点什么吧...")
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
                .liquidGlassSurface(cornerRadius: 999, interactive: true)
            }
        }
        .buttonStyle(.plain)
    }

    private func commentsLoadingRow(text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(text)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func commentsErrorRow(message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.red)

            Button("重试加载评论") {
                Task {
                    await reloadComments(sortMode: commentSortMode)
                }
            }
            .buttonStyle(.plain)
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .liquidGlassSurface(cornerRadius: 999, interactive: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var commentsEmptyRow: some View {
        Text("暂无评论")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var commentsFooterRow: some View {
        if isLoadingMoreComments {
            commentsLoadingRow(text: "正在加载更多评论...")
                .font(.footnote)
        } else if let commentErrorMessage {
            Button("评论加载失败，点此重试") {
                Task {
                    await loadMoreComments()
                }
            }
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
        } else if !canLoadMoreComments {
            Text("没有更多评论了")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
        }
    }

    private func commentRow(_ comment: VideoComment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                commentAvatarView(comment)

                VStack(alignment: .leading, spacing: 6) {
                    Text(comment.username)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(comment.message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 12) {
                        Text(comment.timeText)
                            .foregroundStyle(.tertiary)
                        Text("回复")
                            .foregroundStyle(.tertiary)

                        Spacer(minLength: 8)

                        Label(statsText(comment.likeCount, fallback: "点赞"), systemImage: "hand.thumbsup")
                            .foregroundStyle(.tertiary)
                    }
                    .font(.footnote)

                    if !comment.previewReplies.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(comment.previewReplies, id: \.self) { reply in
                                (Text("\(reply.username)：")
                                    .foregroundStyle(.primary)
                                 + Text(reply.message)
                                    .foregroundStyle(.secondary))
                                    .font(.footnote)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.top, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if comment.replyCount > 0 {
                        Button {
                            presentReplies(for: comment)
                        } label: {
                            HStack(spacing: 4) {
                                Text(replyButtonTitle(for: comment))
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.bold))
                            }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(biliPink)
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()
                .padding(.leading, 44)
        }
    }

    private func commentAvatarView(_ comment: VideoComment) -> some View {
        RemoteImageView(
            url: comment.avatarURL,
            maxPixelLength: 72,
            placeholder: {
                Circle()
                    .fill(Color(.quaternarySystemFill))
            },
            failureView: { _ in
                Circle()
                    .fill(Color(.quaternarySystemFill))
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
            }
        )
        .transaction { transaction in
            transaction.animation = nil
        }
        .frame(width: 34, height: 34)
        .clipShape(Circle())
    }

    private var currentUserAvatarView: some View {
        Group {
            if let avatarURL = authManager.avatarURL {
                RemoteImageView(
                    url: avatarURL,
                    maxPixelLength: 80,
                    placeholder: {
                        Circle()
                            .fill(Color(.quaternarySystemFill))
                    },
                    failureView: { _ in
                        Circle()
                            .fill(Color(.quaternarySystemFill))
                            .overlay {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                    }
                )
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
                maxPixelLength: 220,
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
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
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
            actionIconLabel(systemImage: systemImage, tint: tint, isLoading: isLoading)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityLabel(title)
    }

    private func actionIconLabel(systemImage: String, tint: Color, isLoading: Bool) -> some View {
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
        .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var shareURL: URL {
        if let bvid = viewModel.playbackItem.resolvedBVID,
           let url = URL(string: "https://www.bilibili.com/video/\(bvid)") {
            return url
        }

        if let aid = viewModel.playbackItem.aid,
           let url = URL(string: "https://www.bilibili.com/video/av\(aid)") {
            return url
        }

        return AppConfig.webBaseURL
    }

    private func metaChip(systemImage: String, text: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(height: 34)
            .liquidGlassSurface(cornerRadius: 999)
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
        .liquidGlassSurface(cornerRadius: cardCornerRadius)
    }

    // MARK: - Actions

    private func favoriteCurrentVideo() async {
        let wasFavorite = favoriteViewModel.isFavorite
        await favoriteViewModel.favorite(video: viewModel.playbackItem)
        if !wasFavorite && favoriteViewModel.isFavorite {
            viewModel.stats.favorites = (viewModel.stats.favorites ?? 0) + 1
        }
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
            viewModel.stats.likes = (viewModel.stats.likes ?? 0) + 1
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
            viewModel.stats.coins = (viewModel.stats.coins ?? 0) + 1
        } catch {
            coinErrorMessage = error.localizedDescription
        }
    }

    private func reloadComments(sortMode: CommentSortMode) async {
        guard let aid = viewModel.playbackItem.aid else {
            viewModel.comments = []
            commentErrorMessage = "缺少 aid，暂时无法加载评论"
            return
        }

        isLoadingComments = true
        commentErrorMessage = nil
        commentsNextOffset = nil
        canLoadMoreComments = false

        defer {
            isLoadingComments = false
        }

        do {
            let page = try await replyService.fetchVideoReplyPage(
                oid: aid,
                type: 1,
                sort: sortMode.replySortValue,
                offset: nil
            )
            viewModel.comments = page.comments
            commentsNextOffset = page.nextOffset
            canLoadMoreComments = page.hasMore
        } catch {
            viewModel.comments = []
            commentErrorMessage = "评论加载失败：\(error.localizedDescription)"
        }
    }

    @ViewBuilder
    private func authorProfileLink<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if let author = viewModel.author, let mid = author.mid {
            NavigationLink {
                UserProfileView(mid: mid, username: author.name)
            } label: {
                content()
            }
            .buttonStyle(.plain)
        } else {
            content()
        }
    }

    private func loadMoreCommentsIfNeeded(currentComment: VideoComment) async {
        guard currentComment.id == viewModel.comments.last?.id else { return }
        await loadMoreComments()
    }

    private func loadMoreComments() async {
        guard let aid = viewModel.playbackItem.aid,
              canLoadMoreComments,
              !isLoadingComments,
              !isLoadingMoreComments else { return }

        isLoadingMoreComments = true
        commentErrorMessage = nil
        defer {
            isLoadingMoreComments = false
        }

        do {
            let page = try await replyService.fetchVideoReplyPage(
                oid: aid,
                type: 1,
                sort: commentSortMode.replySortValue,
                offset: commentsNextOffset
            )
            let existingIDs = Set(viewModel.comments.map(\.id))
            viewModel.comments.append(contentsOf: page.comments.filter { !existingIDs.contains($0.id) })
            commentsNextOffset = page.nextOffset
            canLoadMoreComments = page.hasMore
        } catch {
            commentErrorMessage = "更多评论加载失败：\(error.localizedDescription)"
        }
    }

    private func handlePlaybackPositionChange(_ position: Double) {
        playbackProgress.position = position
        savePlaybackHistoryIfNeeded()
    }

    private func savePlaybackHistoryIfNeeded(force: Bool = false) {
        let position = playbackProgress.position
        let currentPercent = Int((position * 100).rounded(.down))
        guard force || position >= 0.98 || abs(currentPercent - playbackProgress.lastSavedPercent) >= 3 else { return }
        playbackProgress.lastSavedPercent = currentPercent
        VideoPlaybackHistoryStore.save(videoID: viewModel.playbackItem.id, position: position)
    }

    private func presentReplies(for comment: VideoComment) {
        guard let aid = viewModel.playbackItem.aid, let root = Int(comment.id) else {
            commentErrorMessage = "缺少评论信息，暂时无法查看回复"
            return
        }
        selectedReplySheet = CommentReplySheetSelection(aid: aid, root: root, comment: comment)
    }

    private func replyButtonTitle(for comment: VideoComment) -> String {
        return "查看 \(comment.replyCount) 条回复"
    }

    private func statsText(_ value: Int?, fallback: String) -> String {
        guard let value else { return fallback }
        if value >= 10_000 {
            let number = Double(value) / 10_000
            return String(format: "%.1f万", number)
        }
        return String(value)
    }

}

private final class VideoPlaybackProgressTracker {
    var position: Double = 0
    var lastSavedPercent = -1
}

private struct CommentReplySheetSelection: Identifiable {
    let aid: Int
    let root: Int
    let comment: VideoComment

    var id: String {
        comment.id
    }
}

private struct CommentRepliesSheet: View {
    let aid: Int
    let root: Int
    let comment: VideoComment
    let replyService: ReplyService

    @Environment(\.dismiss) private var dismiss

    @State private var replies: [VideoCommentPreviewReply] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var nextPage: Int?
    @State private var hasMore = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text(comment.username)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            Spacer()

                            Text(comment.timeText)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }

                        Text(comment.message)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("全部回复") {
                    if isLoading && replies.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("正在加载回复...")
                                .foregroundStyle(.secondary)
                        }
                    } else if let errorMessage, replies.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(errorMessage)
                                .font(.subheadline)
                                .foregroundStyle(.red)

                            Button("重新加载") {
                                Task {
                                    await reloadReplies()
                                }
                            }
                        }
                    } else if replies.isEmpty {
                        Text("暂无回复")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(replies.enumerated()), id: \.offset) { _, reply in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(reply.username)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)

                                Text(reply.message)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }

                        if hasMore {
                            Button {
                                Task {
                                    await loadMoreReplies()
                                }
                            } label: {
                                HStack {
                                    Spacer()
                                    if isLoadingMore {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Text("加载更多回复")
                                    }
                                    Spacer()
                                }
                            }
                            .disabled(isLoadingMore)
                        }
                    }
                }
            }
            .navigationTitle("回复")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadInitialRepliesIfNeeded()
            }
        }
    }

    private func loadInitialRepliesIfNeeded() async {
        guard replies.isEmpty, !isLoading else { return }
        await reloadReplies()
    }

    private func reloadReplies() async {
        isLoading = true
        errorMessage = nil
        nextPage = nil
        hasMore = false

        defer {
            isLoading = false
        }

        do {
            let page = try await replyService.fetchReplyReplyPage(oid: aid, root: root, page: 1)
            replies = page.replies
            nextPage = page.nextPage
            hasMore = page.hasMore
        } catch {
            replies = []
            errorMessage = "回复加载失败：\(error.localizedDescription)"
        }
    }

    private func loadMoreReplies() async {
        guard hasMore, !isLoading, !isLoadingMore else { return }

        isLoadingMore = true
        errorMessage = nil
        defer {
            isLoadingMore = false
        }

        do {
            let page = try await replyService.fetchReplyReplyPage(oid: aid, root: root, page: nextPage ?? 1)
            replies.append(contentsOf: page.replies)
            nextPage = page.nextPage
            hasMore = page.hasMore
        } catch {
            errorMessage = "更多回复加载失败：\(error.localizedDescription)"
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

private extension View {
    @ViewBuilder
    func detailContainerGlass(cornerRadius: CGFloat, interactive: Bool = false) -> some View {
        if #available(iOS 26, *) {
            if interactive {
                self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color(.separator).opacity(0.08), lineWidth: 0.5)
                }
        }
    }
}

private extension View {
    @ViewBuilder
    func liquidGlassSurface(cornerRadius: CGFloat, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26, *) {
            if let tint {
                if interactive {
                    self.glassEffect(.regular.tint(tint).interactive(), in: .rect(cornerRadius: cornerRadius))
                } else {
                    self.glassEffect(.regular.tint(tint), in: .rect(cornerRadius: cornerRadius))
                }
            } else if interactive {
                self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color(.separator).opacity(0.08), lineWidth: 0.5)
                }
        }
    }
}

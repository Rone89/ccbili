import SwiftUI

struct UserProfileView: View {
    @State private var viewModel: UserProfileViewModel

    private let columns = [
        GridItem(.flexible(), spacing: 12, alignment: .top),
        GridItem(.flexible(), spacing: 12, alignment: .top)
    ]

    init(user: SearchUserItem) {
        _viewModel = State(initialValue: UserProfileViewModel(mid: user.mid, fallback: user))
    }

    init(mid: Int, username: String) {
        let fallback = SearchUserItem(
            id: String(mid),
            mid: mid,
            name: username,
            sign: "这个人还没有签名",
            followerText: "粉丝数待获取",
            videoText: "投稿待获取",
            avatarURL: nil
        )
        _viewModel = State(initialValue: UserProfileViewModel(mid: mid, fallback: fallback))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                profileHeader
                errorSection
                archiveSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(viewModel.profile?.name ?? "个人主页")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if viewModel.videos.isEmpty {
                await viewModel.load()
            }
        }
        .refreshable {
            await viewModel.load()
        }
    }

    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                RemoteImageView(
                    url: viewModel.profile?.avatarURL,
                    placeholder: {
                        Circle()
                            .fill(Color(.tertiarySystemGroupedBackground))
                            .overlay { ProgressView() }
                    },
                    failureView: { _ in
                        Circle()
                            .fill(Color(.tertiarySystemGroupedBackground))
                            .overlay {
                                Image(systemName: "person.fill")
                                    .foregroundStyle(.secondary)
                            }
                    }
                )
                .frame(width: 68, height: 68)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 8) {
                    Text(viewModel.profile?.name ?? "加载中...")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)

                    HStack(spacing: 10) {
                        profileMetric(viewModel.profile?.followerText ?? "粉丝 --")
                        profileMetric(viewModel.profile?.videoText ?? "投稿 --")
                    }
                }

                Spacer()
            }

            Text(viewModel.profile?.sign ?? "正在加载个人简介...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private var errorSection: some View {
        if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
                .font(.subheadline)
                .foregroundStyle(.red)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var archiveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("投稿视频")
                .font(.headline)

            if viewModel.isLoading && viewModel.videos.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在加载投稿...")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else if viewModel.videos.isEmpty {
                ContentUnavailableView("暂无投稿", systemImage: "video", description: Text("这个用户暂时没有可展示的视频"))
                    .frame(maxWidth: .infinity)
            } else {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(viewModel.videos) { item in
                        NavigationLink {
                            VideoDetailView(item: item)
                        } label: {
                            VideoListRowView(
                                title: item.title,
                                subtitle: item.subtitle,
                                accessoryText: item.bvid,
                                coverURL: item.coverURL
                            )
                        }
                        .buttonStyle(.plain)
                        .task {
                            await viewModel.loadMoreIfNeeded(currentItem: item)
                        }
                    }
                }

                if viewModel.isLoadingMore {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在加载更多投稿...")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
                } else if !viewModel.canLoadMore {
                    Text("没有更多投稿了")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }
            }
        }
    }

    private func profileMetric(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
    }
}

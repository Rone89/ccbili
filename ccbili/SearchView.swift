//  SearchView.swift
//  ccbili
//

import SwiftUI

struct SearchView: View {
    @State private var viewModel = SearchViewModel()

    private let columns = [
        GridItem(.flexible(), spacing: 12, alignment: .top),
        GridItem(.flexible(), spacing: 12, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                searchBar
                scopePicker
                searchHistorySection
                loadingSection
                errorSection
                resultsSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .background(Color(.systemBackground))
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.large)
        .onSubmit(of: .text) {
            Task {
                await viewModel.search()
            }
        }
    }

    private var scopePicker: some View {
        Picker("搜索类型", selection: $viewModel.scope) {
            ForEach(SearchViewModel.Scope.allCases) { scope in
                Text(scope.rawValue).tag(scope)
            }
        }
        .pickerStyle(.segmented)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("搜索视频、番剧或 UP 主", text: $viewModel.keyword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(.thinMaterial, in: Capsule())

            Button("搜索") {
                Task {
                    await viewModel.search()
                }
            }
            .font(.subheadline.weight(.semibold))
        }
    }

    @ViewBuilder
    private var searchHistorySection: some View {
        if !viewModel.searchHistory.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("搜索历史")
                        .font(.headline)

                    Spacer()

                    Button("清空") {
                        viewModel.clearHistory()
                    }
                    .font(.subheadline)
                    .disabled(viewModel.searchHistory.isEmpty)
                }

                historyTagsView
            }
        }
    }

    @ViewBuilder
    private var loadingSection: some View {
        if viewModel.isLoading {
            HStack(spacing: 10) {
                ProgressView()
                Text("正在搜索...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let errorMessage = viewModel.errorMessage {
            VStack(alignment: .leading, spacing: 8) {
                Text("搜索错误")
                    .font(.headline)

                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("搜索结果")
                    .font(.headline)

                let resultCount = viewModel.scope == .videos ? viewModel.results.count : viewModel.userResults.count
                if viewModel.hasSearched && resultCount > 0 {
                    Text("\(resultCount) 条")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if !viewModel.hasSearched && viewModel.results.isEmpty && viewModel.userResults.isEmpty {
                ContentUnavailableView(
                    "输入关键词开始搜索",
                    systemImage: "magnifyingglass",
                    description: Text("也可以点选搜索历史快速开始")
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
            } else if !viewModel.isLoading && activeResultsAreEmpty {
                ContentUnavailableView(
                    "暂无搜索结果",
                    systemImage: "magnifyingglass",
                    description: Text("试试更换关键词")
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
            } else if viewModel.scope == .users {
                usersResultList
            } else {
                videosResultGrid
            }
        }
    }

    private var activeResultsAreEmpty: Bool {
        switch viewModel.scope {
        case .videos:
            return viewModel.results.isEmpty
        case .users:
            return viewModel.userResults.isEmpty
        }
    }

    private var videosResultGrid: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(viewModel.results) { item in
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

            paginationFooter(isEmpty: viewModel.results.isEmpty)
        }
    }

    private var usersResultList: some View {
        VStack(spacing: 12) {
            ForEach(viewModel.userResults) { user in
                NavigationLink {
                    UserProfileView(user: user)
                } label: {
                    userResultRow(user)
                }
                .buttonStyle(.plain)
                .task {
                    await viewModel.loadMoreUsersIfNeeded(currentItem: user)
                }
            }

            paginationFooter(isEmpty: viewModel.userResults.isEmpty)
        }
    }

    @ViewBuilder
    private func paginationFooter(isEmpty: Bool) -> some View {
        if viewModel.isLoadingMore {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("正在加载更多结果...")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
        } else if viewModel.hasSearched && !viewModel.canLoadMore && !isEmpty {
            Text("没有更多结果了")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
        }
    }

    private func userResultRow(_ user: SearchUserItem) -> some View {
        HStack(spacing: 12) {
            RemoteImageView(
                url: user.avatarURL,
                placeholder: {
                    Circle()
                        .fill(Color(.tertiarySystemGroupedBackground))
                        .overlay { ProgressView().controlSize(.small) }
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
            .frame(width: 52, height: 52)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(user.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(user.sign)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(user.followerText)
                    Text(user.videoText)
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var historyTagsView: some View {
        FlexibleTagFlowView(tags: viewModel.searchHistory) { history in
            Button {
                viewModel.applyHistory(history)
                Task {
                    await viewModel.search()
                }
            } label: {
                Text(history)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

private struct FlexibleTagFlowView: View {
    let tags: [String]
    let content: (String) -> AnyView

    init(tags: [String], @ViewBuilder content: @escaping (String) -> some View) {
        self.tags = tags
        self.content = { tag in AnyView(content(tag)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let rows = makeRows(from: tags, maxCountPerRow: 4)

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 10) {
                    ForEach(row, id: \.self) { tag in
                        content(tag)
                    }

                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func makeRows(from tags: [String], maxCountPerRow: Int) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []

        for tag in tags {
            if currentRow.count >= maxCountPerRow {
                rows.append(currentRow)
                currentRow = [tag]
            } else {
                currentRow.append(tag)
            }
        }

        if !currentRow.isEmpty {
            rows.append(currentRow)
        }

        return rows
    }
}

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
            Text("搜索结果")
                .font(.headline)

            if !viewModel.isLoading && viewModel.results.isEmpty {
                ContentUnavailableView(
                    "暂无搜索结果",
                    systemImage: "magnifyingglass",
                    description: Text("试试更换关键词")
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
            } else {
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
                    }
                }
            }
        }
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

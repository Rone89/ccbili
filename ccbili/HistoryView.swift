//
//  HistoryView.swift
//  ccbili
//
//  Created by chuzu  on 2026/4/25.
//


import SwiftUI

struct HistoryView: View {
    @State private var viewModel = HistoryViewModel()
    @State private var playbackHistories: [String: VideoPlaybackHistory] = [:]

    var body: some View {
        List {
            if viewModel.isLoading && viewModel.items.isEmpty {
                Section("历史观看") {
                    HStack {
                        ProgressView()
                        Text("正在加载历史记录...")
                    }
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Section("错误信息") {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section("历史观看") {
                if !viewModel.isLoading && viewModel.items.isEmpty {
                    Text("暂无历史记录")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.items) { item in
                        NavigationLink {
                            VideoDetailView(item: item)
                        } label: {
                            VideoListRowView(
                                title: item.title,
                                subtitle: item.subtitle,
                                accessoryText: item.bvid,
                                coverURL: item.coverURL,
                                continueWatchingText: continueWatchingText(for: item),
                                progress: playbackHistories[item.id]?.progressFraction
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle("历史观看")
        .task {
            refreshPlaybackHistories()
            if viewModel.items.isEmpty {
                await viewModel.load()
            }
        }
        .refreshable {
            await viewModel.load()
            refreshPlaybackHistories()
        }
        .onAppear {
            refreshPlaybackHistories()
        }
    }

    private func refreshPlaybackHistories() {
        playbackHistories = VideoPlaybackHistoryStore.histories()
    }

    private func continueWatchingText(for item: VideoItem) -> String? {
        guard let history = playbackHistories[item.id] else { return nil }
        return "继续观看到 \(history.displayText)"
    }
}

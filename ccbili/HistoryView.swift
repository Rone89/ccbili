//
//  HistoryView.swift
//  ccbili
//
//  Created by chuzu  on 2026/4/25.
//


import SwiftUI

struct HistoryView: View {
    @Binding var isTabBarHidden: Bool
    @State private var viewModel = HistoryViewModel()

    init(isTabBarHidden: Binding<Bool> = .constant(false)) {
        _isTabBarHidden = isTabBarHidden
    }

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
                            VideoDetailView(item: item, isTabBarHidden: $isTabBarHidden)
                        } label: {
                            VideoListRowView(
                                title: item.title,
                                subtitle: item.subtitle,
                                accessoryText: item.bvid,
                                coverURL: item.coverURL
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle("历史观看")
        .task {
            if viewModel.items.isEmpty {
                await viewModel.load()
            }
        }
        .refreshable {
            await viewModel.load()
        }
    }
}

import LenKit
import SwiftUI

struct SearchView: View {
    @State private var model = SearchModel()

    @PlatformMetrics private var metrics
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.lenBackground)
            .searchable(text: $model.query, prompt: "搜索电影、剧集")
            #if DEBUG
            .task { if model.query.isEmpty, let text = LaunchOptions.searchText { model.query = text } }
            #endif
            #if !os(tvOS)
            .navigationTitle("搜索")
            #endif
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle:
            ContentUnavailableView("搜索电影和剧集", systemImage: "magnifyingglass", description: Text("输入片名，结果会随输入实时出现"))
        case .loading:
            ProgressView("正在搜索…").controlSize(.large)
        case .empty(let text):
            ContentUnavailableView.search(text: text)
        case .failed(let message):
            FailureView(message: message, retry: model.retry)
        case .results(let items):
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(items.count) 部").font(.subheadline).foregroundStyle(.secondary)
                    if usesList {
                        LazyVStack(spacing: 0) {
                            ForEach(items) { SearchResultRow(item: $0) }
                        }
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: metrics.gridMinWidth), spacing: metrics.itemSpacing, alignment: .top)],
                                  spacing: metrics.itemSpacing * 1.4) {
                            ForEach(items) { PosterLink(item: $0) }
                        }
                    }
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.bottom, 24)
            }
        }
    }

    /// iPhone 上用列表，信息更多
    private var usesList: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }
}

private struct SearchResultRow: View {
    let item: MediaSummary

    var body: some View {
        NavigationLink(value: DetailRoute(summary: item)) {
            HStack(spacing: 14) {
                PosterImage(url: item.posterURL, title: item.title, displayWidth: 64)
                    .frame(width: 64, height: 96)
                    .clipShape(.rect(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.body.weight(.semibold)).lineLimit(1)
                    Text([item.kind.displayName, item.subtitle].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(extra).font(.footnote).foregroundStyle(.tertiary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var extra: String {
        [item.kind == .tv ? item.badge : nil, item.director.map { "导演 \($0)" }].compactMap(\.self).joined(separator: " · ")
    }
}

import LenKit
import SwiftUI

struct HomeView: View {
    var isActive = true
    @State private var model = HomeModel()
    @State private var refreshRequest: UUID?
    @Environment(\.scenePhase) private var scenePhase

    @PlatformMetrics private var metrics

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: metrics.sectionSpacing) {
                if let feed = model.feed.value {
                    let featured = feed.featured()
                    if !featured.isEmpty { FeaturedCarousel(items: featured) }
                }

                if !model.continueWatching.isEmpty {
                    Shelf(title: "继续观看") {
                        ForEach(model.continueWatching) { ContinueLink(record: $0) }
                    }
                }

                switch model.feed {
                case .idle, .loading:
                    LoadingView()
                case .failed(let message):
                    FailureView(message: message) { Task { await model.load() } }
                case .loaded(let feed):
                    shelf("热门电影", feed.hotMovies)
                    shelf("热门剧集", feed.hotSeries)
                }
            }
            .padding(.bottom, metrics.sectionSpacing)
        }
        .background(Color.lenBackground)
        .task { await model.load() }
        .task { await model.observeHistory() }
        .task(id: refreshRequest) {
            guard refreshRequest != nil else { return }
            defer { refreshRequest = nil }
            await model.load(isRefresh: true)
        }
        .task(id: model.refreshNotice?.id) {
            guard model.refreshNotice != nil else { return }
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            model.dismissRefreshNotice()
        }
        .overlay(alignment: .top) {
            if model.isLoading, model.feed.value != nil {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("正在刷新首页…")
                }
                .padding()
                .background(.regularMaterial, in: .capsule)
                .accessibilityIdentifier("home.refreshing")
                .allowsHitTesting(false)
            } else if let notice = model.refreshNotice {
                NoticeToast(text: notice.message, isWarning: notice.isWarning)
                    .accessibilityIdentifier("home.refreshResult")
                    .allowsHitTesting(false)
            }
        }
        #if os(tvOS)
        .background {
            TVHomeRefreshGesture(isEnabled: isActive && scenePhase == .active, action: requestRefresh)
                .frame(width: 1, height: 1)
        }
        #elseif os(macOS)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: requestRefresh) {
                    Label("刷新首页", systemImage: "arrow.clockwise")
                }
                .disabled(model.isLoading || !isActive)
                .accessibilityIdentifier("home.refresh")
                .keyboardShortcut("r", modifiers: .command)
                .help("刷新首页（⌘R）")
            }
        }
        #endif
        #if os(iOS)
        .refreshable { await model.load(isRefresh: true) }
        #endif
        #if !os(tvOS)
        .navigationTitle("冷映")
        #endif
    }

    private func requestRefresh() {
        guard isActive, !model.isLoading else { return }
        refreshRequest = UUID()
    }

    @ViewBuilder
    private func shelf(_ title: String, _ items: [MediaSummary]) -> some View {
        if !items.isEmpty {
            Shelf(title: title, note: "\(items.count) 部") {
                ForEach(items) { PosterLink(item: $0, width: metrics.posterWidth) }
            }
        }
    }
}

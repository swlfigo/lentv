import LenKit
import SwiftUI

struct TrendingView: View {
    @State private var model = TrendingModel()
    @PlatformMetrics private var metrics

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: metrics.itemSpacing) {
                #if os(tvOS)
                HStack {
                    Text("热播").font(.title2.bold())
                    Spacer()
                    Button { Task { await model.reload() } } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(ChipButtonStyle(isSelected: false))
                    .disabled(model.isLoading)
                }
                .padding(.bottom, metrics.itemSpacing)
                #endif

                if model.phase == .loading {
                    LoadingView()
                } else if model.items.isEmpty, model.phase == .exhausted {
                    ContentUnavailableView("暂无热播内容", systemImage: "flame")
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: metrics.gridMinWidth), spacing: metrics.itemSpacing, alignment: .top)],
                        spacing: metrics.itemSpacing * 1.4
                    ) {
                        ForEach(model.items) { item in
                            PosterLink(item: item)
                                .task { await model.loadMoreIfNeeded(after: item) }
                        }
                    }
                    #if os(tvOS)
                    .focusSection()
                    #endif
                }

                if case .failed(let message) = model.phase {
                    FailureView(message: message) { Task { await model.loadNext() } }
                } else if model.phase == .loadingMore {
                    ProgressView().frame(maxWidth: .infinity).padding()
                } else if model.phase == .idle, !model.items.isEmpty {
                    Button("加载更多") { Task { await model.loadNext() } }
                        #if os(tvOS)
                        .buttonStyle(ChipButtonStyle(isSelected: false))
                        #endif
                        .frame(maxWidth: .infinity).padding()
                }
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.vertical, metrics.itemSpacing)
            .padding(.bottom, 32)
        }
        .background(Color.lenBackground)
        .task { await model.loadIfNeeded() }
        #if os(iOS)
        .refreshable { await model.reload() }
        #elseif os(macOS)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await model.reload() } } label: {
                    Label("刷新热播", systemImage: "arrow.clockwise")
                }
                .disabled(model.isLoading)
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        #endif
        #if !os(tvOS)
        .navigationTitle("热播")
        #endif
    }
}

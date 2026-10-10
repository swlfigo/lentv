import LenKit
import SwiftUI

struct DetailView: View {
    @State private var model: DetailModel

    @PlatformMetrics private var metrics
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    #if os(tvOS)
    @Environment(\.dismiss) private var dismiss
    #endif

    init(route: DetailRoute) {
        _model = State(initialValue: DetailModel(route: route))
    }

    var body: some View {
        content
            .background { Backdrop(url: model.detail.value?.posterURL ?? model.summary.posterURL, title: title) }
            .task { await model.load() }
            #if os(tvOS)
            // tvOS 惯例：详情页全屏显示，按遥控器返回键回到上一层。
            // TabView 默认会把返回键用来把焦点移回标签栏，所以这里自己处理返回
            .toolbar(.hidden, for: .tabBar)
            .onExitCommand { dismiss() }
            .fullScreenCover(item: $model.playback, onDismiss: model.stopPlayback) { controller in
                TVPlayerScreen(controller: controller)
            }
            #else
            .onDisappear {
                // 进入全屏或画中画时详情页也会“消失”，这时不能停止播放
                if model.playback?.keepsPlayingWhenHidden != true { model.stopPlayback() }
            }
            .navigationTitle(title)
            #endif
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
    }

    private var title: String { model.detail.value?.title ?? model.summary.title }

    @ViewBuilder
    private var content: some View {
        switch model.detail {
        case .idle, .loading:
            LoadingView().frame(maxHeight: .infinity)
        case .failed(let message):
            FailureView(message: message) { Task { await model.load() } }
        case .loaded(let detail):
            loaded(detail)
        }
    }

    @ViewBuilder
    private func loaded(_ detail: MediaDetail) -> some View {
        #if os(tvOS)
        ScrollView {
            HStack(alignment: .top, spacing: 80) {
                PosterImage(url: detail.posterURL, title: detail.title, displayWidth: 400)
                    .frame(width: 400, height: 600)
                    .clipShape(.rect(cornerRadius: 22))
                    .shadow(color: .black.opacity(0.5), radius: 40, y: 30)
                VStack(alignment: .leading, spacing: 36) {
                    DetailInfo(detail: detail)
                    playButton
                    LineSection(model: model, detail: detail)
                    episodes(detail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 40)
        }
        .scrollClipDisabled()
        #elseif os(iOS)
        // 横屏（iPhone 横屏、iPad 横屏）用双栏：单栏时播放器按全宽算出的高度会超过屏幕高度
        GeometryReader { proxy in
            if proxy.size.width > proxy.size.height {
                twoColumns(detail, panelWidth: proxy.size.width < 1000 ? 300 : 380)
            } else {
                singleColumn(detail)
            }
        }
        #else
        singleColumn(detail)
        #endif
    }

    #if os(iOS)
    private func twoColumns(_ detail: MediaDetail, panelWidth: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 28) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    InlinePlayerArea(model: model, detail: detail)
                    DetailInfo(detail: detail)
                }
                .padding(.bottom, 24)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    LineSection(model: model, detail: detail)
                    episodes(detail)
                }
                .padding(20)
            }
            .frame(width: panelWidth)
            .background(Color.lenSurface, in: .rect(cornerRadius: 18))
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.bottom, 16)
    }
    #endif

    #if !os(tvOS)
    private func singleColumn(_ detail: MediaDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                InlinePlayerArea(model: model, detail: detail)
                DetailInfo(detail: detail)
                LineSection(model: model, detail: detail)
                episodes(detail)
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.bottom, 32)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
    }
    #endif

    @ViewBuilder
    private func episodes(_ detail: MediaDetail) -> some View {
        if detail.lines.contains(where: { $0.episodes.count > 1 }), let line = detail.lines[safe: model.activeLine] {
            EpisodeGrid(line: line, highlighted: model.activeEpisode) { model.play(episode: $0.number) }
        }
    }

    #if os(tvOS)
    private var playButton: some View {
        Button(action: model.play) {
            Label(model.playButtonTitle, systemImage: "play.fill")
                .padding(.horizontal, 16)
        }
        .buttonStyle(ChipButtonStyle(isSelected: true))
    }
    #endif
}

/// 片名、评分、年份地区、导演主演、简介
private struct DetailInfo: View {
    let detail: MediaDetail

    @State private var isSummaryExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(detail.title)
                .font(titleFont)

            HStack(spacing: 10) {
                if let rating = detail.rating {
                    Label(rating, systemImage: "star.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.lenSurface, in: .rect(cornerRadius: 8))
                }
                if detail.kind == .tv, let updateInfo = detail.updateInfo {
                    Text(updateInfo)
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.lenSurface, in: .rect(cornerRadius: 8))
                }
                Text(detail.metadataLine.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                if let director = detail.director { row("导演", director) }
                if let actors = detail.actors { row("主演", actors.replacingOccurrences(of: ",", with: "、")) }
            }

            if let summary = detail.summary {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(isSummaryExpanded ? nil : 3)
                    #if !os(tvOS)
                    .onTapGesture { isSummaryExpanded.toggle() }
                    #endif
            }
        }
    }

    #if os(tvOS)
    private let titleFont = Font.system(size: 64, weight: .heavy)
    #else
    private let titleFont = Font.title.weight(.heavy)
    #endif

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).foregroundStyle(.tertiary)
            Text(value).foregroundStyle(.secondary).lineLimit(1)
        }
        .font(.callout)
    }
}

/// 线路选择。播放中切换会保留进度；没有当前这一集的线路不可选。
private struct LineSection: View {
    let model: DetailModel
    let detail: MediaDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("播放线路").font(.headline)
                Text("\(detail.lines.count) 条").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                if let playback = model.playback {
                    Text("正在播放 \(playback.subtitle)").font(.caption).foregroundStyle(.secondary)
                }
            }
            if detail.lines.isEmpty {
                Text("暂时没有可播放的线路").foregroundStyle(.secondary)
            } else {
                ChipRow(
                    items: Array(detail.lines.indices),
                    selection: model.activeLine,
                    title: { detail.lines[$0].name },
                    isEnabled: { index in
                        guard let episode = model.playback?.cursor.episodeNumber else { return true }
                        return detail.lines[index].episode(number: episode)?.isPlayable == true
                    },
                    horizontalPadding: 0,
                    onSelect: model.selectLine)
            }
        }
    }
}

#if !os(tvOS)
/// iPhone / iPad / Mac：详情页顶部的播放器，未播放时显示模糊海报和播放按钮
private struct InlinePlayerArea: View {
    let model: DetailModel
    let detail: MediaDetail

    var body: some View {
        ZStack {
            if let controller = model.playback {
                PlayerSurface(controller: controller)
                if case .failed(let message) = controller.phase {
                    FailureOverlay(message: message, retry: controller.retry)
                }
                PlaybackNoticeOverlay(controller: controller)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)
            } else {
                PosterImage(url: detail.posterURL, title: detail.title, displayWidth: 160, showsTitleWhileLoading: false)
                    .blur(radius: 30)
                    .overlay(Color.black.opacity(0.35))
                Button(action: model.play) {
                    Label(model.playButtonTitle, systemImage: "play.fill")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(.white, in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(detail.firstCursor == nil)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .background(.black)
        .clipShape(.rect(cornerRadius: 12))
    }
}

private struct FailureOverlay: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").font(.title).foregroundStyle(.orange)
            Text("无法播放").font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("重试", action: retry).buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.75))
    }
}
#endif

/// 模糊海报做背景，取代后端缺失的横版剧照
struct Backdrop: View {
    let url: URL?
    let title: String

    var body: some View {
        PosterImage(url: url, title: title, displayWidth: 120, showsTitleWhileLoading: false)
            .blur(radius: 90)
            .opacity(0.45)
            .overlay(Color.lenBackground.opacity(0.4))
            .background(Color.lenBackground)
            .ignoresSafeArea()
    }
}

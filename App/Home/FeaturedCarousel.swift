import LenKit
import SwiftUI

/// 首页顶部的推荐轮播，横向分页滚动，每 7 秒自动翻页。
/// tvOS 上焦点在卡片按钮上时，翻页后焦点跟到下一张卡片的同一个按钮，避免留在看不见的卡片上。
struct FeaturedCarousel: View {
    let items: [MediaSummary]

    @State private var currentID: MediaSummary.ID?
    @FocusState private var focus: HeroFocus?
    @PlatformMetrics private var metrics

    private static let interval: Duration = .seconds(7)

    var body: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal) {
                // 推荐最多几张，全部常驻：Lazy 布局会回收滑走的卡片，回到第一张时焦点会找不到目标
                HStack(spacing: 0) {
                    ForEach(items) { item in
                        FeaturedCard(item: item, focus: $focus)
                            .padding(.horizontal, metrics.horizontalPadding)
                            .containerRelativeFrame(.horizontal)
                            .id(item.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $currentID)
            .scrollIndicators(.never)
            .scrollClipDisabled()
            .frame(height: metrics.heroHeight)
            #if os(tvOS)
            .focusSection()
            #endif

            if items.count > 1 {
                PageDots(count: items.count, index: currentIndex)
            }
        }
        // 翻页或焦点移动后重新计时，避免用户正要按确认键时卡片换掉
        .task(id: AutoAdvanceKey(current: currentID, focus: focus)) {
            await autoAdvance()
        }
    }

    private var currentIndex: Int {
        items.firstIndex { $0.id == currentID } ?? 0
    }

    private func autoAdvance() async {
        guard items.count > 1 else { return }
        try? await Task.sleep(for: Self.interval)
        guard !Task.isCancelled else { return }
        let next = items[(currentIndex + 1) % items.count].id
        withAnimation(.easeInOut(duration: 0.6)) {
            currentID = next
        }
        // 焦点跟到下一张卡片的同一个按钮；稍后再设，等滚动开始后目标按钮已在布局中
        if let focus {
            let target = focus.moved(to: next)
            Task {
                try? await Task.sleep(for: .milliseconds(80))
                self.focus = target
            }
        }
    }
}

/// 推荐卡片上的按钮焦点
enum HeroFocus: Hashable {
    case play(MediaSummary.ID)
    case info(MediaSummary.ID)

    func moved(to id: MediaSummary.ID) -> HeroFocus {
        switch self {
        case .play: .play(id)
        case .info: .info(id)
        }
    }
}

private struct AutoAdvanceKey: Equatable {
    let current: MediaSummary.ID?
    let focus: HeroFocus?
}

private struct FeaturedCard: View {
    let item: MediaSummary
    let focus: FocusState<HeroFocus?>.Binding

    @PlatformMetrics private var metrics

    var body: some View {
        HStack(alignment: .top, spacing: metrics.itemSpacing * 1.4) {
            #if !os(tvOS)
            poster
            #endif
            VStack(alignment: .leading, spacing: spacing) {
                Text(eyebrow)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                Text(item.title)
                    .font(titleFont)
                    .lineLimit(2)
                Text(meta)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let summary = item.summary {
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: 900, alignment: .leading)
                }
                Spacer(minLength: 0)
                // 窄屏放不下时换成短文字
                ViewThatFits(in: .horizontal) {
                    actions(playTitle: item.kind == .tv ? "播放 第1集" : "播放", infoTitle: "详情")
                    actions(playTitle: "播放", infoTitle: nil)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            #if os(tvOS)
            poster
            #endif
        }
        .padding(cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            PosterImage(url: item.posterURL, title: item.title, displayWidth: 160, showsTitleWhileLoading: false)
                .blur(radius: 50)
                .overlay(Color.black.opacity(0.4))
        }
        .clipShape(.rect(cornerRadius: metrics.cornerRadius * 2))
    }

    private func actions(playTitle: String, infoTitle: String?) -> some View {
        HStack(spacing: 12) {
            NavigationLink(value: DetailRoute(summary: item, autoplay: true)) {
                Label(playTitle, systemImage: "play.fill")
            }
            .buttonStyle(ChipButtonStyle(isSelected: true))
            .focused(focus, equals: .play(item.id))
            NavigationLink(value: DetailRoute(summary: item)) {
                if let infoTitle {
                    Label(infoTitle, systemImage: "info.circle")
                } else {
                    Image(systemName: "info.circle").accessibilityLabel("详情")
                }
            }
            .buttonStyle(ChipButtonStyle(isSelected: false))
            .focused(focus, equals: .info(item.id))
        }
        .fixedSize()
    }

    private var poster: some View {
        let height = metrics.heroHeight - cardPadding * 2
        return PosterImage(url: item.posterURL, title: item.title, displayWidth: height * 2 / 3)
            .frame(width: height * 2 / 3, height: height)
            .clipShape(.rect(cornerRadius: metrics.cornerRadius))
            .shadow(color: .black.opacity(0.4), radius: 20, y: 12)
    }

    private var eyebrow: String {
        ["今日推荐", item.category].compactMap(\.self).joined(separator: " · ")
    }

    private var meta: String {
        var parts = [item.year.map(String.init), item.region].compactMap(\.self)
        if item.kind == .tv, let count = item.totalEpisodes ?? item.currentEpisode { parts.append("\(count) 集") }
        if let actors = item.actors { parts.append(actors.replacingOccurrences(of: ",", with: "、")) }
        return parts.joined(separator: " · ")
    }

    #if os(tvOS)
    private let titleFont = Font.system(size: 88, weight: .heavy)
    private let spacing: CGFloat = 16
    private let cardPadding: CGFloat = 50
    #elseif os(macOS)
    private let titleFont = Font.system(size: 38, weight: .heavy)
    private let spacing: CGFloat = 8
    private let cardPadding: CGFloat = 24
    #else
    private let titleFont = Font.title.weight(.heavy)
    private let spacing: CGFloat = 6
    private let cardPadding: CGFloat = 16
    #endif
}

private struct PageDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { dot in
                Capsule()
                    .fill(dot == index ? Color.white : Color.white.opacity(0.3))
                    .frame(width: dot == index ? 18 : 6, height: 6)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.2), value: index)
        .accessibilityHidden(true)
    }
}

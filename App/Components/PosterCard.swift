import LenKit
import SwiftUI

/// 海报 + 片名 + 年份地区。`width` 为 nil 时撑满网格列宽。
struct PosterCard: View {
    let item: MediaSummary
    var width: CGFloat?

    @PlatformMetrics private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            poster
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(item.subtitle.isEmpty ? item.kind.displayName : item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: width)
    }

    private var poster: some View {
        Color.clear
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay { PosterImage(url: item.posterURL, title: item.title, displayWidth: width ?? metrics.gridMinWidth) }
            .overlay(alignment: .topLeading) { BadgeLabel(text: item.badge) }
            .clipShape(.rect(cornerRadius: metrics.cornerRadius))
            #if os(tvOS)
            .hoverEffect(.highlight)
            #endif
    }
}

/// 点击进入详情的海报
struct PosterLink: View {
    let item: MediaSummary
    var width: CGFloat?

    var body: some View {
        NavigationLink(value: DetailRoute(summary: item)) {
            PosterCard(item: item, width: width)
        }
        .posterButtonStyle()
    }
}

struct BadgeLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.5), in: .rect(cornerRadius: 5))
            .padding(6)
    }
}

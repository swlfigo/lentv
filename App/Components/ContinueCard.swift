import LenKit
import SwiftUI

/// “继续观看”卡片：模糊海报做背景，左侧小海报，右侧集数、线路、剩余时间和进度条
struct ContinueCard: View {
    let record: WatchRecord

    @PlatformMetrics private var metrics

    var body: some View {
        let size = metrics.continueCardSize
        let thumbWidth = (size.height - 20) * 2 / 3

        HStack(spacing: 12) {
            PosterImage(url: record.posterURL, title: record.title, displayWidth: thumbWidth, showsTitleWhileLoading: false)
                .frame(width: thumbWidth, height: thumbWidth * 1.5)
                .clipShape(.rect(cornerRadius: metrics.cornerRadius * 0.7))

            VStack(alignment: .leading, spacing: 4) {
                Spacer(minLength: 0)
                Text(record.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(record.progressTitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                Text(TimeText.remaining(record.remaining))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                ProgressView(value: record.progress)
                    .tint(.white)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(width: size.width, height: size.height)
        .background {
            PosterImage(url: record.posterURL, title: record.title, displayWidth: 120, showsTitleWhileLoading: false)
                .blur(radius: 24)
                .overlay(Color.black.opacity(0.45))
        }
        .clipShape(.rect(cornerRadius: metrics.cornerRadius + 4))
        #if os(tvOS)
        .hoverEffect(.highlight)
        #endif
    }
}

struct ContinueLink: View {
    let record: WatchRecord

    var body: some View {
        NavigationLink(value: DetailRoute(summary: record.summary, autoplay: true)) {
            ContinueCard(record: record)
        }
        .posterButtonStyle()
    }
}

import Kingfisher
import SwiftUI

/// 海报：Kingfisher 负责下载、缓存和按显示尺寸缩小，加载完成前显示按片名取色的占位块。
struct PosterImage: View {
    let url: URL?
    let title: String
    /// 显示宽度（点），用来决定缩小后的尺寸
    var displayWidth: CGFloat = 200
    var showsTitleWhileLoading = true

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(PosterPalette.color(for: title))
            .overlay {
                KFImage(url)
                    .placeholder { placeholderTitle }
                    .setProcessor(DownsamplingImageProcessor(size: CGSize(width: displayWidth, height: displayWidth * 1.5)))
                    .scaleFactor(displayScale)
                    .retry(maxCount: 2, interval: .seconds(1))
                    .fade(duration: 0.2)
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
    }

    @ViewBuilder
    private var placeholderTitle: some View {
        if showsTitleWhileLoading {
            Text(title)
                .font(.system(size: max(displayWidth * 0.11, 11), weight: .heavy))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(3)
                .padding(displayWidth * 0.07)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
    }
}

enum ImageCacheSetup {
    /// 资源站的图片通常不带缓存头，所以由 Kingfisher 自己管理磁盘缓存的大小和过期时间
    static func configure() {
        let cache = ImageCache.default
        cache.memoryStorage.config.totalCostLimit = 120 * 1024 * 1024
        cache.diskStorage.config.sizeLimit = 300 * 1024 * 1024
        cache.diskStorage.config.expiration = .days(14)
    }
}

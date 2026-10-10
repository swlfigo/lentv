import LenKit
import SwiftUI

/// 进入详情页。`autoplay` 用于首页“播放”和“继续观看”：进入后直接开始播放。
struct DetailRoute: Hashable {
    let summary: MediaSummary
    var autoplay = false
}

extension View {
    func mediaDestinations() -> some View {
        navigationDestination(for: DetailRoute.self) { route in
            DetailView(route: route)
        }
    }

    /// tvOS 上用系统的海报聚焦效果，其它平台保持平铺
    @ViewBuilder
    func posterButtonStyle() -> some View {
        #if os(tvOS)
        buttonStyle(.borderless)
        #else
        buttonStyle(.plain)
        #endif
    }
}

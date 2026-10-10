import SwiftUI

/// 首页的一行：标题 + 横向滚动的内容
struct Shelf<Content: View>: View {
    let title: String
    var note: String?
    @ViewBuilder var content: Content

    @PlatformMetrics private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title).font(.title3.weight(.bold))
                if let note {
                    Text(note).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, metrics.horizontalPadding)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: metrics.itemSpacing) {
                    content
                }
                .padding(.horizontal, metrics.horizontalPadding)
                #if os(tvOS)
                // 给聚焦放大留出空间
                .padding(.vertical, 24)
                #endif
            }
            .scrollIndicators(.never)
            .scrollClipDisabled()
        }
        #if os(tvOS)
        .focusSection()
        #endif
    }
}

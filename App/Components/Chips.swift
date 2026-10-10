import SwiftUI

/// 分类、线路等单选标签。tvOS 上聚焦时白底放大，选中时红底。
struct ChipButtonStyle: ButtonStyle {
    var isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        ChipBody(configuration: configuration, isSelected: isSelected)
    }
}

private struct ChipBody: View {
    let configuration: ButtonStyleConfiguration
    let isSelected: Bool

    @Environment(\.isFocused) private var isFocused
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(font)
            .lineLimit(1)
            .padding(.horizontal, horizontalPadding)
            .frame(minHeight: height)
            .foregroundStyle(isFocused ? Color.black : .white)
            .background(background, in: .capsule)
            .scaleEffect(isFocused ? 1.08 : (configuration.isPressed ? 0.96 : 1))
            .shadow(color: .black.opacity(isFocused ? 0.5 : 0), radius: 16, y: 10)
            .opacity(isEnabled ? 1 : 0.35)
            .animation(.easeOut(duration: 0.15), value: isFocused)
            .contentShape(.capsule)
    }

    private var background: Color {
        if isFocused { return .white }
        return isSelected ? .lenSelectedFill : .lenSurface
    }

    #if os(tvOS)
    private var font: Font { .callout.weight(.bold) }
    private var height: CGFloat { 60 }
    private var horizontalPadding: CGFloat { 30 }
    #elseif os(macOS)
    private var font: Font { .callout.weight(.semibold) }
    private var height: CGFloat { 30 }
    private var horizontalPadding: CGFloat { 14 }
    #else
    private var font: Font { .subheadline.weight(.bold) }
    private var height: CGFloat { 44 }
    private var horizontalPadding: CGFloat { 18 }
    #endif
}

/// 横向滚动的一排单选标签
struct ChipRow<Item: Hashable>: View {
    let items: [Item]
    let selection: Item?
    let title: (Item) -> String
    var isEnabled: (Item) -> Bool = { _ in true }
    /// 默认使用页面左右边距；放在已有边距的容器里时传 0
    var horizontalPadding: CGFloat?
    /// 分类栏在触屏设备上提示右侧还有选项。
    var showsOverflowHint = false
    let onSelect: (Item) -> Void

    @PlatformMetrics private var metrics
    #if os(iOS)
    @Namespace private var scrollCoordinateSpace
    @State private var contentTrailingEdge: CGFloat = 0
    #endif

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: metrics.itemSpacing * 0.6) {
                ForEach(items, id: \.self) { item in
                    Button { onSelect(item) } label: {
                        HStack(spacing: 6) {
                            if item == selection {
                                Image(systemName: "checkmark").font(.caption.weight(.heavy))
                            }
                            Text(title(item))
                        }
                    }
                    .buttonStyle(ChipButtonStyle(isSelected: item == selection))
                    .disabled(!isEnabled(item))
                }
            }
            .padding(.horizontal, horizontalPadding ?? metrics.horizontalPadding)
            #if os(iOS)
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.frame(in: .named(scrollCoordinateSpace)).maxX
            } action: { edge in
                if showsOverflowHint { contentTrailingEdge = edge }
            }
            #endif
            #if os(tvOS)
            .padding(.vertical, 12)
            #endif
        }
        .scrollIndicators(.never)
        .scrollClipDisabled()
        #if os(iOS)
        .coordinateSpace(name: scrollCoordinateSpace)
        .overlay {
            if showsOverflowHint {
                GeometryReader { geometry in
                    let trailingPadding = horizontalPadding ?? metrics.horizontalPadding
                    if contentTrailingEdge - trailingPadding > geometry.size.width + 1 {
                        HStack(spacing: 0) {
                            Spacer(minLength: 0)
                            LinearGradient(
                                colors: [.lenBackground.opacity(0), .lenBackground, .lenBackground],
                                startPoint: .leading, endPoint: .trailing)
                                .frame(width: 40)
                                .overlay(alignment: .trailing) {
                                    Image(systemName: "arrowtriangle.right.fill")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white.opacity(0.85))
                                        .padding(.trailing, 8)
                                }
                        }
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        #endif
        #if os(tvOS)
        .focusSection()
        #endif
    }
}

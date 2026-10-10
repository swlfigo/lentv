import SwiftUI

extension Color {
    static let lenBackground = Color(red: 0x0B / 255, green: 0x0C / 255, blue: 0x0F / 255)
    static let lenSurface = Color.white.opacity(0.08)
    /// 选中态的填充色，比强调色略深，保证白字对比度
    static let lenSelectedFill = Color(red: 0xC4 / 255, green: 0x36 / 255, blue: 0x3B / 255)
}

/// 各平台的尺寸。iPhone 和 iPad 通过水平尺寸类区分。
struct Metrics {
    let posterWidth: CGFloat
    let gridMinWidth: CGFloat
    let itemSpacing: CGFloat
    let sectionSpacing: CGFloat
    let horizontalPadding: CGFloat
    let cornerRadius: CGFloat
    let heroHeight: CGFloat
    let continueCardSize: CGSize

    static let tv = Metrics(
        posterWidth: 220, gridMinWidth: 220, itemSpacing: 40, sectionSpacing: 56, horizontalPadding: 0,
        cornerRadius: 14, heroHeight: 600, continueCardSize: CGSize(width: 420, height: 236))
    static let phone = Metrics(
        posterWidth: 110, gridMinWidth: 104, itemSpacing: 12, sectionSpacing: 26, horizontalPadding: 16,
        cornerRadius: 10, heroHeight: 210, continueCardSize: CGSize(width: 272, height: 116))
    static let pad = Metrics(
        posterWidth: 140, gridMinWidth: 140, itemSpacing: 18, sectionSpacing: 30, horizontalPadding: 32,
        cornerRadius: 12, heroHeight: 300, continueCardSize: CGSize(width: 300, height: 134))
    static let mac = Metrics(
        posterWidth: 128, gridMinWidth: 128, itemSpacing: 18, sectionSpacing: 28, horizontalPadding: 28,
        cornerRadius: 10, heroHeight: 300, continueCardSize: CGSize(width: 290, height: 126))
}

/// 读取当前平台尺寸的属性包装：`@PlatformMetrics private var metrics`
@propertyWrapper
struct PlatformMetrics: DynamicProperty {
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    var wrappedValue: Metrics {
        #if os(tvOS)
        .tv
        #elseif os(macOS)
        .mac
        #else
        sizeClass == .compact ? .phone : .pad
        #endif
    }
}

/// 没有海报或海报加载中时的占位色，按片名固定取色
enum PosterPalette {
    private static let hexes: [UInt32] = [
        0x24324A, 0x3A3226, 0x33293F, 0x3A2A2A, 0x2B2F40, 0x2A3A2C, 0x3C3029, 0x2A3A3F, 0x3A2639, 0x2D3A33,
    ]

    static func color(for title: String) -> Color {
        let seed = title.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        let hex = hexes[seed % hexes.count]
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        return Color(red: red, green: green, blue: blue)
    }
}

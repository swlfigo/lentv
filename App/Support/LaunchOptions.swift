#if DEBUG
import Foundation
import LenKit

/// 仅用于调试：通过启动参数直接打开某个页面，方便在模拟器里验证。
///
///     -LenTVTab search            打开某个标签（home / movies / series / search）
///     -LenTVSearch 蜘蛛侠          预填搜索词
///     -LenTVDetail movie/40614    打开详情页
///     -LenTVAutoplay YES          打开详情页后直接播放
enum LaunchOptions {
    private static let defaults = UserDefaults.standard

    static var tab: AppSection? {
        defaults.string(forKey: "LenTVTab").flatMap(AppSection.init(rawValue:))
    }

    static var searchText: String? {
        defaults.string(forKey: "LenTVSearch")
    }

    static var detailRoute: DetailRoute? {
        guard let value = defaults.string(forKey: "LenTVDetail") else { return nil }
        let parts = value.split(separator: "/")
        guard parts.count == 2, let kind = MediaKind(rawValue: String(parts[0])), let id = Int(parts[1]) else { return nil }
        return DetailRoute(
            summary: MediaSummary(kind: kind, mediaID: id, title: ""),
            autoplay: defaults.bool(forKey: "LenTVAutoplay"))
    }
}
#endif

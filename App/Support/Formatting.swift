import Foundation
import LenKit

enum TimeText {
    /// 3735 → "1:02:15"，728 → "12:08"
    static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds)
        let (h, m, s) = (total / 3600, total % 3600 / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    /// "剩余 33 分钟" / "剩余 1:05:40"
    static func remaining(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "" }
        return seconds >= 3600 ? "剩余 \(clock(seconds))" : "剩余 \(max(Int(seconds / 60), 1)) 分钟"
    }
}

extension WatchRecord {
    /// "第3集 · 红牛" / "正片 · 豆瓣"
    var progressTitle: String {
        "\(media.kind == .movie ? "正片" : episodeTitle) · \(lineName)"
    }
}

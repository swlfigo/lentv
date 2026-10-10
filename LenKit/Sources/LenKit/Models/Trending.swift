import Foundation

/// 两路列表的剩余条目和分页位置。调用方原样传回；请求失败不消耗游标。
public struct TrendingCursor: Sendable {
    struct Entry: Sendable {
        let item: MediaSummary
        let views: Int
    }

    struct Stream: Sendable {
        var entries: [Entry] = []
        var nextPage = 1
        var hasMore = true

        var isExhausted: Bool { entries.isEmpty && !hasMore }
    }

    var movies = Stream()
    var series = Stream()
    var seen: Set<MediaSummary.ID> = []
}

public struct TrendingPage: Sendable {
    public let items: [MediaSummary]
    /// nil 表示两类内容均已加载完。
    public let nextCursor: TrendingCursor?
}

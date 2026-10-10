import Foundation

/// `GET /home` 中客户端用到的部分。
public struct HomeFeed: Sendable, Hashable {
    public let hotMovies: [MediaSummary]
    public let hotSeries: [MediaSummary]

    public init(hotMovies: [MediaSummary], hotSeries: [MediaSummary]) {
        self.hotMovies = hotMovies
        self.hotSeries = hotSeries
    }

    /// 顶部推荐轮播：剧集和电影交替取前几部，优先有简介的
    public func featured(limit: Int = 3) -> [MediaSummary] {
        let pool = zip(hotSeries, hotMovies).flatMap { [$0, $1] } + hotSeries.dropFirst(hotMovies.count)
        let described = pool.filter { $0.summary != nil }
        return Array((described.isEmpty ? pool : described).prefix(limit))
    }
}

struct HomeFeedPayload: Decodable {
    let feed: HomeFeed

    private enum CodingKeys: String, CodingKey { case movies, tvSeries }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        feed = HomeFeed(
            hotMovies: c.lossyArray(MediaSummaryPayload.self, forKey: .movies).compactMap { $0.summary(defaultKind: .movie) },
            hotSeries: c.lossyArray(MediaSummaryPayload.self, forKey: .tvSeries).compactMap { $0.summary(defaultKind: .tv) })
    }
}

/// 分页列表的一页。
public struct Page<Item: Sendable & Hashable>: Sendable, Hashable {
    public let items: [Item]
    public let page: Int
    public let totalPages: Int
    public let total: Int

    public init(items: [Item], page: Int, totalPages: Int, total: Int) {
        self.items = items
        self.page = page
        self.totalPages = totalPages
        self.total = total
    }

    public var hasMore: Bool { page < totalPages }
}

struct PagePayload: Decodable {
    let items: [MediaSummaryPayload]
    let page: Int
    let totalPages: Int
    let total: Int

    private enum CodingKeys: String, CodingKey { case items, page, totalPages, total }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = c.lossyArray(MediaSummaryPayload.self, forKey: .items)
        page = c.lossyInt(.page) ?? 1
        totalPages = c.lossyInt(.totalPages) ?? 1
        total = c.lossyInt(.total) ?? items.count
    }
}

/// 电影 / 剧集分类，筛选时传 `slug`。
public struct MediaCategory: Sendable, Hashable, Identifiable, Decodable {
    public let name: String
    public let slug: String

    public var id: String { slug }

    public init(name: String, slug: String) {
        self.name = name
        self.slug = slug
    }
}

public struct YearOption: Sendable, Hashable, Identifiable, Decodable {
    /// 接口取值，例如 `"2026"`、`"earlier-2015"`
    public let value: String

    public var id: String { value }

    public var label: String {
        value.hasPrefix("earlier-") ? "\(value.dropFirst("earlier-".count)) 以前" : value
    }

    public init(value: String) {
        self.value = value
    }

    private enum CodingKeys: String, CodingKey { case year }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let value = c.lossyString(.year) else {
            throw DecodingError.dataCorruptedError(forKey: .year, in: c, debugDescription: "Missing year")
        }
        self.value = value
    }
}

struct RegionPayload: Decodable {
    let name: String
}

public enum ListSort: String, Sendable, Hashable, CaseIterable, Identifiable {
    case latest
    case views
    case rating

    public var id: String { rawValue }

    public func displayName(for kind: MediaKind) -> String {
        switch self {
        case .latest: kind == .tv ? "最近更新" : "最新"
        case .views: "最热"
        case .rating: "评分"
        }
    }
}

public enum SeriesStatus: String, Sendable, Hashable, CaseIterable, Identifiable {
    case ongoing
    case finished

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ongoing: "连载中"
        case .finished: "已完结"
        }
    }
}

/// 分类列表的筛选条件。
public struct ListQuery: Sendable, Hashable {
    public var kind: MediaKind
    public var categorySlug: String?
    public var region: String?
    public var year: String?
    public var status: SeriesStatus?
    public var sort: ListSort
    public var page: Int
    public var pageSize: Int

    public init(
        kind: MediaKind, categorySlug: String? = nil, region: String? = nil, year: String? = nil,
        status: SeriesStatus? = nil, sort: ListSort = .latest, page: Int = 1, pageSize: Int = 30
    ) {
        self.kind = kind
        self.categorySlug = categorySlug
        self.region = region
        self.year = year
        self.status = status
        self.sort = sort
        self.page = page
        self.pageSize = pageSize
    }

    var queryItems: [URLQueryItem] {
        var items = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "pageSize", value: String(pageSize)),
            URLQueryItem(name: "sort", value: sort.rawValue),
        ]
        if let categorySlug { items.append(URLQueryItem(name: "type", value: categorySlug)) }
        if let region { items.append(URLQueryItem(name: "region", value: region)) }
        if let year { items.append(URLQueryItem(name: "year", value: year)) }
        if kind == .tv, let status {
            items.append(URLQueryItem(name: "isFinished", value: status == .finished ? "true" : "false"))
        }
        return items
    }
}

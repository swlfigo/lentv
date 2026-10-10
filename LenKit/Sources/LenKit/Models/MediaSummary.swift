import Foundation

public enum MediaKind: String, Sendable, Hashable, Codable, CaseIterable {
    case movie
    case tv

    /// 列表接口的 `resultType` / 详情接口的 `media_type`
    init?(apiValue: String?) {
        switch apiValue?.lowercased() {
        case "movie": self = .movie
        case "tv", "tv_series", "tv-series": self = .tv
        default: return nil
        }
    }

    public var displayName: String {
        switch self {
        case .movie: "电影"
        case .tv: "剧集"
        }
    }
}

public enum SearchScope: String, Sendable, CaseIterable {
    case all
    case movie
    case tv
}

/// 搜索结果、首页和分类列表里的一项。
public struct MediaSummary: Sendable, Hashable, Identifiable {
    public struct ID: Sendable, Hashable, Codable {
        public let kind: MediaKind
        public let value: Int

        public init(kind: MediaKind, value: Int) {
            self.kind = kind
            self.value = value
        }
    }

    public let kind: MediaKind
    public let mediaID: Int
    public let title: String
    public let posterURL: URL?
    public let year: Int?
    public let region: String?
    /// 评分为 0 时视为没有评分
    public let rating: String?
    public let director: String?
    public let actors: String?
    public let summary: String?
    public let category: String?
    public let totalEpisodes: Int?
    public let currentEpisode: Int?

    public var id: ID { ID(kind: kind, value: mediaID) }

    public init(
        kind: MediaKind, mediaID: Int, title: String, posterURL: URL? = nil, year: Int? = nil,
        region: String? = nil, rating: String? = nil, director: String? = nil, actors: String? = nil,
        summary: String? = nil, category: String? = nil, totalEpisodes: Int? = nil, currentEpisode: Int? = nil
    ) {
        self.kind = kind
        self.mediaID = mediaID
        self.title = title
        self.posterURL = posterURL
        self.year = year
        self.region = region
        self.rating = rating
        self.director = director
        self.actors = actors
        self.summary = summary
        self.category = category
        self.totalEpisodes = totalEpisodes
        self.currentEpisode = currentEpisode
    }

    /// 海报角标：“电影” / “65 集”
    public var badge: String {
        guard kind == .tv else { return kind.displayName }
        if let count = totalEpisodes ?? currentEpisode, count > 0 { return "\(count) 集" }
        return kind.displayName
    }

    /// “2026 · 美国”
    public var subtitle: String {
        [year.map(String.init), region].compactMap(\.self).joined(separator: " · ")
    }
}

/// 各接口里条目字段的并集，解码后再按场景补上类型。
struct MediaSummaryPayload: Decodable {
    let id: Int?
    let kind: MediaKind?
    let title: String?
    let posterURL: URL?
    let year: Int?
    let region: String?
    let rating: String?
    let director: String?
    let actors: String?
    let summary: String?
    let category: String?
    let totalEpisodes: Int?
    let currentEpisode: Int?
    let viewCount: Int

    private enum CodingKeys: String, CodingKey {
        case id, title, poster, year, region, rating, director, actors, description
        case resultType, mediaType = "media_type"
        case releaseDate = "release_date", firstAirDate = "first_air_date"
        case categoryName = "category_name", type
        case totalEpisodes = "total_episodes", currentEpisode = "current_episode", currentEpisodes = "current_episodes"
        case viewCount = "view_count"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lossyInt(.id)
        kind = MediaKind(apiValue: c.lossyString(.resultType) ?? c.lossyString(.mediaType))
        title = c.lossyString(.title)
        posterURL = c.lossyURL(.poster)
        year = c.lossyYear(.year, .releaseDate, .firstAirDate)
        region = c.lossyString(.region)
        rating = c.lossyString(.rating).flatMap { Double($0) ?? 0 > 0 ? $0 : nil }
        director = c.lossyString(.director)
        actors = c.lossyString(.actors)
        summary = c.lossyString(.description)
        category = c.lossyString(.categoryName) ?? c.lossyString(.type)
        totalEpisodes = c.lossyInt(.totalEpisodes)
        currentEpisode = c.lossyInt(.currentEpisode) ?? c.lossyInt(.currentEpisodes)
        viewCount = c.lossyInt(.viewCount) ?? 0
    }

    func summary(defaultKind: MediaKind?) -> MediaSummary? {
        guard let id, let kind = kind ?? defaultKind else { return nil }
        return MediaSummary(
            kind: kind, mediaID: id, title: title ?? "未命名", posterURL: posterURL, year: year,
            region: region, rating: rating, director: director, actors: actors, summary: summary,
            category: category, totalEpisodes: totalEpisodes, currentEpisode: currentEpisode)
    }
}

/// `GET /search` 的响应（没有 success/data 外壳）。
struct SearchResponse: Decodable {
    let results: [MediaSummary]

    private enum CodingKeys: String, CodingKey { case results }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        results = c.lossyArray(MediaSummaryPayload.self, forKey: .results).compactMap { $0.summary(defaultKind: nil) }
    }
}

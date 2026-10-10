import Foundation

/// 一集（电影只有一集“正片”）。
public struct Episode: Sendable, Hashable, Decodable {
    public let number: Int
    public let title: String
    public let videoURL: URL?
    public let isAvailable: Bool

    public init(number: Int, title: String, videoURL: URL?, isAvailable: Bool = true) {
        self.number = number
        self.title = title
        self.videoURL = videoURL
        self.isAvailable = isAvailable
    }

    public var isPlayable: Bool { isAvailable && videoURL != nil }

    private enum CodingKeys: String, CodingKey { case number, title, videoUrl, isAvailable }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let number = c.lossyInt(.number) else {
            throw DecodingError.dataCorruptedError(forKey: .number, in: c, debugDescription: "Missing number")
        }
        self.number = number
        self.title = c.lossyString(.title) ?? "第\(number)集"
        self.videoURL = c.lossyURL(.videoUrl)
        self.isAvailable = c.lossyBool(.isAvailable) ?? true
    }
}

/// 一条播放线路，例如“豆瓣”“红牛”。
public struct SourceLine: Sendable, Hashable, Identifiable, Decodable {
    /// 例如 `"0:141487"`，调用 play-url 接口时作为 `source` 参数
    public let key: String
    public let name: String
    /// 按集数升序
    public let episodes: [Episode]

    public var id: String { key }

    public init(key: String, name: String, episodes: [Episode]) {
        self.key = key
        self.name = name
        self.episodes = episodes.sorted { $0.number < $1.number }
    }

    public func episode(number: Int) -> Episode? {
        episodes.first { $0.number == number }
    }

    private enum CodingKeys: String, CodingKey { case key, name, episodes }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let key = c.lossyString(.key) else {
            throw DecodingError.dataCorruptedError(forKey: .key, in: c, debugDescription: "Missing key")
        }
        self.init(
            key: key,
            name: c.lossyString(.name) ?? key,
            episodes: c.lossyArray(Episode.self, forKey: .episodes))
    }
}

public struct MediaDetail: Sendable, Hashable, Decodable {
    public let kind: MediaKind
    public let id: Int
    public let title: String
    public let posterURL: URL?
    public let backdropURL: URL?
    public let year: Int?
    public let region: String?
    public let language: String?
    public let director: String?
    public let actors: String?
    public let summary: String?
    public let rating: String?
    public let category: String?
    public let updateInfo: String?
    public let totalEpisodes: Int?
    public let isFinished: Bool
    /// 只保留至少有一集的线路
    public let lines: [SourceLine]

    public init(
        kind: MediaKind, id: Int, title: String, posterURL: URL? = nil, backdropURL: URL? = nil,
        year: Int? = nil, region: String? = nil, language: String? = nil, director: String? = nil,
        actors: String? = nil, summary: String? = nil, rating: String? = nil, category: String? = nil,
        updateInfo: String? = nil, totalEpisodes: Int? = nil, isFinished: Bool = true, lines: [SourceLine]
    ) {
        self.kind = kind
        self.id = id
        self.title = title
        self.posterURL = posterURL
        self.backdropURL = backdropURL
        self.year = year
        self.region = region
        self.language = language
        self.director = director
        self.actors = actors
        self.summary = summary
        self.rating = rating
        self.category = category
        self.updateInfo = updateInfo
        self.totalEpisodes = totalEpisodes
        self.isFinished = isFinished
        self.lines = lines.filter { !$0.episodes.isEmpty }
    }

    private enum CodingKeys: String, CodingKey {
        case mediaType = "media_type", id, title, poster, backdrop, year, region, language, director
        case actors, description, rating, category, updateInfo = "update_info"
        case totalEpisodes = "total_episodes", isFinished = "is_finished", sourceOptions = "source_options"
    }

    private struct CategoryRef: Decodable { let name: String? }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.lossyInt(.id) else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "Missing id")
        }
        self.init(
            // media_type 缺失时由 LenAPIClient 按请求的类型修正
            kind: MediaKind(apiValue: c.lossyString(.mediaType)) ?? .movie,
            id: id,
            title: c.lossyString(.title) ?? "未命名",
            posterURL: c.lossyURL(.poster),
            backdropURL: c.lossyURL(.backdrop),
            year: c.lossyYear(.year),
            region: c.lossyString(.region),
            language: c.lossyString(.language),
            director: c.lossyString(.director),
            actors: c.lossyString(.actors),
            summary: c.lossyString(.description),
            rating: c.lossyString(.rating).flatMap { Double($0) ?? 0 > 0 ? $0 : nil },
            category: ((try? c.decodeIfPresent(CategoryRef.self, forKey: .category)) ?? nil)?.name,
            updateInfo: c.lossyString(.updateInfo),
            totalEpisodes: c.lossyInt(.totalEpisodes),
            isFinished: c.lossyBool(.isFinished) ?? true,
            lines: c.lossyArray(SourceLine.self, forKey: .sourceOptions))
    }

    func with(kind: MediaKind) -> MediaDetail {
        guard kind != self.kind else { return self }
        return MediaDetail(
            kind: kind, id: id, title: title, posterURL: posterURL, backdropURL: backdropURL, year: year,
            region: region, language: language, director: director, actors: actors, summary: summary,
            rating: rating, category: category, updateInfo: updateInfo, totalEpisodes: totalEpisodes,
            isFinished: isFinished, lines: lines)
    }

    public var mediaID: MediaSummary.ID { MediaSummary.ID(kind: kind, value: id) }

    public var asSummary: MediaSummary {
        MediaSummary(
            kind: kind, mediaID: id, title: title, posterURL: posterURL, year: year, region: region,
            rating: rating, director: director, actors: actors, summary: summary, category: category,
            totalEpisodes: totalEpisodes)
    }

    /// “2026 · 美国 · 动作 · 英语”
    public var metadataLine: [String] {
        [year.map(String.init), region, category, language].compactMap(\.self)
    }
}

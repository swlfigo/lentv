import Foundation

/// len.tv 接口客户端（接口说明见 docs/API.md）。
///
/// 用 actor 隔离缓存状态：详情接口有短期缓存，并且同一个详情同时被多处请求时只发一次网络请求。
public actor LenAPIClient {
    public static let defaultBaseURL = URL(string: "https://apiii.solada.site/api/")!

    private struct CachedDetail {
        let detail: MediaDetail
        let fetchedAt: ContinuousClock.Instant
    }

    private let baseURL: URL
    private let transport: any HTTPTransport
    private let decoder = JSONDecoder()
    private let clock = ContinuousClock()
    private let detailTTL: Duration

    private var detailCache: [MediaSummary.ID: CachedDetail] = [:]
    private var detailTasks: [MediaSummary.ID: Task<MediaDetail, any Error>] = [:]
    private var categoryCache: [MediaKind: [MediaCategory]] = [:]
    private var regionCache: [String]?
    private var yearCache: [YearOption]?

    public init(
        baseURL: URL = LenAPIClient.defaultBaseURL,
        transport: any HTTPTransport = URLSessionTransport(),
        detailTTL: Duration = .seconds(300)
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.detailTTL = detailTTL
    }

    // MARK: - 首页与列表

    public func home(forceRefresh: Bool = false) async throws(LenAPIError) -> HomeFeed {
        try await get("home", as: HomeFeedPayload.self,
                      cachePolicy: forceRefresh ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy).feed
    }

    public func list(_ query: ListQuery) async throws(LenAPIError) -> Page<MediaSummary> {
        let path = query.kind == .movie ? "movies" : "tv-series"
        let payload = try await getEnveloped(path, query: query.queryItems, as: PagePayload.self)
        return Page(
            items: payload.items.compactMap { $0.summary(defaultKind: query.kind) },
            page: payload.page, totalPages: payload.totalPages, total: payload.total)
    }

    /// 按播放量归并电影、剧集，每次最多返回 24 项。两路独立翻页，避免漏掉某一路的高热度条目。
    public func trending(after cursor: TrendingCursor? = nil) async throws(LenAPIError) -> TrendingPage {
        var cursor = cursor ?? TrendingCursor()
        var items: [MediaSummary] = []
        while items.count < 24 {
            if Task.isCancelled { throw .cancelled }
            // 必须知道两路下一个条目后才能比较；一条流可能连续贡献多页。
            let movieStream = cursor.movies
            let seriesStream = cursor.series
            async let movies = fillTrendingStream(movieStream, kind: .movie)
            async let series = fillTrendingStream(seriesStream, kind: .tv)
            do {
                (cursor.movies, cursor.series) = try await (movies, series)
            } catch {
                throw (error as? LenAPIError) ?? .transport(error.localizedDescription)
            }

            let entry: TrendingCursor.Entry
            switch (cursor.movies.entries.first, cursor.series.entries.first) {
            case (nil, nil):
                return TrendingPage(items: items, nextCursor: nil)
            case (let movie?, let series?) where movie.views >= series.views:
                entry = cursor.movies.entries.removeFirst()
            case (nil, _?):
                entry = cursor.series.entries.removeFirst()
            case (_?, nil):
                entry = cursor.movies.entries.removeFirst()
            default:
                entry = cursor.series.entries.removeFirst()
            }
            if cursor.seen.insert(entry.item.id).inserted { items.append(entry.item) }
        }
        let exhausted = cursor.movies.isExhausted && cursor.series.isExhausted
        return TrendingPage(items: items, nextCursor: exhausted ? nil : cursor)
    }

    private func fillTrendingStream(
        _ stream: TrendingCursor.Stream, kind: MediaKind
    ) async throws(LenAPIError) -> TrendingCursor.Stream {
        var stream = stream
        while stream.entries.isEmpty && stream.hasMore {
            if Task.isCancelled { throw .cancelled }
            let query = ListQuery(kind: kind, sort: .views, page: stream.nextPage, pageSize: 24)
            let envelope = try await get(
                kind == .movie ? "movies" : "tv-series", query: query.queryItems,
                as: Envelope<PagePayload>.self, cachePolicy: .reloadIgnoringLocalCacheData)
            guard envelope.success, let page = envelope.data else { throw .server(message: envelope.message) }
            stream.entries = page.items.compactMap { payload in
                payload.summary(defaultKind: kind).map { TrendingCursor.Entry(item: $0, views: payload.viewCount) }
            }
            stream.hasMore = stream.nextPage < page.totalPages
            stream.nextPage += 1
        }
        return stream
    }

    public func categories(_ kind: MediaKind) async throws(LenAPIError) -> [MediaCategory] {
        if let cached = categoryCache[kind] { return cached }
        let type = kind == .movie ? "movie" : "tv"
        let categories = try await getEnveloped(
            "categories", query: [URLQueryItem(name: "type", value: type)], as: [Lossy<MediaCategory>].self
        ).compactMap(\.value)
        categoryCache[kind] = categories
        return categories
    }

    public func regions() async throws(LenAPIError) -> [String] {
        if let regionCache { return regionCache }
        let regions = try await getEnveloped("regions", as: [Lossy<RegionPayload>].self).compactMap(\.value?.name)
        regionCache = regions
        return regions
    }

    public func years() async throws(LenAPIError) -> [YearOption] {
        if let yearCache { return yearCache }
        let years = try await getEnveloped("years", as: [Lossy<YearOption>].self).compactMap(\.value)
        yearCache = years
        return years
    }

    // MARK: - 搜索

    public func search(_ query: String, scope: SearchScope = .all) async throws(LenAPIError) -> [MediaSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return try await get(
            "search",
            query: [
                URLQueryItem(name: "q", value: trimmed),
                URLQueryItem(name: "type", value: scope.rawValue),
                URLQueryItem(name: "page", value: "1"),
                URLQueryItem(name: "pageSize", value: "60"),
            ],
            as: SearchResponse.self
        ).results
    }

    // MARK: - 详情与播放地址

    public func detail(_ kind: MediaKind, id: Int) async throws(LenAPIError) -> MediaDetail {
        let key = MediaSummary.ID(kind: kind, value: id)
        if let cached = detailCache[key], cached.fetchedAt.duration(to: clock.now) < detailTTL {
            return cached.detail
        }

        let task: Task<MediaDetail, any Error>
        if let inFlight = detailTasks[key] {
            task = inFlight
        } else {
            task = Task { try await self.fetchDetail(kind, id: id) }
            detailTasks[key] = task
        }

        do {
            let detail = try await task.value
            detailTasks[key] = nil
            detailCache[key] = CachedDetail(detail: detail, fetchedAt: clock.now)
            return detail
        } catch {
            detailTasks[key] = nil
            throw (error as? LenAPIError) ?? .transport(error.localizedDescription)
        }
    }

    /// 详情里的地址为空或失效时，向服务端重新获取某条线路某一集的地址。
    public func playURL(_ kind: MediaKind, id: Int, episode: Int, lineKey: String) async throws(LenAPIError) -> URL {
        let path = kind == .movie ? "movies/\(id)/play-url" : "tv-series/\(id)/episodes/\(episode)/play-url"
        let payload = try await getEnveloped(
            path, query: [URLQueryItem(name: "source", value: lineKey)], as: PlayURLPayload.self)
        guard let url = payload.url else { throw .noPlayableSource }
        return url
    }

    public func invalidateDetail(_ kind: MediaKind, id: Int) {
        detailCache[MediaSummary.ID(kind: kind, value: id)] = nil
    }

    private func fetchDetail(_ kind: MediaKind, id: Int) async throws(LenAPIError) -> MediaDetail {
        let path = kind == .movie ? "movies/\(id)" : "tv-series/\(id)"
        return try await getEnveloped(path, as: MediaDetail.self).with(kind: kind)
    }

    // MARK: - 请求

    private func getEnveloped<Payload: Decodable>(
        _ path: String, query: [URLQueryItem] = [], as type: Payload.Type
    ) async throws(LenAPIError) -> Payload {
        let envelope = try await get(path, query: query, as: Envelope<Payload>.self)
        guard envelope.success, let data = envelope.data else {
            throw .server(message: envelope.message)
        }
        return data
    }

    private func get<Response: Decodable>(
        _ path: String, query: [URLQueryItem] = [], as type: Response.Type,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
    ) async throws(LenAPIError) -> Response {
        var url = baseURL.appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }
        var request = URLRequest(url: url, cachePolicy: cachePolicy, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw .cancelled
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw .transport(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw .http(status: http.statusCode)
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw .decoding(String(describing: error))
        }
    }
}

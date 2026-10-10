import Foundation
import Testing
@testable import LenKit

@Suite("接口数据解码")
struct DecodingTests {
    let decoder = JSONDecoder()

    @Test func searchResults() throws {
        let results = try decoder.decode(SearchResponse.self, from: Fixture.data("search")).results
        #expect(results.count == 31)

        let first = try #require(results.first)
        #expect(first.kind == .movie)
        #expect(first.mediaID == 24236)
        #expect(first.title == "蜘蛛侠")
        #expect(first.year == 2002)
        #expect(first.rating == nil, "评分 0.0 视为没有评分")
        #expect(first.badge == "电影")

        let series = try #require(results.first { $0.mediaID == 4243 })
        #expect(series.kind == .tv)
        #expect(series.badge == "65 集")
        #expect(series.subtitle == "1994 · 美国")
    }

    @Test func movieDetailHasAllLines() throws {
        let detail = try #require(try decoder.decode(Envelope<MediaDetail>.self, from: Fixture.data("movie")).data)
        #expect(detail.kind == .movie)
        #expect(detail.title == "蜘蛛侠：崭新之日")
        #expect(detail.rating == "10.0")
        #expect(detail.category == "动作")
        #expect(detail.lines.map(\.name) == ["豆瓣", "速博", "红牛"])
        #expect(detail.lines.map(\.key) == ["0:141487", "1:117072", "2:152730"])
        #expect(detail.lines[2].episodes.first?.videoURL?.absoluteString == "https://hn.bfvvs.com/play/axklJyqe/index.m3u8")
        #expect(detail.metadataLine == ["2026", "美国", "动作", "英语"])
    }

    @Test func seriesDetailHasSortedEpisodes() throws {
        let detail = try #require(try decoder.decode(Envelope<MediaDetail>.self, from: Fixture.data("tv")).data)
        #expect(detail.kind == .tv)
        #expect(detail.updateInfo == "更新至第65集")
        #expect(detail.isFinished == false)
        #expect(detail.lines.count == 1)
        #expect(detail.lines[0].episodes.map(\.number) == Array(1...65))
    }

    @Test func playURL() throws {
        let movie = try #require(try decoder.decode(Envelope<PlayURLPayload>.self, from: Fixture.data("movie_play")).data)
        #expect(movie.url?.absoluteString == "https://vodcnd17.ajupf.com/20261006/OaWhoNqF/index.m3u8")
        let episode = try #require(try decoder.decode(Envelope<PlayURLPayload>.self, from: Fixture.data("tv_play")).data)
        #expect(episode.url?.absoluteString == "https://hn.bfvvs.com/play/QdJ3qWDe/index.m3u8")
    }

    @Test func homeFeed() throws {
        let feed = try decoder.decode(HomeFeedPayload.self, from: Fixture.data("home")).feed
        #expect(feed.hotMovies.count == 2)
        #expect(feed.hotSeries.count == 2)
        #expect(feed.hotMovies.allSatisfy { $0.kind == .movie })
        #expect(feed.hotSeries.allSatisfy { $0.kind == .tv })
        #expect(feed.hotSeries[0].title == "亲爱的警督")
        #expect(feed.hotSeries[0].currentEpisode == 4)
        #expect(feed.featured(limit: 3).count == 3)
    }

    @Test func listPage() throws {
        let page = try #require(try decoder.decode(Envelope<PagePayload>.self, from: Fixture.data("movies_page")).data)
        #expect(page.items.count == 3)
        #expect(page.total == 42049)
        #expect(page.totalPages == 14017)
        let first = try #require(page.items.first?.summary(defaultKind: .movie))
        #expect(first.title == "侠盗之簪花乱")
        #expect(first.year == 2023)
    }

    @Test func toleratesMessyFields() throws {
        let json = """
        {"results": [
          {"id": "7", "title": "\u{200B}字符串编号 ", "resultType": "movie", "year": "2026-07-30", "rating": 0},
          {"id": 8, "title": "未知类型", "resultType": "short_video"},
          {"title": "缺少编号", "resultType": "tv"}
        ]}
        """
        let results = try decoder.decode(SearchResponse.self, from: Data(json.utf8)).results
        #expect(results.count == 1)
        #expect(results[0].mediaID == 7)
        #expect(results[0].title == "字符串编号")
        #expect(results[0].year == 2026)
        #expect(results[0].rating == nil)
    }
}

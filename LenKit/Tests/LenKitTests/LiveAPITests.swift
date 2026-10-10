import Foundation
import Testing
@testable import LenKit

/// 访问线上接口，默认跳过。运行：`LEN_LIVE=1 swift test --filter LiveAPITests`
@Suite("线上接口", .enabled(if: ProcessInfo.processInfo.environment["LEN_LIVE"] == "1"), .serialized)
struct LiveAPITests {
    let client = LenAPIClient()

    @Test func trending() async throws {
        let first = try await client.trending()
        let second = try await client.trending(after: #require(first.nextCursor))
        #expect(first.items.count == 24)
        #expect(second.items.count == 24)
        #expect(Set((first.items + second.items).map(\.id)).count == 48)
        #expect(Set(first.items.map(\.kind)) == [.movie, .tv])
        let item = try #require(first.items.first)
        let detail = try await client.detail(item.kind, id: item.mediaID)
        #expect(detail.id == item.mediaID)
        #expect(detail.kind == item.kind)
    }

    @Test func home() async throws {
        let feed = try await client.home()
        #expect(!feed.hotMovies.isEmpty)
        #expect(!feed.hotSeries.isEmpty)
    }

    @Test func searchThenDetailThenPlayURL() async throws {
        let results = try await client.search("蜘蛛侠")
        let movie = try #require(results.first { $0.mediaID == 40614 })
        let detail = try await client.detail(movie.kind, id: movie.mediaID)
        let line = try #require(detail.lines.first)
        #expect(line.episodes.first?.isPlayable == true)
        let url = try await client.playURL(.movie, id: detail.id, episode: 1, lineKey: line.key)
        #expect(url.pathExtension == "m3u8")
    }

    @Test func filters() async throws {
        #expect(try await client.categories(.tv).map(\.slug).contains("chinese-drama"))
        #expect(try await client.categories(.movie).map(\.slug).contains("action"))
        #expect(try await client.regions().contains("美国"))
        #expect(try await client.years().first?.value == "2026")
    }

    @Test func list() async throws {
        let page = try await client.list(ListQuery(kind: .tv, categorySlug: "chinese-drama", sort: .views))
        #expect(page.items.count == 30)
        #expect(page.hasMore)
    }
}

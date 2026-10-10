import Foundation
import Testing
@testable import LenKit

@Suite("LenAPIClient")
struct LenAPIClientTests {
    @Test func homeRefreshBypassesLocalCache() async throws {
        let transport = try StubTransport(fixture: "home")
        let client = LenAPIClient(transport: transport)

        _ = try await client.home()
        _ = try await client.home(forceRefresh: true)

        #expect(transport.requests.count == 2)
        #expect(transport.requests[0].cachePolicy == .useProtocolCachePolicy)
        #expect(transport.requests[1].cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(transport.requests[1].url?.path() == "/api/home")
    }

    @Test func searchRequest() async throws {
        let transport = try StubTransport(fixture: "search")
        let client = LenAPIClient(transport: transport)

        let results = try await client.search("  蜘蛛侠 ")

        #expect(results.count == 31)
        let request = try #require(transport.requests.first)
        #expect(request.url?.path() == "/api/search")
        #expect(request.queryValue("q") == "蜘蛛侠")
        #expect(request.queryValue("type") == "all")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test func emptySearchSkipsNetwork() async throws {
        let transport = try StubTransport(fixture: "search")
        let results = try await LenAPIClient(transport: transport).search("   ")
        #expect(results.isEmpty)
        #expect(transport.requests.isEmpty)
    }

    @Test func detailIsDeduplicatedAndCached() async throws {
        let body = try Fixture.data("movie")
        let transport = StubTransport(delay: .milliseconds(50)) { _ in (200, body) }
        let client = LenAPIClient(transport: transport)

        async let first = client.detail(.movie, id: 40614)
        async let second = client.detail(.movie, id: 40614)
        let (a, b) = try await (first, second)
        let third = try await client.detail(.movie, id: 40614)

        #expect(a == b)
        #expect(b == third)
        #expect(transport.requests.count == 1)
        #expect(transport.requests[0].url?.path() == "/api/movies/40614")
    }

    @Test func detailKindFollowsRequest() async throws {
        let json = #"{"success": true, "data": {"id": 9, "title": "无类型", "source_options": []}}"#
        let transport = StubTransport { _ in (200, Data(json.utf8)) }
        let detail = try await LenAPIClient(transport: transport).detail(.tv, id: 9)
        #expect(detail.kind == .tv)
        #expect(transport.requests[0].url?.path() == "/api/tv-series/9")
    }

    @Test func listQuery() async throws {
        let transport = try StubTransport(fixture: "movies_page")
        let client = LenAPIClient(transport: transport)
        let query = ListQuery(kind: .tv, categorySlug: "chinese-drama", year: "2026", status: .finished, sort: .views, page: 2)

        let page = try await client.list(query)

        #expect(page.items.allSatisfy { $0.kind == .tv })
        let request = try #require(transport.requests.first)
        #expect(request.url?.path() == "/api/tv-series")
        #expect(request.queryValue("type") == "chinese-drama")
        #expect(request.queryValue("year") == "2026")
        #expect(request.queryValue("isFinished") == "true")
        #expect(request.queryValue("sort") == "views")
        #expect(request.queryValue("page") == "2")
        #expect(request.queryValue("region") == nil)
    }

    @Test func envelopeWithoutSuccessFlag() async throws {
        let json = #"{"data": [{"id": 9, "name": "国产剧", "slug": "chinese-drama"}, {"name": "缺少 slug"}]}"#
        let transport = StubTransport { _ in (200, Data(json.utf8)) }
        let client = LenAPIClient(transport: transport)

        #expect(try await client.categories(.tv) == [MediaCategory(name: "国产剧", slug: "chinese-drama")])
        _ = try await client.categories(.tv)
        #expect(transport.requests.count == 1, "分类结果应该被缓存")
        #expect(transport.requests[0].queryValue("type") == "tv")
    }

    @Test func playURLRequest() async throws {
        let transport = try StubTransport(fixture: "tv_play")
        let url = try await LenAPIClient(transport: transport).playURL(.tv, id: 4243, episode: 3, lineKey: "0:146420")
        #expect(url.absoluteString == "https://hn.bfvvs.com/play/QdJ3qWDe/index.m3u8")
        let request = try #require(transport.requests.first)
        #expect(request.url?.path() == "/api/tv-series/4243/episodes/3/play-url")
        #expect(request.queryValue("source") == "0:146420")
    }

    @Test func httpErrorIsTyped() async throws {
        let transport = StubTransport { _ in (500, Data()) }
        await #expect(throws: LenAPIError.http(status: 500)) {
            try await LenAPIClient(transport: transport).home()
        }
    }

    @Test func serverFailureCarriesMessage() async throws {
        let json = #"{"success": false, "message": "影片不存在"}"#
        let transport = StubTransport { _ in (200, Data(json.utf8)) }
        await #expect(throws: LenAPIError.server(message: "影片不存在")) {
            try await LenAPIClient(transport: transport).detail(.movie, id: 1)
        }
    }

    @Test func transportErrorIsWrapped() async throws {
        let transport = StubTransport { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await LenAPIClient(transport: transport).search("a")
            Issue.record("应该抛出错误")
        } catch {
            guard case .transport = error else {
                Issue.record("错误类型不对：\(error)")
                return
            }
        }
    }
}

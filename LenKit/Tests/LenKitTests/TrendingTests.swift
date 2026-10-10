import Foundation
import Testing
@testable import LenKit

@Suite("热播分页")
struct TrendingTests {
    private struct Item: Sendable {
        let id: Int
        let views: Int
    }

    private static func response(_ request: URLRequest, movies: [Item], series: [Item]) throws -> Data {
        let items = request.url?.lastPathComponent == "movies" ? movies : series
        let page = Int(request.queryValue("page") ?? "1")!
        let size = Int(request.queryValue("pageSize") ?? "24")!
        let slice = items.dropFirst((page - 1) * size).prefix(size)
        return try JSONSerialization.data(withJSONObject: [
            "success": true,
            "data": [
                "items": slice.map { ["id": $0.id, "title": "影片\($0.id)", "view_count": String($0.views)] },
                "page": page, "totalPages": (items.count + size - 1) / size, "total": items.count,
            ],
        ])
    }

    @Test func mergesAcrossUnevenSourcePagesAndKeepsTypedIDs() async throws {
        let movies = (1...50).map { Item(id: $0, views: 1000 - $0) }
        let series = (1...5).map { Item(id: $0, views: 100 - $0) }
        let transport = StubTransport { request in
            (200, try Self.response(request, movies: movies, series: series))
        }
        let client = LenAPIClient(transport: transport)
        let first = try await client.trending()
        let second = try await client.trending(after: #require(first.nextCursor))
        let third = try await client.trending(after: #require(second.nextCursor))
        let all = first.items + second.items + third.items

        #expect(first.items.count == 24)
        #expect(second.items.count == 24)
        #expect(third.items.count == 7)
        #expect(third.nextCursor == nil)
        #expect(all.map(\.id) == movies.map { MediaSummary.ID(kind: .movie, value: $0.id) }
            + series.map { MediaSummary.ID(kind: .tv, value: $0.id) })
        #expect(transport.requests.filter { $0.url?.lastPathComponent == "tv-series" }.count == 1)
        #expect(transport.requests.allSatisfy { $0.queryValue("sort") == "views" })
        #expect(transport.requests.allSatisfy { $0.cachePolicy == .reloadIgnoringLocalCacheData })
    }

    @Test func failedContinuationCanRetryWithoutLosingBufferedItems() async throws {
        let movies = (1...50).map { Item(id: $0, views: 100 - $0) }
        let series = (1...4).map { Item(id: $0, views: 1000 - $0) }
        let failing = StubTransport { request in
            if request.queryValue("page") == "2" { return (503, Data()) }
            return (200, try Self.response(request, movies: movies, series: series))
        }
        let client = LenAPIClient(transport: failing)
        let first = try await client.trending()
        let cursor = try #require(first.nextCursor)
        await #expect(throws: LenAPIError.http(status: 503)) {
            try await client.trending(after: cursor)
        }
        let recovered = LenAPIClient(transport: StubTransport { request in
            (200, try Self.response(request, movies: movies, series: series))
        })
        let retry = try await recovered.trending(after: cursor)
        #expect(retry.items.map(\.mediaID) == Array(21...44))
        #expect(retry.items.allSatisfy { $0.kind == .movie })
    }

    @Test func handlesEmptySourceAndDuplicateItems() async throws {
        let series = [Item(id: 1, views: 10), Item(id: 1, views: 10), Item(id: 2, views: 5)]
        let client = LenAPIClient(transport: StubTransport { request in
            (200, try Self.response(request, movies: [], series: series))
        })
        let page = try await client.trending()
        #expect(page.items.map(\.mediaID) == [1, 2])
        #expect(page.items.allSatisfy { $0.kind == .tv })
        #expect(page.nextCursor == nil)
    }

    @Test func skipsMalformedPageAndUsesDeterministicTies() async throws {
        let client = LenAPIClient(transport: StubTransport { request in
            if request.url?.lastPathComponent == "movies", request.queryValue("page") == "1" {
                return (200, Data(#"{"data":{"items":[{"title":"缺少ID"}],"page":1,"totalPages":2}}"#.utf8))
            }
            return (200, Data(#"{"data":{"items":[{"id":1,"view_count":10}],"page":2,"totalPages":2}}"#.utf8))
        })
        let page = try await client.trending()
        #expect(page.items.map(\.kind) == [.movie, .tv])
        #expect(page.nextCursor == nil)
    }
}

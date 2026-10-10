import Foundation
import os
import Testing
@testable import LenKit

enum Fixture {
    static func data(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }
}

/// 记录请求并返回预设响应的网络桩。
final class StubTransport: HTTPTransport {
    typealias Handler = @Sendable (URLRequest) throws -> (status: Int, body: Data)

    private let handler: Handler
    private let delay: Duration
    private let log = OSAllocatedUnfairLock<[URLRequest]>(initialState: [])

    init(delay: Duration = .zero, handler: @escaping Handler) {
        self.delay = delay
        self.handler = handler
    }

    convenience init(status: Int = 200, fixture: String) throws {
        let body = try Fixture.data(fixture)
        self.init { _ in (status, body) }
    }

    var requests: [URLRequest] { log.withLock { $0 } }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        log.withLock { $0.append(request) }
        if delay > .zero { try await Task.sleep(for: delay) }
        let (status, body) = try handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (body, response)
    }
}

final class InMemoryStore: KeyValueStore {
    private let values = OSAllocatedUnfairLock<[String: Data]>(initialState: [:])

    func data(forKey key: String) -> Data? { values.withLock { $0[key] } }

    func set(_ data: Data?, forKey key: String) { values.withLock { $0[key] = data } }
}

extension URLRequest {
    func queryValue(_ name: String) -> String? {
        url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
            .queryItems?.first { $0.name == name }?.value
    }
}

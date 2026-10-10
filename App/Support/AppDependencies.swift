import LenKit

/// 全局依赖。成员都是 actor，可以在任意并发域使用。
nonisolated final class AppDependencies: Sendable {
    static let live = AppDependencies()

    let api: LenAPIClient
    let history: WatchHistoryStore

    init(api: LenAPIClient = LenAPIClient(), history: WatchHistoryStore = WatchHistoryStore()) {
        self.api = api
        self.history = history
    }
}

import Foundation
import LenKit
import Observation

@Observable
final class HomeModel {
    private(set) var feed: Loadable<HomeFeed> = .idle
    private(set) var continueWatching: [WatchRecord] = []
    private(set) var isLoading = false
    private(set) var refreshNotice: RefreshNotice?

    @ObservationIgnored private let deps: AppDependencies

    init(deps: AppDependencies = .live) {
        self.deps = deps
    }

    struct RefreshNotice: Equatable {
        let id = UUID()
        let message: String
        var isWarning = false
    }

    func load(isRefresh: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        refreshNotice = nil
        defer { isLoading = false }
        if feed.value == nil { feed = .loading }
        do {
            feed = .loaded(try await deps.api.home(forceRefresh: isRefresh))
            if isRefresh { refreshNotice = RefreshNotice(message: "首页已刷新") }
        } catch LenAPIError.cancelled {
            if feed.value == nil { feed = .idle }
        } catch {
            if feed.value == nil { feed = .failed(error.localizedDescription) }
            if isRefresh {
                refreshNotice = RefreshNotice(message: "刷新失败，请稍后重试", isWarning: true)
            }
        }
    }

    func dismissRefreshNotice() {
        refreshNotice = nil
    }

    /// 订阅播放记录：播放器保存进度后首页“继续观看”自动更新
    func observeHistory() async {
        for await records in await deps.history.updates() {
            continueWatching = records.filter { !$0.isFinished }
        }
    }
}

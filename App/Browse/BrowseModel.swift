import Foundation
import LenKit
import Observation

/// 电影 / 剧集分类浏览：筛选条件变化时重新加载，滚动到底部时加载下一页
@Observable
final class BrowseModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loadingMore
        case failed(String)
        case exhausted
    }

    let kind: MediaKind
    var category: MediaCategory?
    var region: String?
    var year: YearOption?
    var status: SeriesStatus?
    var sort: ListSort

    private(set) var categories: [MediaCategory] = []
    private(set) var regions: [String] = []
    private(set) var years: [YearOption] = []
    private(set) var items: [MediaSummary] = []
    private(set) var total: Int?
    private(set) var phase: Phase = .idle

    @ObservationIgnored private let deps: AppDependencies
    @ObservationIgnored private var nextPage = 1
    /// 每次重新加载加一，丢弃旧筛选条件下晚到的结果
    @ObservationIgnored private var generation = 0

    init(kind: MediaKind, deps: AppDependencies = .live) {
        self.kind = kind
        self.sort = kind == .tv ? .latest : .views
        self.deps = deps
    }

    /// 当前筛选条件（不含页码），作为 `.task(id:)` 的标识
    var query: ListQuery {
        ListQuery(kind: kind, categorySlug: category?.slug, region: region, year: year?.value, status: status, sort: sort)
    }

    func loadFilters() async {
        guard categories.isEmpty else { return }
        async let categories = try? deps.api.categories(kind)
        async let regions = try? deps.api.regions()
        async let years = try? deps.api.years()
        self.categories = await categories ?? []
        self.regions = await regions ?? []
        self.years = await years ?? []
    }

    func reload() async {
        generation += 1
        nextPage = 1
        items = []
        total = nil
        phase = .loading
        await fetchNextPage()
    }

    /// 出现倒数第 6 个时开始加载下一页
    func loadMoreIfNeeded(after item: MediaSummary) async {
        guard phase == .idle, let index = items.firstIndex(where: { $0.id == item.id }), index >= items.count - 6 else { return }
        phase = .loadingMore
        await fetchNextPage()
    }

    private func fetchNextPage() async {
        let generation = self.generation
        var query = self.query
        query.page = nextPage
        do {
            let page = try await deps.api.list(query)
            guard generation == self.generation else { return }
            let known = Set(items.map(\.id))
            items += page.items.filter { !known.contains($0.id) }
            total = page.total
            nextPage = page.page + 1
            phase = page.hasMore ? .idle : .exhausted
        } catch LenAPIError.cancelled {
            if generation == self.generation, phase == .loadingMore { phase = .idle }
        } catch {
            guard generation == self.generation else { return }
            phase = .failed(error.localizedDescription)
        }
    }
}

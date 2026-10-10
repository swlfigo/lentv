import Foundation
import LenKit
import Observation

@Observable
final class TrendingModel {
    enum Phase: Equatable {
        case idle, loading, loadingMore, exhausted
        case failed(String)
    }

    private(set) var items: [MediaSummary] = []
    private(set) var phase: Phase = .idle
    @ObservationIgnored private let api: LenAPIClient
    @ObservationIgnored private var cursor: TrendingCursor?
    @ObservationIgnored private var generation = 0

    init(api: LenAPIClient = AppDependencies.live.api) { self.api = api }

    var isLoading: Bool { phase == .loading || phase == .loadingMore }

    func loadIfNeeded() async {
        guard items.isEmpty, phase == .idle else { return }
        await loadNext()
    }

    func reload() async {
        generation += 1
        cursor = nil
        items = []
        phase = .idle
        await loadNext()
    }

    func loadMoreIfNeeded(after item: MediaSummary) async {
        guard phase == .idle, let index = items.firstIndex(where: { $0.id == item.id }),
              index >= items.count - 6 else { return }
        await loadNext()
    }

    func loadNext() async {
        guard !isLoading, phase != .exhausted else { return }
        let generation = generation
        phase = items.isEmpty ? .loading : .loadingMore
        do {
            let page = try await api.trending(after: cursor)
            guard generation == self.generation else { return }
            items += page.items
            cursor = page.nextCursor
            phase = cursor == nil ? .exhausted : .idle
        } catch LenAPIError.cancelled {
            if generation == self.generation { phase = .idle }
        } catch {
            guard generation == self.generation else { return }
            phase = .failed(error.localizedDescription)
        }
    }
}

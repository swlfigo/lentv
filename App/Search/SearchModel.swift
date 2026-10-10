import Combine
import Foundation
import LenKit
import Observation

@Observable
final class SearchModel {
    enum State: Equatable {
        case idle
        case loading
        case results([MediaSummary])
        case empty(String)
        case failed(String)
    }

    /// 绑定到搜索框；变化经 Combine 防抖后再请求
    var query = "" {
        didSet { querySubject.send(query) }
    }

    private(set) var state: State = .idle

    @ObservationIgnored private let deps: AppDependencies
    @ObservationIgnored private let querySubject = PassthroughSubject<String, Never>()
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    init(deps: AppDependencies = .live) {
        self.deps = deps
        querySubject
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] text in self?.search(text) }
            .store(in: &cancellables)
    }

    func retry() {
        search(query.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func search(_ text: String) {
        searchTask?.cancel()
        guard !text.isEmpty else {
            state = .idle
            return
        }
        state = .loading
        let api = deps.api
        searchTask = Task { [weak self] in
            do {
                let results = try await api.search(text)
                guard !Task.isCancelled else { return }
                self?.state = results.isEmpty ? .empty(text) : .results(results)
            } catch LenAPIError.cancelled {
            } catch {
                guard !Task.isCancelled else { return }
                self?.state = .failed(error.localizedDescription)
            }
        }
    }
}

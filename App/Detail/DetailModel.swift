import Foundation
import LenKit
import Observation

@Observable
final class DetailModel {
    let route: DetailRoute
    private(set) var detail: Loadable<MediaDetail> = .idle
    private(set) var record: WatchRecord?
    /// 还没开始播放时在详情页选中的线路
    var selectedLine = 0
    /// 正在进行的播放；tvOS 上非空时全屏显示播放器，其它平台显示在详情页顶部
    var playback: PlaybackController?

    @ObservationIgnored private let deps: AppDependencies
    @ObservationIgnored private var didAutoplay = false

    init(route: DetailRoute, deps: AppDependencies = .live) {
        self.route = route
        self.deps = deps
    }

    var summary: MediaSummary { route.summary }

    func load() async {
        if detail.value == nil { detail = .loading }
        record = await deps.history.record(for: summary.id)
        do {
            let loaded = try await deps.api.detail(summary.kind, id: summary.mediaID)
            detail = .loaded(loaded)
            if let record, let cursor = loaded.cursor(episode: record.episodeNumber, preferredLineKey: record.lineKey) {
                selectedLine = cursor.lineIndex
            } else {
                selectedLine = loaded.firstCursor?.lineIndex ?? 0
            }
            if route.autoplay, !didAutoplay {
                didAutoplay = true
                play()
            }
        } catch LenAPIError.cancelled {
        } catch {
            if detail.value == nil { detail = .failed(error.localizedDescription) }
        }
    }

    /// 当前高亮的线路：播放中跟随播放器，否则是详情页的选择
    var activeLine: Int { playback?.cursor.lineIndex ?? selectedLine }

    /// 当前高亮的集数：播放中的集，否则是上次看到的集
    var activeEpisode: Int? { playback?.cursor.episodeNumber ?? record?.episodeNumber }

    /// “继续播放 第3集 · 12:08” / “播放”
    var playButtonTitle: String {
        guard let record, record.resumePosition > 0 else { return "播放" }
        let episode = summary.kind == .tv ? " \(record.episodeTitle)" : ""
        return "继续播放\(episode) · \(TimeText.clock(record.resumePosition))"
    }

    func selectLine(_ index: Int) {
        if let playback {
            playback.selectLine(index)
        } else {
            selectedLine = index
        }
    }

    /// 播放按钮：有记录就从上次的位置继续，否则从选中线路的第一集开始
    func play() {
        guard let detail = detail.value else { return }
        if let record, let cursor = detail.cursor(episode: record.episodeNumber, preferredLineKey: record.lineKey) {
            start(detail, cursor: cursor, at: record.resumePosition)
        } else if let episode = detail.lines[safe: selectedLine]?.episodes.first(where: \.isPlayable) {
            start(detail, cursor: PlaybackCursor(lineIndex: selectedLine, episodeNumber: episode.number), at: nil)
        } else if let cursor = detail.firstCursor {
            start(detail, cursor: cursor, at: nil)
        }
    }

    /// 选集：如果正好是上次看到的那集，从上次的位置继续
    func play(episode number: Int) {
        guard let detail = detail.value else { return }
        if let playback {
            playback.selectEpisode(number)
            return
        }
        let preferredKey = detail.lines[safe: selectedLine]?.key
        guard let cursor = detail.cursor(episode: number, preferredLineKey: preferredKey) else { return }
        let resume = record.flatMap { $0.episodeNumber == number ? $0.resumePosition : nil }
        start(detail, cursor: cursor, at: resume)
    }

    func stopPlayback() {
        playback?.stop()
        playback = nil
        Task { record = await deps.history.record(for: summary.id) }
    }

    private func start(_ detail: MediaDetail, cursor: PlaybackCursor, at position: Double?) {
        playback?.stop()
        let controller = PlaybackController(detail: detail, cursor: cursor, startAt: position, deps: deps)
        playback = controller
        controller.start()
    }
}

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

import AVFoundation
import AVKit
import Combine
import LenKit
import Observation
import os

/// 一次播放会话：持有 AVPlayer，负责切换线路、失败自动换线、自动连播和保存进度。
/// 各平台的播放器界面只负责显示 `player`，并把用户操作转给这里。
@Observable
final class PlaybackController: Identifiable {
    struct Notice: Equatable, Identifiable {
        let id = UUID()
        let text: String
        var isWarning = false
    }

    enum Phase: Equatable {
        case loading
        case playing
        case failed(String)
        case ended
    }

    let detail: MediaDetail
    let player = AVPlayer()
    private(set) var cursor: PlaybackCursor
    private(set) var phase: Phase = .loading
    private(set) var notice: Notice?

    /// 系统播放器正在全屏或画中画：此时详情页虽然“消失”了，播放不能停
    @ObservationIgnored var isPresentingFullScreen = false
    @ObservationIgnored var isInPictureInPicture = false
    var keepsPlayingWhenHidden: Bool { isPresentingFullScreen || isInPictureInPicture }

    @ObservationIgnored private let deps: AppDependencies
    @ObservationIgnored private let startPosition: Double?
    @ObservationIgnored private var itemObservers = Set<AnyCancellable>()
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var stallTask: Task<Void, Never>?
    /// 当前这一集已经失败过的线路
    @ObservationIgnored private var failedLines: Set<Int> = []
    @ObservationIgnored private var pendingSeek: Double?
    @ObservationIgnored private var lastKnownPosition: Double?
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var isStopped = false

    /// 线路加载超过这个时间还没就绪就视为失败
    private static let stallTimeout: Duration = .seconds(25)
    private static let logger = Logger(subsystem: "dev.lentvos.LenTV", category: "Playback")

    init(detail: MediaDetail, cursor: PlaybackCursor, startAt position: Double? = nil, deps: AppDependencies = .live) {
        self.detail = detail
        self.cursor = cursor
        self.startPosition = position
        self.deps = deps
    }

    var currentLine: SourceLine? { detail.line(at: cursor) }
    var currentEpisode: Episode? { detail.episode(at: cursor) }

    /// 是否需要显示选集（电影只有“正片”一集）
    var hasEpisodes: Bool { detail.lines.contains { $0.episodes.count > 1 } }

    /// “蜘蛛侠：崭新之日 · 豆瓣” / “第3集 · 红牛”
    var subtitle: String {
        [hasEpisodes ? currentEpisode?.title : nil, currentLine?.name.appending(" 线路")]
            .compactMap(\.self)
            .joined(separator: " · ")
    }

    // MARK: - 控制

    func start() {
        guard !isStarted else { return }
        isStarted = true
        let interval = CMTime(seconds: 10, preferredTimescale: 1)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveProgress() }
        }
        load(cursor, at: startPosition)
    }

    /// 用户切换线路：从当前进度继续
    func selectLine(_ index: Int) {
        guard index != cursor.lineIndex, detail.lines.indices.contains(index),
              detail.lines[index].episode(number: cursor.episodeNumber)?.isPlayable == true else { return }
        let position = currentPosition
        failedLines = []
        let name = detail.lines[index].name
        show(Notice(text: position.map { "已切换到 \(name) 线路，从 \(TimeText.clock($0)) 继续" } ?? "已切换到 \(name) 线路"))
        load(PlaybackCursor(lineIndex: index, episodeNumber: cursor.episodeNumber), at: position)
    }

    /// 用户选集：优先当前线路
    func selectEpisode(_ number: Int) {
        guard number != cursor.episodeNumber,
              let target = detail.cursor(episode: number, preferredLineKey: currentLine?.key) else { return }
        saveProgress()
        failedLines = []
        load(target, at: nil)
    }

    func retry() {
        failedLines = []
        load(cursor, at: lastKnownPosition)
    }

    /// 离开播放界面时调用：保存进度并释放播放器
    func stop() {
        guard !isStopped else { return }
        saveProgress()
        isStopped = true
        loadTask?.cancel()
        stallTask?.cancel()
        itemObservers.removeAll()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    func dismissNotice(_ id: Notice.ID) {
        if notice?.id == id { notice = nil }
    }

    #if os(iOS)
    func pictureInPictureFailed(_ error: any Error) {
        // willStart 之后仍可能失败，不能留下“画中画中”的状态，导致离开详情后无法清理播放。
        isInPictureInPicture = false
        Self.logger.error("Picture in Picture failed: \(error.localizedDescription)")
        show(Notice(text: "画中画未能启动，请在应用内继续播放。", isWarning: true))
    }

    private func activateAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            // 仅设置 category 不等于激活。开始播放时激活，确保后台播放 / PiP 可使用音频会话。
            try session.setActive(true)
        } catch {
            Self.logger.error("Audio session activation failed: \(error.localizedDescription)")
            show(Notice(text: "音频会话未能启动，后台播放和画中画可能不可用。", isWarning: true))
        }
    }
    #endif

    // MARK: - 加载

    private var currentPosition: Double? {
        let seconds = player.currentTime().seconds
        return seconds.isFinite && seconds > 1 ? seconds : lastKnownPosition
    }

    private func load(_ target: PlaybackCursor, at position: Double?) {
        loadTask?.cancel()
        stallTask?.cancel()
        itemObservers.removeAll()
        cursor = target
        phase = .loading
        pendingSeek = position
        lastKnownPosition = position

        guard let line = detail.line(at: target), let episode = detail.episode(at: target) else {
            handleFailure(of: nil)
            return
        }

        #if os(iOS)
        activateAudioSession()
        #endif

        let api = deps.api
        let kind = detail.kind
        let mediaID = detail.id
        loadTask = Task { [weak self] in
            var url = episode.videoURL
            if url == nil {
                url = try? await api.playURL(kind, id: mediaID, episode: episode.number, lineKey: line.key)
            }
            guard let self, !Task.isCancelled, !self.isStopped else { return }
            guard let url else {
                self.handleFailure(of: nil)
                return
            }
            let item = AVPlayerItem(url: url)
            self.applyMetadata(to: item, episode: episode)
            self.observe(item)
            self.player.replaceCurrentItem(with: item)
            self.player.play()
            self.watchForStall(of: item)
        }
    }

    /// Combine 监听播放状态：就绪、失败、播放结束
    private func observe(_ item: AVPlayerItem) {
        item.publisher(for: \.status)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak item] status in
                guard let self, let item else { return }
                switch status {
                case .readyToPlay: self.handleReady(item)
                case .failed: self.handleFailure(of: item)
                default: break
                }
            }
            .store(in: &itemObservers)

        NotificationCenter.default.publisher(for: AVPlayerItem.failedToPlayToEndTimeNotification, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak item] _ in self?.handleFailure(of: item) }
            .store(in: &itemObservers)

        NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak item] _ in self?.handleEnd(of: item) }
            .store(in: &itemObservers)
    }

    private func watchForStall(of item: AVPlayerItem) {
        stallTask = Task { [weak self, weak item] in
            try? await Task.sleep(for: Self.stallTimeout)
            guard !Task.isCancelled, let self, let item, self.phase == .loading else { return }
            self.handleFailure(of: item)
        }
    }

    private func handleReady(_ item: AVPlayerItem) {
        guard item === player.currentItem, phase == .loading else { return }
        stallTask?.cancel()
        phase = .playing
        failedLines = []
        if let seek = pendingSeek, seek > 1 {
            player.seek(to: CMTime(seconds: seek, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .positiveInfinity)
        }
        pendingSeek = nil
    }

    /// 当前线路失败：换下一条有这一集的线路，都失败了才报错
    private func handleFailure(of item: AVPlayerItem?) {
        guard !isStopped, item == nil || item === player.currentItem else { return }
        guard phase == .loading || phase == .playing else { return }
        stallTask?.cancel()
        let position = currentPosition ?? pendingSeek
        failedLines.insert(cursor.lineIndex)

        if let next = detail.fallbackCursor(after: cursor, excluding: failedLines) {
            let from = currentLine?.name ?? "当前"
            let to = detail.lines[next.lineIndex].name
            show(Notice(text: "\(from) 线路无法播放，已自动切换到 \(to)", isWarning: true))
            load(next, at: position)
        } else {
            lastKnownPosition = position
            player.pause()
            let count = detail.lineIndices(containing: cursor.episodeNumber).count
            phase = .failed(count > 1 ? "\(count) 条线路都无法播放，请稍后再试，或换一部片子。" : "这条线路无法播放，请稍后再试，或换一部片子。")
        }
    }

    private func handleEnd(of item: AVPlayerItem?) {
        guard item === player.currentItem else { return }
        saveProgress()
        if let next = detail.nextEpisodeCursor(after: cursor) {
            let title = detail.episode(at: next)?.title ?? "下一集"
            show(Notice(text: "正在播放 \(title)"))
            failedLines = []
            load(next, at: nil)
        } else {
            phase = .ended
        }
    }

    private func show(_ notice: Notice) {
        self.notice = notice
    }

    // MARK: - 进度与信息

    private func saveProgress() {
        guard !isStopped, let line = currentLine, let episode = currentEpisode else { return }
        let position = player.currentTime().seconds
        guard position.isFinite, position > 5 else { return }
        lastKnownPosition = position
        let duration = player.currentItem?.duration.seconds ?? 0
        let record = WatchRecord(
            media: detail.mediaID, title: detail.title, posterURL: detail.posterURL,
            episodeNumber: episode.number, episodeTitle: episode.title,
            lineKey: line.key, lineName: line.name,
            position: position, duration: duration.isFinite ? duration : 0)
        let history = deps.history
        Task { await history.save(record) }
    }

    private func applyMetadata(to item: AVPlayerItem, episode: Episode) {
        #if os(iOS) || os(tvOS)
        // tvOS 播放器信息面板和系统“正在播放”里显示的标题
        func entry(_ identifier: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
            let metadata = AVMutableMetadataItem()
            metadata.identifier = identifier
            metadata.value = value as NSString
            metadata.extendedLanguageTag = "und"
            return metadata
        }
        var items = [entry(.commonIdentifierTitle, detail.title)]
        if !subtitle.isEmpty { items.append(entry(.iTunesMetadataTrackSubTitle, subtitle)) }
        if let summary = detail.summary { items.append(entry(.commonIdentifierDescription, summary)) }
        item.externalMetadata = items
        #endif
    }
}

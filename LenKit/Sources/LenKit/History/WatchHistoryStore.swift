import Foundation

/// 一部片子的播放记录（每部只保留最近一条）。
public struct WatchRecord: Sendable, Hashable, Codable, Identifiable {
    public var media: MediaSummary.ID
    public var title: String
    public var posterURL: URL?
    public var episodeNumber: Int
    public var episodeTitle: String
    public var lineKey: String
    public var lineName: String
    /// 秒
    public var position: Double
    /// 秒，未知时为 0
    public var duration: Double
    public var updatedAt: Date

    public var id: MediaSummary.ID { media }

    public init(
        media: MediaSummary.ID, title: String, posterURL: URL?, episodeNumber: Int, episodeTitle: String,
        lineKey: String, lineName: String, position: Double, duration: Double, updatedAt: Date = .now
    ) {
        self.media = media
        self.title = title
        self.posterURL = posterURL
        self.episodeNumber = episodeNumber
        self.episodeTitle = episodeTitle
        self.lineKey = lineKey
        self.lineName = lineName
        self.position = position
        self.duration = duration
        self.updatedAt = updatedAt
    }

    public var progress: Double {
        duration > 0 ? min(max(position / duration, 0), 1) : 0
    }

    public var remaining: Double { max(duration - position, 0) }

    /// 看到 95% 以后视为看完，下次从头播放
    public var isFinished: Bool { duration > 0 && progress >= 0.95 }

    /// 继续播放的起点；看完了就从头开始
    public var resumePosition: Double { isFinished ? 0 : position }

    public var summary: MediaSummary {
        MediaSummary(kind: media.kind, mediaID: media.value, title: title, posterURL: posterURL)
    }
}

/// 简单的键值存储，默认用 UserDefaults（tvOS 没有可长期保存的文件目录）。
public protocol KeyValueStore: Sendable {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
}

public struct UserDefaultsStore: KeyValueStore, @unchecked Sendable {
    // UserDefaults 本身是线程安全的
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func data(forKey key: String) -> Data? { defaults.data(forKey: key) }

    public func set(_ data: Data?, forKey key: String) { defaults.set(data, forKey: key) }
}

/// 本地播放记录。tvOS 上 UserDefaults 约有 500KB 上限，所以只保留最近的若干条。
public actor WatchHistoryStore {
    private let storage: any KeyValueStore
    private let key: String
    private let limit: Int
    private let encoder = JSONEncoder()
    private var records: [WatchRecord]
    private var continuations: [UUID: AsyncStream<[WatchRecord]>.Continuation] = [:]

    public init(storage: any KeyValueStore = UserDefaultsStore(), key: String = "lentv.watchHistory.v1", limit: Int = 60) {
        self.storage = storage
        self.key = key
        self.limit = limit
        let decoded = storage.data(forKey: key).flatMap { try? JSONDecoder().decode([WatchRecord].self, from: $0) }
        self.records = (decoded ?? []).sorted { $0.updatedAt > $1.updatedAt }
    }

    /// 按最近观看排序
    public func all() -> [WatchRecord] { records }

    /// 首页“继续观看”：还没看完的
    public func continueWatching() -> [WatchRecord] { records.filter { !$0.isFinished } }

    public func record(for media: MediaSummary.ID) -> WatchRecord? {
        records.first { $0.media == media }
    }

    public func save(_ record: WatchRecord) {
        records.removeAll { $0.media == record.media }
        records.insert(record, at: 0)
        if records.count > limit { records.removeLast(records.count - limit) }
        persist()
    }

    public func remove(_ media: MediaSummary.ID) {
        records.removeAll { $0.media == media }
        persist()
    }

    /// 订阅变化：先收到当前列表，之后每次保存都会收到新列表
    public func updates() -> AsyncStream<[WatchRecord]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [WatchRecord].self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(id) }
        }
        continuation.yield(records)
        return stream
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }

    private func persist() {
        storage.set(try? encoder.encode(records), forKey: key)
        for continuation in continuations.values { continuation.yield(records) }
    }
}

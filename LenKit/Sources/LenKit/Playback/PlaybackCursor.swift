import Foundation

/// 正在播放的位置：哪条线路的第几集。
public struct PlaybackCursor: Sendable, Hashable, Codable {
    public var lineIndex: Int
    public var episodeNumber: Int

    public init(lineIndex: Int, episodeNumber: Int) {
        self.lineIndex = lineIndex
        self.episodeNumber = episodeNumber
    }
}

extension MediaDetail {
    public func line(at cursor: PlaybackCursor) -> SourceLine? {
        lines.indices.contains(cursor.lineIndex) ? lines[cursor.lineIndex] : nil
    }

    public func episode(at cursor: PlaybackCursor) -> Episode? {
        line(at: cursor)?.episode(number: cursor.episodeNumber)
    }

    /// 第一条有可播放集数的线路的第一集。
    public var firstCursor: PlaybackCursor? {
        for (index, line) in lines.enumerated() {
            if let episode = line.episodes.first(where: \.isPlayable) {
                return PlaybackCursor(lineIndex: index, episodeNumber: episode.number)
            }
        }
        return nil
    }

    /// 恢复播放位置：优先用上次的线路，这条线路没有这一集时换一条有的。
    public func cursor(episode: Int, preferredLineKey: String?) -> PlaybackCursor? {
        if let key = preferredLineKey,
           let index = lines.firstIndex(where: { $0.key == key }),
           lines[index].episode(number: episode)?.isPlayable == true {
            return PlaybackCursor(lineIndex: index, episodeNumber: episode)
        }
        if let index = lines.firstIndex(where: { $0.episode(number: episode)?.isPlayable == true }) {
            return PlaybackCursor(lineIndex: index, episodeNumber: episode)
        }
        return firstCursor
    }

    /// 当前线路播放失败时的下一条线路：从当前线路之后开始找，跳过已经试过的和没有这一集的。
    public func fallbackCursor(after cursor: PlaybackCursor, excluding tried: Set<Int>) -> PlaybackCursor? {
        guard !lines.isEmpty else { return nil }
        for offset in 1..<max(lines.count, 1) {
            let index = (cursor.lineIndex + offset) % lines.count
            guard !tried.contains(index) else { continue }
            if lines[index].episode(number: cursor.episodeNumber)?.isPlayable == true {
                return PlaybackCursor(lineIndex: index, episodeNumber: cursor.episodeNumber)
            }
        }
        return nil
    }

    /// 自动连播的下一集：优先同一条线路，这条线路没有下一集时换一条有的。
    public func nextEpisodeCursor(after cursor: PlaybackCursor) -> PlaybackCursor? {
        let next = lines.flatMap(\.episodes).map(\.number).filter { $0 > cursor.episodeNumber }.min()
        guard let next else { return nil }
        if line(at: cursor)?.episode(number: next)?.isPlayable == true {
            return PlaybackCursor(lineIndex: cursor.lineIndex, episodeNumber: next)
        }
        return self.cursor(episode: next, preferredLineKey: nil)
    }

    /// 线路是否有某一集，用于在菜单里禁用没有这一集的线路。
    public func lineIndices(containing episode: Int) -> [Int] {
        lines.indices.filter { lines[$0].episode(number: episode)?.isPlayable == true }
    }
}

/// 选集网格的一页（例如“1–30”）。
public struct EpisodePage: Sendable, Hashable, Identifiable {
    public let episodes: [Episode]

    public var id: Int { episodes.first?.number ?? 0 }

    public var label: String {
        guard let first = episodes.first?.number, let last = episodes.last?.number else { return "" }
        return first == last ? "\(first)" : "\(first)–\(last)"
    }
}

extension SourceLine {
    public func episodePages(size: Int = 30) -> [EpisodePage] {
        stride(from: 0, to: episodes.count, by: max(size, 1)).map { start in
            EpisodePage(episodes: Array(episodes[start..<min(start + size, episodes.count)]))
        }
    }
}

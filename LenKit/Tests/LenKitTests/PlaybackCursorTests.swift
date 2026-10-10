import Foundation
import Testing
@testable import LenKit

@Suite("线路切换与连播")
struct PlaybackCursorTests {
    /// a: 1–3 集；b: 1–2 集，第 2 集不可用；c: 1–4 集；empty: 没有可播放的集
    let detail: MediaDetail = {
        func episodes(_ numbers: ClosedRange<Int>, unavailable: Set<Int> = []) -> [Episode] {
            numbers.map {
                Episode(number: $0, title: "第\($0)集", videoURL: URL(string: "https://example.com/\($0).m3u8"),
                        isAvailable: !unavailable.contains($0))
            }
        }
        return MediaDetail(kind: .tv, id: 1, title: "测试剧", lines: [
            SourceLine(key: "empty", name: "空", episodes: [Episode(number: 1, title: "第1集", videoURL: nil)]),
            SourceLine(key: "a", name: "甲", episodes: episodes(1...3)),
            SourceLine(key: "b", name: "乙", episodes: episodes(1...2, unavailable: [2])),
            SourceLine(key: "c", name: "丙", episodes: episodes(1...4)),
        ])
    }()

    @Test func firstCursorSkipsUnplayableLines() {
        #expect(detail.firstCursor == PlaybackCursor(lineIndex: 1, episodeNumber: 1))
    }

    @Test func fallbackSkipsLinesWithoutTheEpisode() {
        let current = PlaybackCursor(lineIndex: 1, episodeNumber: 2)
        #expect(detail.fallbackCursor(after: current, excluding: [1]) == PlaybackCursor(lineIndex: 3, episodeNumber: 2))
    }

    @Test func fallbackWrapsAroundAndStopsWhenExhausted() {
        let current = PlaybackCursor(lineIndex: 3, episodeNumber: 1)
        #expect(detail.fallbackCursor(after: current, excluding: [3]) == PlaybackCursor(lineIndex: 1, episodeNumber: 1))
        #expect(detail.fallbackCursor(after: current, excluding: [1, 2, 3]) == nil)
    }

    @Test func nextEpisodePrefersSameLine() {
        #expect(detail.nextEpisodeCursor(after: PlaybackCursor(lineIndex: 1, episodeNumber: 1)) == PlaybackCursor(lineIndex: 1, episodeNumber: 2))
        // 甲线路只有 3 集，第 4 集换到丙
        #expect(detail.nextEpisodeCursor(after: PlaybackCursor(lineIndex: 1, episodeNumber: 3)) == PlaybackCursor(lineIndex: 3, episodeNumber: 4))
        #expect(detail.nextEpisodeCursor(after: PlaybackCursor(lineIndex: 3, episodeNumber: 4)) == nil)
    }

    @Test func restoreCursorFallsBackWhenPreferredLineLacksEpisode() {
        #expect(detail.cursor(episode: 2, preferredLineKey: "c") == PlaybackCursor(lineIndex: 3, episodeNumber: 2))
        #expect(detail.cursor(episode: 2, preferredLineKey: "b") == PlaybackCursor(lineIndex: 1, episodeNumber: 2))
        #expect(detail.cursor(episode: 9, preferredLineKey: nil) == detail.firstCursor)
    }

    @Test func linesContainingEpisode() {
        #expect(detail.lineIndices(containing: 2) == [1, 3])
    }

    @Test func episodePages() {
        let line = SourceLine(key: "x", name: "x", episodes: (1...65).map { Episode(number: $0, title: "", videoURL: nil) })
        #expect(line.episodePages(size: 30).map(\.label) == ["1–30", "31–60", "61–65"])
        #expect(SourceLine(key: "y", name: "y", episodes: [Episode(number: 1, title: "正片", videoURL: nil)]).episodePages().map(\.label) == ["1"])
    }
}

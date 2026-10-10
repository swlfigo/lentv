import Foundation
import Testing
@testable import LenKit

@Suite("播放记录")
struct WatchHistoryStoreTests {
    func record(_ id: Int, episode: Int = 1, position: Double = 60, duration: Double = 600, at time: TimeInterval = 0) -> WatchRecord {
        WatchRecord(
            media: MediaSummary.ID(kind: .tv, value: id), title: "片\(id)", posterURL: nil, episodeNumber: episode,
            episodeTitle: "第\(episode)集", lineKey: "a", lineName: "甲", position: position, duration: duration,
            updatedAt: Date(timeIntervalSince1970: time))
    }

    @Test func latestSaveComesFirstAndReplacesOldRecord() async {
        let store = WatchHistoryStore(storage: InMemoryStore())
        await store.save(record(1, at: 1))
        await store.save(record(2, at: 2))
        await store.save(record(1, episode: 3, at: 3))

        let all = await store.all()
        #expect(all.map(\.media.value) == [1, 2])
        #expect(all.first?.episodeNumber == 3)
    }

    @Test func keepsOnlyLimit() async {
        let store = WatchHistoryStore(storage: InMemoryStore(), limit: 3)
        for id in 1...5 { await store.save(record(id)) }
        #expect(await store.all().map(\.media.value) == [5, 4, 3])
    }

    @Test func persistsAcrossInstances() async {
        let storage = InMemoryStore()
        await WatchHistoryStore(storage: storage).save(record(7, episode: 2))
        let restored = await WatchHistoryStore(storage: storage).record(for: MediaSummary.ID(kind: .tv, value: 7))
        #expect(restored?.episodeNumber == 2)
    }

    @Test func finishedRecordsLeaveContinueWatching() async {
        let store = WatchHistoryStore(storage: InMemoryStore())
        await store.save(record(1, position: 590, duration: 600))
        await store.save(record(2, position: 100, duration: 600))
        #expect(await store.continueWatching().map(\.media.value) == [2])
        #expect(await store.record(for: MediaSummary.ID(kind: .tv, value: 1))?.resumePosition == 0)
    }

    @Test func updatesStreamYieldsCurrentThenChanges() async {
        let store = WatchHistoryStore(storage: InMemoryStore())
        await store.save(record(1))
        var iterator = await store.updates().makeAsyncIterator()

        #expect(await iterator.next()?.map(\.media.value) == [1])
        await store.save(record(2))
        #expect(await iterator.next()?.map(\.media.value) == [2, 1])
    }
}

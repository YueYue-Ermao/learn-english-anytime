import Foundation
import Testing
@testable import ContextEnglishCore

@Suite("Pause manager")
struct PauseManagerTests {
    @Test("Global pause expires and clears itself")
    func globalPauseExpiresAndClearsItself() {
        let store = MemoryPauseStore()
        var now = Date(timeIntervalSince1970: 1_000)
        let manager = PauseManager(store: store, now: { now })

        manager.pause(.global, for: 3_600)
        #expect(manager.activePause(for: .global) != nil)
        #expect(abs((manager.remainingTime(for: .global) ?? 0) - 3_600) < 0.001)

        now = now.addingTimeInterval(3_601)
        #expect(manager.activePause(for: .global) == nil)
        #expect(store.date(forKey: "pause.global") == nil)
    }

    @Test("Global pause takes priority over application pause")
    func globalPauseTakesPriorityOverApplicationPause() {
        let store = MemoryPauseStore()
        let now = Date(timeIntervalSince1970: 2_000)
        let manager = PauseManager(store: store, now: { now })

        manager.pause(.application("com.microsoft.Word"), for: 600)
        let global = manager.pause(.global, for: 1_200)

        #expect(manager.activePause(forApplicationID: "com.microsoft.Word") == global)
    }

    @Test("Resume only clears the requested scope")
    func resumeOnlyClearsRequestedScope() {
        let store = MemoryPauseStore()
        let now = Date(timeIntervalSince1970: 3_000)
        let manager = PauseManager(store: store, now: { now })

        manager.pause(.global, for: 600)
        manager.pause(.application("com.apple.Safari"), for: 600)
        manager.resume(.global)

        #expect(manager.activePause(for: .global) == nil)
        #expect(manager.activePause(for: .application("com.apple.Safari")) != nil)
    }
}

private final class MemoryPauseStore: PauseStore {
    private var values: [String: Date] = [:]

    func date(forKey key: String) -> Date? {
        values[key]
    }

    func setDate(_ date: Date?, forKey key: String) {
        values[key] = date
    }
}

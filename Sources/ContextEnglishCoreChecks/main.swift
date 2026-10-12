import ContextEnglishCore
import Darwin
import Foundation

private final class MemoryPauseStore: PauseStore {
    private var values: [String: Date] = [:]

    func date(forKey key: String) -> Date? {
        values[key]
    }

    func setDate(_ date: Date?, forKey key: String) {
        values[key] = date
    }
}

private var failures: [String] = []

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        failures.append(message)
    }
}

private func snapshot(_ text: String, surface: SurfaceKind) -> SelectionSnapshot {
    SelectionSnapshot(
        text: text,
        bounds: nil,
        source: .macOSAccessibility,
        sourceApplicationID: "test.application",
        surfaceKind: surface
    )
}

private func runPauseChecks() {
    let store = MemoryPauseStore()
    var now = Date(timeIntervalSince1970: 1_000)
    let manager = PauseManager(store: store, now: { now })

    manager.pause(.global, for: 3_600)
    check(manager.activePause(for: .global) != nil, "global pause should activate")
    check(
        abs((manager.remainingTime(for: .global) ?? 0) - 3_600) < 0.001,
        "global pause should expose the correct remaining duration"
    )

    now = now.addingTimeInterval(3_601)
    check(manager.activePause(for: .global) == nil, "expired pause should clear itself")

    manager.pause(.application("com.apple.Safari"), for: 600)
    check(
        manager.activePause(forApplicationID: "com.apple.Safari") != nil,
        "application pause should apply to the matching bundle identifier"
    )
    manager.resume(.application("com.apple.Safari"))
    check(
        manager.activePause(forApplicationID: "com.apple.Safari") == nil,
        "application pause should resume independently"
    )
}

private func runTriggerPolicyChecks() {
    let policy = TriggerPolicy()

    check(
        policy.decision(
            for: snapshot("prioritize", surface: .readOnly),
            mode: .smart,
            isPaused: false
        ) == .full,
        "smart mode should fully expand for read-only text"
    )
    check(
        policy.decision(
            for: snapshot("prioritize", surface: .editable),
            mode: .smart,
            isPaused: false
        ) == .hint,
        "smart mode should use a hint for editable text"
    )
    check(
        policy.decision(
            for: snapshot("prioritize", surface: .readOnly),
            mode: .alwaysFull,
            isPaused: true
        ) == .none,
        "paused selections must not trigger"
    )
    check(
        policy.decision(
            for: snapshot("12345", surface: .readOnly),
            mode: .alwaysFull,
            isPaused: false
        ) == .none,
        "numbers alone must not trigger"
    )
}

private func runTextContextChecks() {
    check(TextLanguageDetector.detect("prioritize") == .english, "English should be detected")
    check(TextLanguageDetector.detect("推进项目") == .chinese, "Chinese should be detected")
    check(TextLanguageDetector.detect("推进 project") == .mixed, "mixed text should be detected")

    let chinese = "上一句。我们需要推进这个项目，确保按计划交付。下一句。"
    let nsChinese = chinese as NSString
    let selectedRange = nsChinese.range(of: "推进")
    let context = SentenceContextExtractor.extract(
        from: chinese,
        selectedRangeUTF16: selectedRange
    )
    check(context?.text == "我们需要推进这个项目，确保按计划交付。", "Chinese sentence context should be extracted")
    check(context?.selectionStartUTF16 == 4, "selection offset should be relative to context")
    check(context?.selectionLengthUTF16 == 2, "selection length should be preserved")

    let repeated = SentenceContextExtractor.extractUniqueOccurrence(
        of: "issue",
        from: "This issue is different from that issue."
    )
    check(repeated == nil, "ambiguous repeated selections must not invent context")
}

private func runLookupRoutingChecks() {
    let policy = LookupRoutingPolicy()
    check(
        policy.route(for: "prioritize", language: .english) == .localDictionaryFirst,
        "simple English words should prefer the local dictionary"
    )
    check(
        policy.route(for: "面试", language: .chinese) == .localDictionaryFirst,
        "simple Chinese terms should prefer the local dictionary"
    )
    check(
        policy.route(for: "我会先确认需求优先级，再评估成本。", language: .chinese) == .modelRecommended,
        "Chinese sentences should recommend contextual translation"
    )
}

runPauseChecks()
runTriggerPolicyChecks()
runTextContextChecks()
runLookupRoutingChecks()

if failures.isEmpty {
    print("Core checks passed")
} else {
    failures.forEach { fputs("FAIL: \($0)\n", stderr) }
    exit(1)
}

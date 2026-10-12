import Foundation
import Testing
@testable import ContextEnglishCore

@Suite("Trigger policy")
struct TriggerPolicyTests {
    private let policy = TriggerPolicy()

    @Test("Paused selection never triggers")
    func pausedSelectionNeverTriggers() {
        let decision = policy.decision(
            for: snapshot(text: "prioritize", surface: .readOnly),
            mode: .alwaysFull,
            isPaused: true
        )
        #expect(decision == .none)
    }

    @Test("Smart mode uses a full card for read-only text")
    func smartModeUsesFullCardForReadOnlyText() {
        let decision = policy.decision(
            for: snapshot(text: "prioritize", surface: .readOnly),
            mode: .smart,
            isPaused: false
        )
        #expect(decision == .full)
    }

    @Test("Smart mode uses a hint for editable text")
    func smartModeUsesHintForEditableText() {
        let decision = policy.decision(
            for: snapshot(text: "prioritize", surface: .editable),
            mode: .smart,
            isPaused: false
        )
        #expect(decision == .hint)
    }

    @Test("Numbers alone do not trigger")
    func numbersOnlyDoNotTrigger() {
        let decision = policy.decision(
            for: snapshot(text: "12345", surface: .readOnly),
            mode: .alwaysFull,
            isPaused: false
        )
        #expect(decision == .none)
    }

    @Test("Manual mode does not automatically trigger")
    func manualModeDoesNotAutomaticallyTrigger() {
        let decision = policy.decision(
            for: snapshot(text: "align", surface: .readOnly),
            mode: .manualOnly,
            isPaused: false
        )
        #expect(decision == .none)
    }

    private func snapshot(text: String, surface: SurfaceKind) -> SelectionSnapshot {
        SelectionSnapshot(
            text: text,
            bounds: nil,
            source: .macOSAccessibility,
            sourceApplicationID: "test.application",
            surfaceKind: surface
        )
    }
}

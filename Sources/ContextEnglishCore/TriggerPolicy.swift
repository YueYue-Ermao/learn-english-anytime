import Foundation

public enum TriggerMode: String, CaseIterable, Codable, Sendable {
    case smart
    case alwaysFull
    case hintOnly
    case manualOnly
    case disabled
}

public enum TriggerDecision: Equatable, Sendable {
    case none
    case hint
    case full
}

public struct TriggerPolicy: Sendable {
    public let maximumAutomaticSelectionLength: Int

    public init(maximumAutomaticSelectionLength: Int = 500) {
        self.maximumAutomaticSelectionLength = maximumAutomaticSelectionLength
    }

    public func decision(
        for snapshot: SelectionSnapshot,
        mode: TriggerMode,
        isPaused: Bool
    ) -> TriggerDecision {
        guard !isPaused else { return .none }

        let text = snapshot.normalizedText
        guard !text.isEmpty,
              text.count <= maximumAutomaticSelectionLength,
              text.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) else {
            return .none
        }

        switch mode {
        case .disabled, .manualOnly:
            return .none
        case .alwaysFull:
            return .full
        case .hintOnly:
            return .hint
        case .smart:
            switch snapshot.surfaceKind {
            case .readOnly:
                return .full
            case .editable, .unknown:
                return .hint
            }
        }
    }
}

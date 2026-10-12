import Foundation

public enum PauseScope: Equatable, Sendable {
    case global
    case application(String)

    fileprivate var storageKey: String {
        switch self {
        case .global:
            return "pause.global"
        case .application(let bundleID):
            return "pause.application.\(bundleID)"
        }
    }
}

public struct PauseStatus: Equatable, Sendable {
    public let scope: PauseScope
    public let pausedUntil: Date

    public init(scope: PauseScope, pausedUntil: Date) {
        self.scope = scope
        self.pausedUntil = pausedUntil
    }
}

public protocol PauseStore: AnyObject {
    func date(forKey key: String) -> Date?
    func setDate(_ date: Date?, forKey key: String)
}

public final class UserDefaultsPauseStore: PauseStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func date(forKey key: String) -> Date? {
        defaults.object(forKey: key) as? Date
    }

    public func setDate(_ date: Date?, forKey key: String) {
        if let date {
            defaults.set(date, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

public final class PauseManager {
    private let store: PauseStore
    private let now: () -> Date

    public init(
        store: PauseStore = UserDefaultsPauseStore(),
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.now = now
    }

    @discardableResult
    public func pause(_ scope: PauseScope, for duration: TimeInterval) -> PauseStatus {
        let until = now().addingTimeInterval(max(0, duration))
        store.setDate(until, forKey: scope.storageKey)
        return PauseStatus(scope: scope, pausedUntil: until)
    }

    public func resume(_ scope: PauseScope) {
        store.setDate(nil, forKey: scope.storageKey)
    }

    public func activePause(forApplicationID applicationID: String?) -> PauseStatus? {
        if let global = activePause(for: .global) {
            return global
        }

        guard let applicationID else { return nil }
        return activePause(for: .application(applicationID))
    }

    public func activePause(for scope: PauseScope) -> PauseStatus? {
        guard let until = store.date(forKey: scope.storageKey) else {
            return nil
        }

        guard until > now() else {
            store.setDate(nil, forKey: scope.storageKey)
            return nil
        }

        return PauseStatus(scope: scope, pausedUntil: until)
    }

    public func remainingTime(for scope: PauseScope) -> TimeInterval? {
        activePause(for: scope).map { $0.pausedUntil.timeIntervalSince(now()) }
    }
}

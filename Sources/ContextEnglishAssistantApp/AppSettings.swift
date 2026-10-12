import Foundation

final class AppSettings {
    private enum Key {
        static let directDisplayEnabled = "trigger.directDisplayEnabled"
        static let contextualTranslationEndpoint = "translation.endpoint"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var directDisplayEnabled: Bool {
        get { defaults.bool(forKey: Key.directDisplayEnabled) }
        set { defaults.set(newValue, forKey: Key.directDisplayEnabled) }
    }

    var contextualTranslationEndpoint: URL? {
        get {
            guard let value = defaults.string(forKey: Key.contextualTranslationEndpoint),
                  !value.isEmpty else { return nil }
            return URL(string: value)
        }
        set {
            if let newValue {
                defaults.set(newValue.absoluteString, forKey: Key.contextualTranslationEndpoint)
            } else {
                defaults.removeObject(forKey: Key.contextualTranslationEndpoint)
            }
        }
    }
}

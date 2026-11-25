import Foundation

/// Persists user-configured default startup characters (multi-select up to 4 characters)
/// and default startup scale across app launches via `UserDefaults`.
public final class UserPreferencesStore {
    public static let shared = UserPreferencesStore()

    private let startupCharactersKey = "ChiikawaDesktop.DefaultStartupCharacters"
    private let startupScaleKey = "ChiikawaDesktop.DefaultStartupScale"

    private init() {}

    /// Returns the list of character IDs to summon automatically at app launch.
    /// Falls back to `spec.populationLimits.initialSpawnCharacters` (e.g. `["hachiware"]`) if not customized yet.
    public func defaultStartupCharacters(fallback: [String]) -> [String] {
        if let saved = UserDefaults.standard.stringArray(forKey: startupCharactersKey), !saved.isEmpty {
            return saved
        }
        return fallback
    }

    public func isStartupCharacterSelected(id: String, fallback: [String]) -> Bool {
        return defaultStartupCharacters(fallback: fallback).contains(id)
    }

    /// Toggles a character ID in the default startup list (ensuring at least 1 character remains selected).
    public func toggleStartupCharacter(id: String, fallback: [String], orderedValidIDs: [String]) {
        var current = Set(defaultStartupCharacters(fallback: fallback))
        if current.contains(id) {
            if current.count > 1 {
                current.remove(id)
            }
        } else {
            current.insert(id)
        }
        let ordered = orderedValidIDs.filter { current.contains($0) }
        UserDefaults.standard.set(ordered, forKey: startupCharactersKey)
    }

    /// Returns the user's configured default startup scale, falling back to `spec.characterDimensions.scaleRange.default`.
    public func defaultStartupScale(fallback: Double) -> Double {
        if UserDefaults.standard.object(forKey: startupScaleKey) != nil {
            let val = UserDefaults.standard.double(forKey: startupScaleKey)
            if val > 0.1 { return val }
        }
        return fallback
    }

    public func setDefaultStartupScale(_ scale: Double) {
        UserDefaults.standard.set(scale, forKey: startupScaleKey)
    }
}

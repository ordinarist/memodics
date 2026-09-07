import Foundation
import Combine
import MemodicsCore

/// User-facing settings, persisted locally in `UserDefaults`. SPEC §23.
///
/// Deliberately minimal: detection on/off, provider configuration, max
/// selection size, and launch-at-login. No accounts, telemetry, or sync.
final class SettingsStore: ObservableObject {

    private enum Keys {
        static let detectionEnabled = "detectionEnabled"
        static let apiKey = "apiKey" // legacy UserDefaults key, migrated to Keychain
        static let model = "model"
        static let endpoint = "endpoint"
        static let targetLanguage = "targetLanguage"
        static let maxCharacters = "maxCharacters"
        static let launchAtLogin = "launchAtLogin"
    }

    static let defaultEndpoint = "https://api.openai.com/v1/chat/completions"

    private let defaults: UserDefaults

    private static let apiKeyAccount = "translationApiKey"

    @Published var detectionEnabled: Bool { didSet { defaults.set(detectionEnabled, forKey: Keys.detectionEnabled) } }
    /// Stored in the Keychain, never in UserDefaults (SPEC §22).
    @Published var apiKey: String { didSet { KeychainStore.set(apiKey, account: Self.apiKeyAccount) } }
    @Published var model: String { didSet { defaults.set(model, forKey: Keys.model) } }
    @Published var endpoint: String { didSet { defaults.set(endpoint, forKey: Keys.endpoint) } }
    @Published var targetLanguage: String { didSet { defaults.set(targetLanguage, forKey: Keys.targetLanguage) } }
    @Published var maxCharacters: Int { didSet { defaults.set(maxCharacters, forKey: Keys.maxCharacters) } }
    @Published var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.detectionEnabled = defaults.object(forKey: Keys.detectionEnabled) as? Bool ?? true

        // Migrate any legacy plaintext key out of UserDefaults into the Keychain.
        if let legacy = defaults.string(forKey: Keys.apiKey), !legacy.isEmpty {
            KeychainStore.set(legacy, account: Self.apiKeyAccount)
            defaults.removeObject(forKey: Keys.apiKey)
        }
        self.apiKey = KeychainStore.get(account: Self.apiKeyAccount) ?? ""

        self.model = defaults.string(forKey: Keys.model) ?? "gpt-4o-mini"
        self.endpoint = defaults.string(forKey: Keys.endpoint) ?? SettingsStore.defaultEndpoint
        self.targetLanguage = defaults.string(forKey: Keys.targetLanguage) ?? "Vietnamese"
        self.maxCharacters = defaults.object(forKey: Keys.maxCharacters) as? Int ?? 4000
        self.launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false
    }

    /// Build the provider configuration from current settings.
    func providerConfiguration() -> LLMProviderConfiguration {
        let url = URL(string: endpoint) ?? URL(string: SettingsStore.defaultEndpoint)!
        return LLMProviderConfiguration(apiKey: apiKey, model: model, endpoint: url,
                                        targetLanguage: targetLanguage, maxCharacters: maxCharacters)
    }

    var isProviderConfigured: Bool { !apiKey.isEmpty }
}

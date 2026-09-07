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

    /// True only while `loadSecrets` assigns the Keychain-loaded value, so the
    /// `apiKey` setter skips writing it back to the Keychain.
    private var isLoadingApiKey = false

    @Published var detectionEnabled: Bool { didSet { defaults.set(detectionEnabled, forKey: Keys.detectionEnabled) } }
    /// Stored in the Keychain, never in UserDefaults (SPEC §22). Persistence is
    /// suppressed while `loadSecrets` populates the value from the Keychain, so
    /// loading doesn't write the freshly-read value straight back.
    @Published var apiKey: String {
        didSet {
            guard !isLoadingApiKey else { return }
            KeychainStore.set(apiKey, account: Self.apiKeyAccount)
        }
    }
    @Published var model: String { didSet { defaults.set(model, forKey: Keys.model) } }
    @Published var endpoint: String { didSet { defaults.set(endpoint, forKey: Keys.endpoint) } }
    @Published var targetLanguage: String { didSet { defaults.set(targetLanguage, forKey: Keys.targetLanguage) } }
    @Published var maxCharacters: Int { didSet { defaults.set(maxCharacters, forKey: Keys.maxCharacters) } }
    @Published var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.detectionEnabled = defaults.object(forKey: Keys.detectionEnabled) as? Bool ?? true

        // The Keychain read is deferred to `loadSecrets` (off the main thread):
        // a Keychain access prompt — e.g. after the app is rebuilt/re-signed —
        // must never freeze app launch (SPEC §24).
        self.apiKey = ""

        self.model = defaults.string(forKey: Keys.model) ?? "gpt-4o-mini"
        self.endpoint = defaults.string(forKey: Keys.endpoint) ?? SettingsStore.defaultEndpoint
        self.targetLanguage = defaults.string(forKey: Keys.targetLanguage) ?? "Vietnamese"
        self.maxCharacters = defaults.object(forKey: Keys.maxCharacters) as? Int ?? 4000
        self.launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false
    }

    /// Load the API key from the Keychain off the main thread so a Keychain
    /// access prompt can never block launch, then publish it on the main thread.
    /// `completion` runs on the main thread once the key is available, letting
    /// the caller rebuild anything that depends on it (e.g. the provider).
    func loadSecrets(completion: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            // Migrate any legacy plaintext key out of UserDefaults into the
            // Keychain (kept off the main thread for the same reason).
            if let legacy = self.defaults.string(forKey: Keys.apiKey), !legacy.isEmpty {
                KeychainStore.set(legacy, account: Self.apiKeyAccount)
                self.defaults.removeObject(forKey: Keys.apiKey)
            }
            let stored = KeychainStore.get(account: Self.apiKeyAccount) ?? ""

            DispatchQueue.main.async {
                self.isLoadingApiKey = true
                self.apiKey = stored
                self.isLoadingApiKey = false
                completion()
            }
        }
    }

    /// Build the provider configuration from current settings.
    func providerConfiguration() -> LLMProviderConfiguration {
        let url = URL(string: endpoint) ?? URL(string: SettingsStore.defaultEndpoint)!
        return LLMProviderConfiguration(apiKey: apiKey, model: model, endpoint: url,
                                        targetLanguage: targetLanguage, maxCharacters: maxCharacters)
    }

    var isProviderConfigured: Bool { !apiKey.isEmpty }
}

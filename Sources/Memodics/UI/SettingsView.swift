import SwiftUI
import MemodicsCore

/// Minimal settings. SPEC §23: enable/disable detection, provider config, max
/// selection size, launch at login. Nothing more.
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    var onProviderChanged: () -> Void
    var accessibilityTrusted: Bool
    var onOpenAccessibility: () -> Void

    var body: some View {
        Form {
            Section("Detection") {
                Toggle("Enable translation detection", isOn: $settings.detectionEnabled)
                if !accessibilityTrusted {
                    HStack {
                        Label("Accessibility permission not granted", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Open Settings…", action: onOpenAccessibility)
                    }
                }
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }

            Section("Translation provider") {
                SecureField("API key", text: $settings.apiKey)
                    .onChange(of: settings.apiKey) { _, _ in onProviderChanged() }
                TextField("Model", text: $settings.model)
                    .onChange(of: settings.model) { _, _ in onProviderChanged() }
                TextField("Endpoint", text: $settings.endpoint)
                    .onChange(of: settings.endpoint) { _, _ in onProviderChanged() }
                TextField("Target language", text: $settings.targetLanguage)
                    .onChange(of: settings.targetLanguage) { _, _ in onProviderChanged() }
                Text("An OpenAI-compatible chat-completions endpoint. Stored locally only.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Cost control") {
                Stepper(value: $settings.maxCharacters, in: 100...20000, step: 100) {
                    Text("Max selection size: \(settings.maxCharacters) characters")
                }
                .onChange(of: settings.maxCharacters) { _, _ in onProviderChanged() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 420)
    }
}

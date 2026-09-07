import Foundation

/// Errors surfaced by translation providers. SPEC §24.
public enum TranslationProviderError: Error, Equatable, CustomStringConvertible {
    case notConfigured
    case requestFailed(String)
    case malformedResponse(String)

    public var description: String {
        switch self {
        case .notConfigured: return "Translation provider is not configured."
        case .requestFailed(let m): return "Translation request failed: \(m)"
        case .malformedResponse(let m): return "Malformed translation response: \(m)"
        }
    }
}

/// The single abstraction all translation/analysis flows through. SPEC §8.
///
/// The concrete provider (LLM, cloud API, local model) is isolated behind this
/// protocol so the app is never hard-coded to one vendor, and so tests can use
/// a mock. `knownVocabulary` lets the provider skip re-analyzing already-known
/// words to control cost (SPEC §21).
public protocol TranslationProvider: Sendable {
    func analyze(text: String, knownVocabulary: [VocabularyItem]) async throws -> TranslationResult
}

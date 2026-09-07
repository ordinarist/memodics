import Foundation

/// Decides whether an extracted selection is worth processing. SPEC §7.
///
/// Rejects empty/whitespace-only, punctuation-only, and over-length selections.
/// Accepts anything from a single word up to a paragraph. The maximum is an
/// explicit, configurable cost guard (SPEC §7) — not an arbitrary small limit.
public struct TextQualifier {

    public let maxCharacters: Int

    public init(maxCharacters: Int = 4000) {
        self.maxCharacters = maxCharacters
    }

    public func isProcessable(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard trimmed.count <= maxCharacters else { return false }
        // Must contain at least one letter — filters punctuation/symbol-only and
        // most binary/non-text clipboard content.
        return trimmed.unicodeScalars.contains { CharacterSet.letters.contains($0) }
    }
}

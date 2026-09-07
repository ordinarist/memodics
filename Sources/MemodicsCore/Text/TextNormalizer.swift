import Foundation

/// Normalizes selected text so that trivially-different selections resolve to
/// the same canonical form (and therefore the same cache key). SPEC §15.
///
/// Normalization rules:
/// 1. Apply Unicode canonical composition (NFC).
/// 2. Trim leading/trailing whitespace and newlines.
/// 3. Collapse any run of Unicode whitespace (spaces, tabs, newlines) to a
///    single ASCII space.
public enum TextNormalizer {

    public static func normalize(_ text: String) -> String {
        // NFC first so combining marks fold into precomposed characters before
        // we do any whitespace work.
        let composed = text.precomposedStringWithCanonicalMapping

        // Split on any Unicode whitespace/newline, drop empties, rejoin with a
        // single space. This simultaneously trims the ends and collapses
        // internal runs.
        let pieces = composed.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        return pieces.joined(separator: " ")
    }
}

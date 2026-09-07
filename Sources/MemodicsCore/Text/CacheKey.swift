import Foundation
import CryptoKit

/// Deterministic cache-key generation for translated sentences. SPEC §15.
///
/// The key is the SHA-256 hash (lowercase hex) of the *normalized* text, so
/// that whitespace/Unicode-equivalent selections share a single cache entry.
public enum CacheKey {

    /// Normalize `rawText` then hash it. This is the key used by the sentence
    /// cache for an arbitrary user selection.
    public static func make(fromRawText rawText: String) -> String {
        hash(ofNormalizedText: TextNormalizer.normalize(rawText))
    }

    /// Hash already-normalized text. Exposed separately so callers that have
    /// already normalized (and stored) the text don't normalize twice.
    public static func hash(ofNormalizedText text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

import Foundation

/// Mastery-based overall English-level estimate. SPEC §16 (design doc
/// 2026-09-12). CEFR mastery is cumulative: your level is the highest band
/// where you have mastered (marked "understood") enough words AND every lower
/// band also clears its threshold.
public struct EnglishLevelEstimate: Equatable, Sendable {
    public enum Confidence: String, Sendable, Equatable { case low, medium, high }
    /// nil = not enough data yet.
    public let level: CEFRLevel?
    /// Understood counts per band (passthrough of the estimator input).
    public let distribution: [CEFRLevel: Int]
    public let confidence: Confidence
}

public enum EnglishLevelEstimator {
    /// Understood-word count required to "clear" each band. Higher bands taper
    /// because fewer distinct high-level words are encountered in practice.
    /// Single source of truth — tune here.
    static let thresholds: [CEFRLevel: Int] = [
        .a1: 20, .a2: 40, .b1: 60, .b2: 80, .c1: 60, .c2: 40,
    ]

    public static func estimate(understoodByLevel: [CEFRLevel: Int]) -> EnglishLevelEstimate {
        var level: CEFRLevel?
        for band in CEFRLevel.allCases {
            let count = understoodByLevel[band] ?? 0
            let threshold = thresholds[band] ?? .max
            if count >= threshold {
                level = band
            } else {
                break   // monotonic: a gap caps the level here
            }
        }
        let total = understoodByLevel.values.reduce(0, +)
        let confidence: EnglishLevelEstimate.Confidence =
            total < 50 ? .low : (total < 200 ? .medium : .high)
        return EnglishLevelEstimate(level: level, distribution: understoodByLevel,
                                    confidence: confidence)
    }
}

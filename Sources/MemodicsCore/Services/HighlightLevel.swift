import Foundation

/// Maps lookup frequency to a bounded highlight intensity level. SPEC §13.
///
/// The scale is deliberately bucketed (not linear) so 20 lookups is not "20×"
/// stronger than 1. Understood vocabulary is never highlighted (level 0).
public enum HighlightLevel {

    /// Number of distinct non-zero intensity levels.
    public static let maxLevel = 6

    /// Bucketed level for a raw lookup count:
    /// 0 → 0, 1 → 1, 2–3 → 2, 4–7 → 3, 8–15 → 4, 16–31 → 5, 32+ → 6.
    public static func level(forLookupCount count: Int) -> Int {
        switch count {
        case ..<1: return 0
        case 1: return 1
        case 2...3: return 2
        case 4...7: return 3
        case 8...15: return 4
        case 16...31: return 5
        default: return 6
        }
    }

    /// Level for a vocabulary item, honoring its learning state. SPEC §11, §13.
    public static func level(for item: VocabularyItem) -> Int {
        guard item.status == .learning else { return 0 }
        return level(forLookupCount: item.lookupCount)
    }
}

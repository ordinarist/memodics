import Foundation

/// Serializes analyzed vocabulary to/from the JSON stored in the sentence
/// cache's `analysis_json` column (SPEC §15), so a cache hit reconstructs the
/// exact vocabulary set without another API call (SPEC §20, §21).
public enum AnalysisCodec {

    public static func encode(_ vocabulary: [AnalyzedVocabulary]) -> String {
        guard let data = try? JSONEncoder().encode(vocabulary),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    public static func decode(_ json: String) -> [AnalyzedVocabulary] {
        guard let data = json.data(using: .utf8),
              let vocab = try? JSONDecoder().decode([AnalyzedVocabulary].self, from: data) else {
            return []
        }
        return vocab
    }
}

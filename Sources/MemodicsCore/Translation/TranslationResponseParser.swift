import Foundation

/// Parses a provider's JSON payload into a `TranslationResult`. SPEC §9, §24.
///
/// Kept separate from any network code so it is fully unit-testable and so the
/// same parsing tolerates responses from different providers (including LLMs
/// that wrap JSON in prose or markdown fences).
public enum TranslationResponseParser {

    private struct DTO: Decodable {
        let translation: String
        let vocabulary: [VocabDTO]?
    }

    private struct VocabDTO: Decodable {
        let surfaceForm: String?
        let lemma: String?
        let meaning: String?
        let type: String?
        let partOfSpeech: String?
    }

    /// Parse a raw JSON object.
    public static func parse(_ data: Data) throws -> TranslationResult {
        let dto: DTO
        do {
            dto = try JSONDecoder().decode(DTO.self, from: data)
        } catch {
            throw TranslationProviderError.malformedResponse("could not decode JSON: \(error)")
        }
        let vocab = (dto.vocabulary ?? []).compactMap { item -> AnalyzedVocabulary? in
            // A vocab entry needs at least a surface form and lemma to be useful.
            let surface = item.surfaceForm ?? item.lemma
            let lemma = item.lemma ?? item.surfaceForm
            guard let surface, let lemma else { return nil }
            let type = item.type.flatMap(VocabularyType.init(rawValue:)) ?? .word
            return AnalyzedVocabulary(surfaceForm: surface, lemma: lemma,
                                      meaning: item.meaning ?? "", type: type,
                                      partOfSpeech: item.partOfSpeech)
        }
        return TranslationResult(translation: dto.translation, vocabulary: vocab)
    }

    /// Parse text that may contain a JSON object embedded in prose or a
    /// markdown code fence, extracting the first balanced `{ … }` block.
    public static func parse(fromText text: String) throws -> TranslationResult {
        guard let json = extractFirstJSONObject(from: text) else {
            throw TranslationProviderError.malformedResponse("no JSON object found in response")
        }
        return try parse(Data(json.utf8))
    }

    /// Extract the first balanced top-level `{ … }` substring, respecting
    /// string literals so braces inside strings don't unbalance the scan.
    static func extractFirstJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < text.endIndex {
            let ch = text[index]
            if inString {
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == "\"" { inString = false }
            } else {
                switch ch {
                case "\"": inString = true
                case "{": depth += 1
                case "}":
                    depth -= 1
                    if depth == 0 { return String(text[start...index]) }
                default: break
                }
            }
            index = text.index(after: index)
        }
        return nil
    }
}

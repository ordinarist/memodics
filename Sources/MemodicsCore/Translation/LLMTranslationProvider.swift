import Foundation

/// Configuration for an OpenAI-compatible chat-completions translation provider.
///
/// Kept provider-agnostic: any endpoint that accepts the OpenAI chat schema and
/// returns `choices[].message.content` works (OpenAI, local llama.cpp servers,
/// etc.). The API key is supplied by the user in Settings (SPEC §23) and stored
/// locally only.
public struct LLMProviderConfiguration: Sendable, Equatable {
    public var apiKey: String
    public var model: String
    public var endpoint: URL
    public var targetLanguage: String
    /// Explicit, configurable cap to protect API cost (SPEC §7).
    public var maxCharacters: Int

    public init(apiKey: String, model: String, endpoint: URL,
                targetLanguage: String, maxCharacters: Int = 4000) {
        self.apiKey = apiKey
        self.model = model
        self.endpoint = endpoint
        self.targetLanguage = targetLanguage
        self.maxCharacters = maxCharacters
    }

    public var isConfigured: Bool { !apiKey.isEmpty }
}

/// Concrete translation provider that calls an LLM chat endpoint and expects a
/// strict-JSON response. Fully isolated behind `TranslationProvider` (SPEC §8)
/// and testable via an injected `HTTPTransport` (SPEC §26).
public final class LLMTranslationProvider: TranslationProvider, @unchecked Sendable {

    private let configuration: LLMProviderConfiguration
    private let transport: HTTPTransport

    public init(configuration: LLMProviderConfiguration, transport: HTTPTransport = URLSessionTransport()) {
        self.configuration = configuration
        self.transport = transport
    }

    public func analyze(text: String, knownVocabulary: [VocabularyItem]) async throws -> TranslationResult {
        guard configuration.isConfigured else { throw TranslationProviderError.notConfigured }

        let clipped = String(text.prefix(configuration.maxCharacters))
        let request = try buildRequest(text: clipped, knownVocabulary: knownVocabulary)

        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await transport.send(request)
        } catch {
            throw TranslationProviderError.requestFailed(String(describing: error))
        }
        guard (200..<300).contains(response.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw TranslationProviderError.requestFailed("HTTP \(response.statusCode): \(body)")
        }

        let content = try extractAssistantContent(data)
        return try TranslationResponseParser.parse(fromText: content)
    }

    // MARK: - Request

    private func buildRequest(text: String, knownVocabulary: [VocabularyItem]) throws -> URLRequest {
        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")

        // Already-understood/known lemmas so the model need not re-analyze them (SPEC §21).
        let known = knownVocabulary.map { $0.lemma }.sorted()

        let payload: [String: Any] = [
            "model": configuration.model,
            "temperature": 0.2,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": Self.makeSystemPrompt(
                    targetLanguage: configuration.targetLanguage, knownLemmas: known)],
                ["role": "user", "content": text],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }

    /// Builds the system prompt. `static` + `internal` so it is unit-testable
    /// without a live endpoint.
    static func makeSystemPrompt(targetLanguage: String, knownLemmas: [String]) -> String {
        let knownClause = knownLemmas.isEmpty
            ? ""
            : " Do NOT include these already-known lemmas in the vocabulary array: \(knownLemmas.joined(separator: ", "))."
        return """
        You are a reading assistant for an English learner whose target language is \(targetLanguage).
        Translate the user's English text into \(targetLanguage), then identify vocabulary worth learning.
        Prefer genuine dictionary entries. DO NOT include proper nouns, personal/place/brand names, \
        pure numbers, code identifiers, file paths, or URLs, and skip elementary function words \
        (articles, basic pronouns, simple prepositions).
        DO include conjunctions and discourse connectives worth learning (e.g. "nevertheless", "whereas", \
        "albeit") using type "conjunction".
        Treat phrasal verbs, idioms, and meaningful multi-word expressions as single units — do not split them.
        Use the surrounding context to choose the correct contextual meaning and CEFR level of each item.
        Respond with a single JSON object ONLY, matching exactly:
        {"translation": string, "vocabulary": [{"surfaceForm": string, "lemma": string, "meaning": string (in \(targetLanguage)), "type": one of "word"|"phrase"|"phrasal_verb"|"idiom"|"collocation"|"conjunction", "cefr": one of "A1"|"A2"|"B1"|"B2"|"C1"|"C2", "partOfSpeech": string}]}
        The lemma must be the canonical dictionary form so inflected forms map together.\(knownClause)
        """
    }

    // MARK: - Response

    private struct ChatResponse: Decodable {
        struct Choice: Decodable { struct Message: Decodable { let content: String }; let message: Message }
        let choices: [Choice]
    }

    private func extractAssistantContent(_ data: Data) throws -> String {
        do {
            let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
            guard let content = decoded.choices.first?.message.content else {
                throw TranslationProviderError.malformedResponse("no choices in response")
            }
            return content
        } catch let error as TranslationProviderError {
            throw error
        } catch {
            throw TranslationProviderError.malformedResponse("unexpected chat response shape: \(error)")
        }
    }
}

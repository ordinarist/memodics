import XCTest
@testable import MemodicsCore

/// A fake transport so the provider's request-building and response-decoding
/// are testable without a network. SPEC §26 — the provider must be mockable.
final class FakeHTTPTransport: HTTPTransport, @unchecked Sendable {
    var responseBody: Data
    var statusCode: Int
    private(set) var lastRequest: URLRequest?

    init(responseBody: Data, statusCode: Int = 200) {
        self.responseBody = responseBody
        self.statusCode = statusCode
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        let resp = HTTPURLResponse(url: request.url!, statusCode: statusCode,
                                   httpVersion: nil, headerFields: nil)!
        return (responseBody, resp)
    }
}

final class LLMTranslationProviderTests: XCTestCase {

    private func openAIStyleResponse(content: String) -> Data {
        let escaped = content.replacingOccurrences(of: "\"", with: "\\\"")
                             .replacingOccurrences(of: "\n", with: "\\n")
        return Data("""
        { "choices": [ { "message": { "role": "assistant", "content": "\(escaped)" } } ] }
        """.utf8)
    }

    func testParsesModelJSONFromChatResponse() async throws {
        let content = #"{ "translation": "xin chào thế giới", "vocabulary": [ { "surfaceForm": "world", "lemma": "world", "meaning": "thế giới", "type": "word" } ] }"#
        let transport = FakeHTTPTransport(responseBody: openAIStyleResponse(content: content))
        let config = LLMProviderConfiguration(apiKey: "sk-test", model: "gpt-x",
                                              endpoint: URL(string: "https://example.com/v1/chat/completions")!,
                                              targetLanguage: "Vietnamese")
        let provider = LLMTranslationProvider(configuration: config, transport: transport)

        let result = try await provider.analyze(text: "hello world", knownVocabulary: [])
        XCTAssertEqual(result.translation, "xin chào thế giới")
        XCTAssertEqual(result.vocabulary.first?.lemma, "world")

        // Request was authenticated and carried the source text.
        let body = String(data: transport.lastRequest!.httpBody!, encoding: .utf8)!
        XCTAssertTrue(body.contains("hello world"))
        XCTAssertEqual(transport.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
    }

    func testUnconfiguredProviderThrows() async {
        let config = LLMProviderConfiguration(apiKey: "", model: "m",
                                              endpoint: URL(string: "https://example.com")!,
                                              targetLanguage: "Vietnamese")
        let provider = LLMTranslationProvider(configuration: config, transport: FakeHTTPTransport(responseBody: Data()))
        do {
            _ = try await provider.analyze(text: "x", knownVocabulary: [])
            XCTFail("expected notConfigured")
        } catch let error as TranslationProviderError {
            XCTAssertEqual(error, .notConfigured)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testHTTPErrorStatusThrowsRequestFailed() async {
        let transport = FakeHTTPTransport(responseBody: Data("server error".utf8), statusCode: 500)
        let config = LLMProviderConfiguration(apiKey: "sk", model: "m",
                                              endpoint: URL(string: "https://example.com")!,
                                              targetLanguage: "Vietnamese")
        let provider = LLMTranslationProvider(configuration: config, transport: transport)
        do {
            _ = try await provider.analyze(text: "x", knownVocabulary: [])
            XCTFail("expected requestFailed")
        } catch let error as TranslationProviderError {
            if case .requestFailed = error {} else { XCTFail("wrong error: \(error)") }
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }
}

import Foundation

/// Minimal HTTP abstraction so network-backed providers can be tested with a
/// fake transport (SPEC §26 — provider must be mockable).
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Production transport backed by `URLSession`.
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TranslationProviderError.requestFailed("non-HTTP response")
        }
        return (data, http)
    }
}

import Foundation

/// The optional bridge to the enrichment proxy.
///
/// Three properties this type must never lose:
///   1. **It cannot block.** Every caller already has an on-device result in
///      hand before this is invoked. This only ever offers an upgrade.
///   2. **It fails silently.** A timeout, a 503, a captive-portal login page,
///      airplane mode -- all of them mean "use what you already have". The user
///      is never shown an error, because from their side nothing went wrong.
///   3. **It is off unless asked for.** Default disabled, explicit opt-in.
actor EnrichmentClient {

    enum Failure: Error {
        case disabled
        case notConfigured
        case transport
        case badStatus(Int)
        case undecodable
    }

    /// Deployed proxy. Overridden in Settings for local development.
    static let defaultEndpoint = "https://moth-enrichment.onrender.com"

    private let endpoint: URL?
    private let session: URLSession

    init(endpoint: String = EnrichmentClient.defaultEndpoint) {
        self.endpoint = URL(string: endpoint)

        let config = URLSessionConfiguration.ephemeral
        // Short and hard. The bedtime screen reveals itself over about three
        // seconds, so anything that lands after that has missed its window and
        // swapping the text under the reader would be worse than not trying.
        config.timeoutIntervalForRequest = 3.0
        config.timeoutIntervalForResource = 4.0
        // Nothing about this request should ever touch a cache on disk.
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        self.session = URLSession(configuration: config)
    }

    /// Asks the proxy to write the bedtime summary.
    ///
    /// The returned candidate is *not* trusted -- the caller must still put it
    /// through `Harness.validate` before it reaches a screen. This method's
    /// only job is transport.
    func summary(for request: EnrichmentRequest) async throws -> SummaryCandidate {
        try await post(request, as: SummaryCandidate.self)
    }

    func task(for request: EnrichmentRequest) async throws -> TaskCandidate {
        try await post(request, as: TaskCandidate.self)
    }

    private func post<T: Decodable>(_ body: EnrichmentRequest, as: T.Type) async throws -> T {
        guard let endpoint else { throw Failure.notConfigured }

        var urlRequest = URLRequest(url: endpoint.appendingPathComponent("v1/enrich"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw Failure.transport
        }

        guard let http = response as? HTTPURLResponse else { throw Failure.transport }
        guard (200..<300).contains(http.statusCode) else {
            throw Failure.badStatus(http.statusCode)
        }
        guard let decoded = try? JSONDecoder().decode(T.self, from: data) else {
            throw Failure.undecodable
        }
        return decoded
    }
}

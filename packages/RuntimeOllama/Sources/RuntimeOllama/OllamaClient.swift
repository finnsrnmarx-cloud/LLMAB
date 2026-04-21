import Foundation
import LLMCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Thin URLSession wrapper for the Ollama HTTP API. Public only to the module;
/// `OllamaRuntime` is the `LLMRuntime` façade.
///
/// Marked `@unchecked Sendable` because URLSession is not officially Sendable
/// under Swift 5.x but is thread-safe in practice.
final class OllamaClient: @unchecked Sendable {

    let endpoint: URL
    let session: URLSession

    init(endpoint: URL = RuntimeOllama.defaultEndpoint,
         session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    // MARK: - GET /api/tags

    func listTags() async throws -> OllamaDTO.TagsResponse {
        try await getJSON(path: "/api/tags")
    }

    // MARK: - GET /api/ps

    func listLoaded() async throws -> OllamaDTO.PSResponse {
        try await getJSON(path: "/api/ps")
    }

    // MARK: - POST /api/chat  (streaming NDJSON)

    func streamChat(_ body: OllamaDTO.ChatRequestBody) -> AsyncThrowingStream<OllamaDTO.ChatStreamChunk, Error> {
        streamJSONLines(path: "/api/chat", body: body)
    }

    // MARK: - POST /api/pull  (streaming NDJSON)

    func streamPull(_ body: OllamaDTO.PullRequestBody) -> AsyncThrowingStream<OllamaDTO.PullStreamChunk, Error> {
        streamJSONLines(path: "/api/pull", body: body)
    }

    // MARK: - GET probe

    /// Cheap HEAD-equivalent: hit /api/version with a short timeout.
    func isReachable() async -> Bool {
        var req = URLRequest(url: endpoint.appendingPathComponent("/api/version"))
        req.httpMethod = "GET"
        req.timeoutInterval = 1.5
        do {
            let (_, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }

    // MARK: - Internals

    private func getJSON<T: Decodable>(path: String) async throws -> T {
        var req = URLRequest(url: endpoint.appendingPathComponent(path))
        req.httpMethod = "GET"
        let (data, resp) = try await session.data(for: req)
        try Self.assertOK(resp, data: data)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw LLMRuntimeError.decoding(error)
        }
    }

    private func streamJSONLines<Body: Encodable, Chunk: Decodable>(
        path: String,
        body: Body
    ) -> AsyncThrowingStream<Chunk, Error> {
        AsyncThrowingStream<Chunk, Error> { continuation in
            let task = Task {
                do {
                    var req = URLRequest(url: self.endpoint.appendingPathComponent(path))
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = try JSONEncoder().encode(body)

                    let (bytes, resp) = try await self.session.bytes(for: req)
                    guard let http = resp as? HTTPURLResponse else {
                        throw LLMRuntimeError.badResponse("no HTTPURLResponse")
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        // Drain body for diagnostic purposes.
                        var collected = Data()
                        for try await b in bytes { collected.append(b) }
                        let bodyStr = String(data: collected, encoding: .utf8) ?? "<binary>"
                        throw LLMRuntimeError.http(status: http.statusCode, body: bodyStr)
                    }

                    let decoder = JSONDecoder()
                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            continuation.finish(throwing: LLMRuntimeError.cancelled)
                            return
                        }
                        guard !line.isEmpty else { continue }
                        guard let data = line.data(using: .utf8) else { continue }
                        do {
                            let chunk = try decoder.decode(Chunk.self, from: data)
                            continuation.yield(chunk)
                        } catch {
                            throw LLMRuntimeError.decoding(error)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func assertOK(_ resp: URLResponse, data: Data) throws {
        guard let http = resp as? HTTPURLResponse else {
            throw LLMRuntimeError.badResponse("no HTTPURLResponse")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            throw LLMRuntimeError.http(status: http.statusCode, body: body)
        }
    }
}

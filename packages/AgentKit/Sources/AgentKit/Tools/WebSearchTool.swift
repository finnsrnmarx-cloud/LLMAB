import Foundation
import LLMCore

/// Best-effort web search via DuckDuckGo's HTML lite endpoint. Opt-in per
/// session — the Agents tab surfaces a "web search" toggle that only
/// includes this tool when the user checks it.
///
/// Returns a plain-text digest of the top results. Not great, but keeps us
/// on first-party sources, with no API key and no third-party AI involved.
public struct WebSearchTool: AgentTool {
    public let id = "web_search"
    public let description = "Search the web (DuckDuckGo) and return the top result titles + snippets + URLs."
    public let requiresConsent = false
    public let parameters = ToolParameterSchema(
        type: "object",
        properties: [
            "query": .init(type: "string", description: "The search query."),
            "max_results": .init(type: "integer",
                                 description: "1–10; default 5.")
        ],
        required: ["query"]
    )

    private struct Args: Decodable {
        let query: String
        let max_results: Int?
    }

    public init() {}

    public func execute(arguments: Data) async throws -> String {
        let args = try JSONDecoder().decode(Args.self, from: arguments)
        let count = max(1, min(10, args.max_results ?? 5))
        let encoded = args.query.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) ?? args.query
        guard let url = URL(string: "https://duckduckgo.com/html/?q=\(encoded)") else {
            return "<invalid query>"
        }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) ω/0.1",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, _) = try await URLSession.shared.data(for: request)
        let html = String(data: data, encoding: .utf8) ?? ""
        return extractResults(from: html, limit: count)
    }

    /// Very small, permissive HTML pattern match — DuckDuckGo's HTML page
    /// is stable enough for this not to need a full parser.
    private func extractResults(from html: String, limit: Int) -> String {
        let pattern = #"<a[^>]+class="result__a"[^>]+href="([^"]+)"[^>]*>([\s\S]*?)</a>[\s\S]*?<a[^>]+class="result__snippet"[^>]*>([\s\S]*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern,
                                                   options: [.caseInsensitive]) else {
            return "<regex failure>"
        }
        let ns = html as NSString
        let range = NSRange(location: 0, length: ns.length)
        let matches = regex.matches(in: html, options: [], range: range).prefix(limit)
        if matches.isEmpty { return "<no results>" }

        var lines: [String] = []
        for m in matches {
            let href = ns.substring(with: m.range(at: 1))
            let title = strip(ns.substring(with: m.range(at: 2)))
            let snippet = strip(ns.substring(with: m.range(at: 3)))
            lines.append("• \(title)\n  \(snippet)\n  \(href)\n")
        }
        return lines.joined(separator: "\n")
    }

    private func strip(_ s: String) -> String {
        // Drop tags + collapse whitespace.
        let noTags = s.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
        return noTags
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

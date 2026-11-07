import Foundation

/// Savedd search engine configuration.
/// URL template confirmed from Savedd web app: https://savedd.com/?q={searchTerms}
struct SaveddSearchEngine {
    static let name = "Savedd"
    static let baseURL = "https://savedd.com"
    static let searchTemplate = "https://savedd.com/?q="

    /// Builds a search URL for the given query.
    static func searchURL(for query: String) -> URL? {
        guard var components = URLComponents(string: baseURL) else { return nil }
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        // Website URLSearchParams treats a literal + as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }

    /// Resolve explicit web addresses; everything else remains a literal search.
    static func destination(for input: String) -> (url: URL, isSearch: Bool)? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let lower = text.lowercased()
        if !text.contains(where: { $0.isWhitespace }),
           lower.hasPrefix("https://") || lower.hasPrefix("http://") || (!text.contains("://") && text.contains(".")) {
            let candidate = lower.hasPrefix("https://") || lower.hasPrefix("http://") ? text : "https://" + text
            if let url = URL(string: candidate), let host = url.host, !host.isEmpty {
                return (url, false)
            }
        }
        return searchURL(for: text).map { ($0, true) }
    }

    /// Home / new-tab URL.
    static var homeURL: URL {
        URL(string: baseURL)! 
    }
}

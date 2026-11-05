import Foundation

/// Savedd search engine configuration.
/// URL template confirmed from Savedd web app: https://savedd.com/?q={searchTerms}
struct SaveddSearchEngine {
    static let name = "Savedd"
    static let baseURL = "https://savedd.com"
    static let searchTemplate = "https://savedd.com/?q="

    /// Builds a search URL for the given query.
    static func searchURL(for query: String) -> URL? {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return URL(string: searchTemplate + encoded)
    }

    /// Home / new-tab URL.
    static var homeURL: URL {
        URL(string: baseURL)! 
    }
}

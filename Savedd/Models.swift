import SwiftUI

enum BrowserNavigationAction: Codable {
    case load(URL)
    case back
    case forward
    case history(offset: Int, url: URL)
}

struct BrowserNavigationRequest: Codable, Identifiable {
    let id: UUID
    let action: BrowserNavigationAction

    init(_ action: BrowserNavigationAction) {
        id = UUID()
        self.action = action
    }
}

struct BrowserTab: Identifiable, Codable {
    var id = UUID()
    var url: URL
    var title: String
    var navigationRequest: BrowserNavigationRequest

    init(url: URL, title: String = "New Tab") {
        self.url = url
        self.title = title
        self.navigationRequest = BrowserNavigationRequest(.load(url))
    }
}

struct Bookmark: Identifiable, Codable {
    var id = UUID()
    var title: String
    var url: URL
    var dateAdded = Date()
}

class BookmarkStore: ObservableObject {
    @Published var bookmarks: [Bookmark] = []
    private let key = "savedd.bookmarks"
    
    init() {
        load()
    }
    
    func add(_ bookmark: Bookmark) {
        bookmarks.insert(bookmark, at: 0)
        save()
    }
    
    func remove(at offsets: IndexSet) {
        bookmarks.remove(atOffsets: offsets)
        save()
    }
    
    func remove(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        save()
    }
    
    private func save() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Bookmark].self, from: data) else { return }
        bookmarks = decoded
    }
}

struct AddressHistoryEntry: Identifiable, Codable {
    var id = UUID()
    let text: String
    let url: URL
    let isSearch: Bool
    var date = Date()
}

/// Only explicit address-bar submissions are saved, not every website visited.
final class AddressHistoryStore: ObservableObject {
    @Published private(set) var entries: [AddressHistoryEntry] = []
    private let defaults: UserDefaults
    private let key = "savedd.address-history.v1"
    static let limit = 100

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([AddressHistoryEntry].self, from: data) {
            entries = Array(decoded.prefix(Self.limit))
        }
    }

    func record(_ text: String, url: URL, isSearch: Bool, privacyMode: Bool) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !privacyMode, !text.isEmpty,
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil else { return }
        entries.removeAll { $0.text.caseInsensitiveCompare(text) == .orderedSame }
        entries.insert(AddressHistoryEntry(text: text, url: url, isSearch: isSearch), at: 0)
        entries = Array(entries.prefix(Self.limit))
        save()
    }

    func matching(_ query: String) -> [AddressHistoryEntry] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? entries : entries.filter {
            $0.text.localizedCaseInsensitiveContains(query) || $0.url.absoluteString.localizedCaseInsensitiveContains(query)
        }
    }

    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func clear() {
        entries = []
        defaults.removeObject(forKey: key)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: key) }
    }
}

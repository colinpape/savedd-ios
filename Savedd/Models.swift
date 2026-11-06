import Foundation

struct BrowserTab: Identifiable, Codable {
    var id = UUID()
    var url: URL
    var title: String
    
    init(url: URL, title: String = "New Tab") {
        self.url = url
        self.title = title
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

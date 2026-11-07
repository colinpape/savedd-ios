import Foundation

@main
struct AddressHistoryTests {
    static func main() throws {
        let suite = "savedd.history-tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AddressHistoryStore(defaults: defaults)

        func submit(_ text: String, privacy: Bool = false) {
            guard let destination = SaveddSearchEngine.destination(for: text) else {
                preconditionFailure("Expected a destination")
            }
            store.record(text, url: destination.url, isSearch: destination.isSearch, privacyMode: privacy)
        }
        submit(" coffee shops ")
        submit("example.com")
        submit("COFFEE SHOPS")
        precondition(store.entries.count == 2, "Repeated terms should move to the top")
        precondition(store.entries[0].text == "COFFEE SHOPS")
        precondition(store.entries[0].isSearch && !store.entries[1].isSearch)
        precondition(store.matching("EXAMPLE").count == 1)
        precondition(store.matching("   ").count == 2)
        precondition(AddressHistoryStore(defaults: defaults).entries.map(\.text) == store.entries.map(\.text),
                     "History must survive a new store instance")

        submit("private search", privacy: true)
        precondition(store.entries.count == 2 && store.matching("private").isEmpty,
                     "Privacy Mode must not persist a submission")
        submit("https://person:password@example.com")
        precondition(store.entries.count == 2, "Do not save credential-bearing URLs")
        store.remove(store.entries[1].id)
        precondition(AddressHistoryStore(defaults: defaults).entries.count == 1)
        store.clear()
        precondition(AddressHistoryStore(defaults: defaults).entries.isEmpty)
        precondition(defaults.data(forKey: "savedd.address-history.v1") == nil)

        for index in 0...AddressHistoryStore.limit { submit("query \(index)") }
        precondition(store.entries.count == AddressHistoryStore.limit)
        precondition(store.entries.first?.text == "query \(AddressHistoryStore.limit)")
        precondition(store.entries.last?.text == "query 1")

        precondition(SaveddSearchEngine.destination(for: " \n ") == nil)
        precondition(SaveddSearchEngine.destination(for: "HTTPS://example.com/path")?.isSearch == false)
        precondition(SaveddSearchEngine.destination(for: "javascript:alert(1)")?.isSearch == true)
        let query = "C++ & coffee #1? café"
        let url = SaveddSearchEngine.searchURL(for: query)!
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        precondition(items.count == 1 && items[0].name == "q" && items[0].value == query)
        precondition(url.absoluteString.contains("C%2B%2B"), "Preserve literal plus signs for the website")
        print("Address history checks passed: persistence, deduplication, deletion, clear, privacy, limit, filtering and URL encoding.")
    }
}

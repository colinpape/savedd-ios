import SwiftUI
import WebKit

struct ContentView: View {
    @StateObject private var bookmarkStore = BookmarkStore()
    @State private var tabs: [BrowserTab] = [BrowserTab(url: SaveddSearchEngine.homeURL)]
    @State private var activeTabIndex = 0
    @State private var searchText = ""
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var showTabs = false
    @State private var showBookmarks = false
    @State private var showShare = false
    @State private var shareItems: [Any] = []
    
    private var activeURL: Binding<URL> {
        Binding(
            get: { tabs[activeTabIndex].url },
            set: { tabs[activeTabIndex].url = $0 }
        )
    }
    
    var body: some View {
        VStack(spacing: 0) {
            WebView(url: activeURL, canGoBack: $canGoBack, canGoForward: $canGoForward)
                .edgesIgnoringSafeArea(.top)
            
            Divider()
            
            // Bottom toolbar
            HStack(spacing: 12) {
                Button(action: goBack) {
                    Image(systemName: "chevron.left")
                }
                .disabled(!canGoBack)
                
                Button(action: goForward) {
                    Image(systemName: "chevron.right")
                }
                .disabled(!canGoForward)
                
                TextField("Search or enter address", text: $searchText, onCommit: performSearch)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                
                Button(action: performSearch) {
                    Image(systemName: "arrow.right.circle.fill")
                }
                
                Button(action: { showTabs = true }) {
                    Image(systemName: "square.on.square")
                }
                
                Button(action: shareCurrentPage) {
                    Image(systemName: "square.and.arrow.up")
                }
                
                Button(action: { showBookmarks = true }) {
                    Image(systemName: "book")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(UIColor.systemBackground))
        }
        .edgesIgnoringSafeArea(.bottom)
        .sheet(isPresented: $showTabs) {
            TabSwitcherView(tabs: $tabs, activeIndex: $activeTabIndex, onNewTab: newTab)
        }
        .sheet(isPresented: $showBookmarks) {
            BookmarksView(store: bookmarkStore) { bookmark in
                loadURL(bookmark.url)
                showBookmarks = false
            }
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(activityItems: shareItems)
        }
        .onChange(of: tabs[activeTabIndex].url) { _ in
            searchText = tabs[activeTabIndex].url.absoluteString
        }
    }
    
    private func performSearch() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        if let url = parseURL(from: trimmed) {
            loadURL(url)
        } else if let searchURL = SaveddSearchEngine.searchURL(for: trimmed) {
            loadURL(searchURL)
        }
    }
    
    private func parseURL(from text: String) -> URL? {
        if text.contains(".") && !text.contains(" ") {
            var urlString = text
            if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
                urlString = "https://" + urlString
            }
            return URL(string: urlString)
        }
        return nil
    }
    
    private func loadURL(_ url: URL) {
        tabs[activeTabIndex].url = url
        searchText = url.absoluteString
    }
    
    private func goBack() {
        // Placeholder — full back/forward needs web view reference; basic version reloads previous if tracked
    }
    
    private func goForward() {
        // Placeholder
    }
    
    private func newTab() {
        let newTab = BrowserTab(url: SaveddSearchEngine.homeURL)
        tabs.append(newTab)
        activeTabIndex = tabs.count - 1
        searchText = ""
    }
    
    private func shareCurrentPage() {
        let url = tabs[activeTabIndex].url
        shareItems = [url]
        showShare = true
    }
}

struct TabSwitcherView: View {
    @Binding var tabs: [BrowserTab]
    @Binding var activeIndex: Int
    var onNewTab: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(tabs.indices, id: \.self) { index in
                    Button {
                        activeIndex = index
                        dismiss()
                    } label: {
                        VStack(alignment: .leading) {
                            Text(tabs[index].title)
                                .font(.headline)
                            Text(tabs[index].url.absoluteString)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            closeTab(at: index)
                        } label: {
                            Label("Close", systemImage: "xmark")
                        }
                    }
                }
            }
            .navigationTitle("Tabs")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        onNewTab()
                        dismiss()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
    
    private func closeTab(at index: Int) {
        guard tabs.count > 1 else { return }
        tabs.remove(at: index)
        if activeIndex >= tabs.count {
            activeIndex = tabs.count - 1
        }
    }
}

struct BookmarksView: View {
    @ObservedObject var store: BookmarkStore
    var onSelect: (Bookmark) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var newTitle = ""
    @State private var newURL = ""
    @State private var showAdd = false
    
    var body: some View {
        NavigationView {
            List {
                ForEach(store.bookmarks) { bookmark in
                    Button {
                        onSelect(bookmark)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(bookmark.title)
                            Text(bookmark.url.absoluteString)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .onDelete(perform: store.remove)
            }
            .navigationTitle("Bookmarks")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                NavigationView {
                    Form {
                        TextField("Title", text: $newTitle)
                        TextField("URL", text: $newURL)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                    .navigationTitle("Add Bookmark")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showAdd = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Add") {
                                addBookmark()
                                showAdd = false
                            }
                            .disabled(newTitle.isEmpty || URL(string: newURL) == nil)
                        }
                    }
                }
            }
        }
    }
    
    private func addBookmark() {
        var urlString = newURL
        if !urlString.hasPrefix("http") {
            urlString = "https://" + urlString
        }
        guard let url = URL(string: urlString) else { return }
        store.add(Bookmark(title: newTitle, url: url))
        newTitle = ""
        newURL = ""
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

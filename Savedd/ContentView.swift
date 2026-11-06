import SwiftUI
import WebKit

struct ContentView: View {
    @EnvironmentObject private var onboarding: OnboardingStore
    @StateObject private var bookmarkStore = BookmarkStore()
    @State private var tabs: [BrowserTab]
    @State private var activeTabIndex = 0
    @State private var searchText = ""
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var backHistory: [HistoryItem] = []
    @State private var forwardHistory: [HistoryItem] = []
    @State private var showTabs = false
    @State private var showBookmarks = false
    @State private var showShare = false
    @State private var showSettings = false
    @State private var shareItems: [Any] = []
    @State private var isEditingAddress = false
    @FocusState private var addressFieldFocused: Bool

    init(initialURL: URL = SaveddSearchEngine.homeURL) {
        _tabs = State(initialValue: [BrowserTab(url: initialURL)])
    }
    
    private var activeURL: Binding<URL> {
        Binding(
            get: { tabs[activeTabIndex].url },
            set: { tabs[activeTabIndex].url = $0 }
        )
    }
    
    private var displayDomain: String {
        let url = tabs[activeTabIndex].url
        return url.host ?? url.absoluteString
    }
    
    var body: some View {
        VStack(spacing: 0) {
            WebView(
                url: activeURL,
                canGoBack: $canGoBack,
                canGoForward: $canGoForward,
                backHistory: $backHistory,
                forwardHistory: $forwardHistory,
                preferences: onboarding.preferences
            )
            .id(onboarding.webRevision)
            .edgesIgnoringSafeArea(.top)
            
            // Safari-style bottom bar
            VStack(spacing: 8) {
                // Rounded address bar
                HStack(spacing: 10) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Settings")
                    
                    ZStack {
                        if isEditingAddress {
                            TextField("Search or enter address", text: $searchText)
                                .focused($addressFieldFocused)
                                .textFieldStyle(.plain)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .font(.system(size: 16))
                                .onSubmit {
                                    performSearch()
                                    isEditingAddress = false
                                    addressFieldFocused = false
                                }
                        } else {
                            Text(displayDomain)
                                .font(.system(size: 16, weight: .medium))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if !isEditingAddress {
                            searchText = tabs[activeTabIndex].url.absoluteString
                            isEditingAddress = true
                            DispatchQueue.main.async {
                                addressFieldFocused = true
                            }
                        }
                    }
                    
                    Button(action: {
                        if isEditingAddress {
                            searchText = ""
                        } else {
                            loadURL(SaveddSearchEngine.homeURL)
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(UIColor.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
                .padding(.horizontal, 12)
                
                // Action buttons
                HStack(spacing: 0) {
                    ToolbarButton(icon: "chevron.left", action: goBack, disabled: !canGoBack)
                        .contextMenu {
                            if backHistory.isEmpty {
                                Text("No back history")
                            } else {
                                ForEach(backHistory) { item in
                                    Button(item.title) {
                                        loadURL(item.url)
                                    }
                                }
                            }
                        }
                    
                    ToolbarButton(icon: "chevron.right", action: goForward, disabled: !canGoForward)
                        .contextMenu {
                            if forwardHistory.isEmpty {
                                Text("No forward history")
                            } else {
                                ForEach(forwardHistory) { item in
                                    Button(item.title) {
                                        loadURL(item.url)
                                    }
                                }
                            }
                        }
                    
                    ToolbarButton(icon: "square.and.arrow.up", action: shareCurrentPage)
                    ToolbarButton(icon: "book", action: { showBookmarks = true })
                    ToolbarButton(icon: "square.on.square", action: { showTabs = true })
                }
                .padding(.horizontal, 4)
            }
            .padding(.vertical, 8)
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
        .sheet(isPresented: $showSettings) {
            SaveddSettingsView()
        }
        .onChange(of: tabs[activeTabIndex].url) { _ in
            if !isEditingAddress {
                searchText = tabs[activeTabIndex].url.absoluteString
            }
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
        isEditingAddress = false
        addressFieldFocused = false
    }
    
    private func goBack() {
        // Single step back — full history is available via long-press menu
        if let first = backHistory.first {
            loadURL(first.url)
        }
    }
    
    private func goForward() {
        if let first = forwardHistory.first {
            loadURL(first.url)
        }
    }
    
    private func newTab() {
        let newTab = BrowserTab(url: SaveddSearchEngine.homeURL)
        tabs.append(newTab)
        activeTabIndex = tabs.count - 1
        searchText = ""
        isEditingAddress = false
        addressFieldFocused = false
    }
    
    private func shareCurrentPage() {
        let url = tabs[activeTabIndex].url
        shareItems = [url]
        showShare = true
    }
}

struct ToolbarButton: View {
    let icon: String
    let action: () -> Void
    var disabled: Bool = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundColor(disabled ? .secondary : .primary)
        }
        .disabled(disabled)
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
            .environmentObject(OnboardingStore())
    }
}

import SwiftUI
import WebKit
import LinkPresentation

struct ContentView: View {
    @EnvironmentObject private var onboarding: OnboardingStore
    @StateObject private var addressHistory = AddressHistoryStore()
    @State private var confirmClearHistory = false
    @StateObject private var bookmarkStore = BookmarkStore()
    @State private var tabs: [BrowserTab]
    @State private var activeTabIndex = 0
    @State private var searchText = ""
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var backHistory: [HistoryItem] = []
    @State private var forwardHistory: [HistoryItem] = []
    @State private var showTabs = false
    @State private var snapshots: [UUID: UIImage] = [:]
    @State private var snapshotRequest = UUID()
    @State private var showBookmarks = false
    @State private var showSettings = false
    @State private var showVoiceSearch = false
    @State private var focusAfterDictation = false
    @State private var sharePage: SharedBrowserPage?
    @State private var isEditingAddress = false
    @FocusState private var addressFieldFocused: Bool

    init(initialURL: URL = SaveddSearchEngine.homeURL) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--share-menu-preview") {
            _tabs = State(initialValue: [BrowserTab(url: SaveddSearchEngine.homeURL, title: "Savedd — Seek, and ye shall find.")])
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--address-editor-preview") {
            _tabs = State(initialValue: [Self.previewTabs()[0]])
            _addressHistory = StateObject(wrappedValue: AddressHistoryStore(defaults: UserDefaults(suiteName: "savedd.address-preview")!))
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--visual-tabs-preview") {
            _tabs = State(initialValue: Self.previewTabs())
            return
        }
        #endif
        _tabs = State(initialValue: [BrowserTab(url: initialURL)])
    }
    
    private var supportsUnderScroll: Bool {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }

    private var displayDomain: String {
        let url = tabs[activeTabIndex].url
        return url.host ?? url.absoluteString
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(tabs) { tab in
                    WebView(
                        url: tabURL(tab.id),
                        canGoBack: activeState($canGoBack, for: tab.id),
                        canGoForward: activeState($canGoForward, for: tab.id),
                        backHistory: activeState($backHistory, for: tab.id),
                        forwardHistory: activeState($forwardHistory, for: tab.id),
                        preferences: onboarding.preferences,
                        topContentInset: supportsUnderScroll ? geometry.safeAreaInsets.top : 0,
                        isActive: tab.id == tabs[activeTabIndex].id,
                        snapshotRequest: snapshotRequest,
                        onPageChanged: { url, title in
                            guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
                            if tabs[index].url != url { snapshots[tab.id] = nil }
                            tabs[index].url = url
                            tabs[index].title = title
                        },
                        onSnapshot: { image in
                            guard tabs.contains(where: { $0.id == tab.id }) else { return }
                            snapshots[tab.id] = image
                        }
                    )
                    .opacity(tab.id == tabs[activeTabIndex].id ? 1 : 0)
                    .allowsHitTesting(tab.id == tabs[activeTabIndex].id)
                    .accessibilityHidden(tab.id != tabs[activeTabIndex].id)
                    .zIndex(tab.id == tabs[activeTabIndex].id ? 1 : 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.container, edges: supportsUnderScroll ? .top : [])
            .overlay(alignment: .top) {
                if supportsUnderScroll {
                    // Scrolling content can pass under this noninteractive status-bar
                    // backdrop. WebKit keeps fixed/sticky controls below this area.
                    Rectangle().fill(.ultraThinMaterial)
                        .frame(height: geometry.safeAreaInsets.top)
                        // This overlay is laid out in the safe container. Move
                        // its backdrop up into the status-bar region itself.
                        .offset(y: -geometry.safeAreaInsets.top)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                if isEditingAddress {
                    recentHistory
                        .frame(height: max(0, min(200, geometry.size.height - 180)))
                        .clipped()
                }
                // Rounded address bar stays in the keyboard-aware safe area.
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
                                .keyboardType(.webSearch)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .font(.system(size: 16))
                                .submitLabel(.go)
                                .accessibilityIdentifier("addressField")
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
                            searchText = SaveddSearchEngine.addressText(for: tabs[activeTabIndex].url)
                            isEditingAddress = true
                            DispatchQueue.main.async {
                                addressFieldFocused = true
                            }
                        }
                    }
                    
                    Button {
                        addressFieldFocused = false
                        showVoiceSearch = true
                    } label: {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(SaveddBrand.gold)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Voice search")
                    .accessibilityHint("Dictate a search or website address")

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
                
                if isEditingAddress {
                    HStack {
                        Button("Cancel") {
                            isEditingAddress = false
                            addressFieldFocused = false
                        }
                        Spacer()
                        Button("Go") { performSearch() }
                            .fontWeight(.semibold)
                            .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal, 24)
                    .frame(minHeight: 36)
                    .tint(SaveddBrand.gold)
                } else {
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
                    ToolbarButton(icon: "square.on.square", action: {
                        addressFieldFocused = false
                        snapshotRequest = UUID()
                        showTabs = true
                    })
                    .accessibilityLabel("Tabs, \(tabs.count) open")
                }
                .padding(.horizontal, 4)
                }
            }
            .padding(.vertical, 8)
            .background {
                Color(UIColor.systemBackground).ignoresSafeArea(.container, edges: .bottom)
            }
            }
        }
        .background {
            // Only the browser background extends behind the status bar and corners.
            Color(UIColor.systemBackground).ignoresSafeArea(.container)
        }
        .confirmationDialog("Clear recent searches and addresses?", isPresented: $confirmClearHistory, titleVisibility: .visible) {
            Button("Clear history", role: .destructive) { addressHistory.clear() }
        } message: {
            Text("This removes the address-bar history saved on this device. Bookmarks and website logins are kept.")
        }
        .sheet(isPresented: $showTabs) {
            TabSwitcherView(tabs: $tabs, activeIndex: $activeTabIndex, snapshots: snapshots, onNewTab: newTab)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showBookmarks) {
            BookmarksView(store: bookmarkStore) { bookmark in
                loadURL(bookmark.url)
                showBookmarks = false
            }
        }
        .sheet(item: $sharePage) { page in
            ShareSheet(page: page, onAddBookmark: bookmarkStore.add)
        }
        .sheet(isPresented: $showVoiceSearch, onDismiss: {
            if focusAfterDictation {
                addressFieldFocused = true
                focusAfterDictation = false
            }
        }) {
            VoiceSearchView(language: onboarding.preferences.language) { text in
                searchText = text
                isEditingAddress = true
                focusAfterDictation = true
                // Leave submission to the user after they review the recognized text.
            }
        }
        .sheet(isPresented: $showSettings) {
            SaveddSettingsView()
        }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--share-menu-preview") {
                try? await Task.sleep(for: .seconds(2))
                shareCurrentPage()
            }
            if ProcessInfo.processInfo.arguments.contains("--address-editor-preview") {
                addressHistory.clear()
                for text in ["https://example.com", "gardening ideas", "local coffee shops"] {
                    if let destination = SaveddSearchEngine.destination(for: text) {
                        addressHistory.record(text, url: destination.url, isSearch: destination.isSearch, privacyMode: false)
                    }
                }
                try? await Task.sleep(for: .seconds(2))
                searchText = ""
                isEditingAddress = true
                addressFieldFocused = true
            }
            if ProcessInfo.processInfo.arguments.contains("--visual-tabs-preview") {
                // Visit real local WebKit pages so CI captures actual snapshots, without network.
                for index in tabs.indices {
                    activeTabIndex = index
                    try? await Task.sleep(for: .seconds(5))
                    snapshotRequest = UUID()
                    try? await Task.sleep(for: .seconds(1))
                }
                try? await Task.sleep(for: .seconds(1))
                activeTabIndex = 1
                snapshotRequest = UUID()
                showTabs = true
            }
            #endif
        }
        .onChange(of: tabs.map(\.id)) {
            snapshots = snapshots.filter { id, _ in tabs.contains(where: { $0.id == id }) }
        }
        .onChange(of: tabs[activeTabIndex].url) {
            if !isEditingAddress {
                searchText = SaveddSearchEngine.addressText(for: tabs[activeTabIndex].url)
            }
        }
    }
    
    private var recentHistory: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Recent searches & addresses").font(.subheadline.weight(.semibold))
                Spacer()
                Button("Clear all") { confirmClearHistory = true }
                    .disabled(addressHistory.entries.isEmpty)
                    .font(.subheadline)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Clear all address-bar history")
            }
            .padding(.horizontal, 16)
            if onboarding.preferences.privacyMode {
                Text("History is paused in Privacy Mode.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let query = searchText == tabs[activeTabIndex].url.absoluteString ? "" : searchText
                let matches = addressHistory.matching(query)
                if matches.isEmpty {
                    Text(addressHistory.entries.isEmpty ? "Your searches and addresses will appear here." : "No matching history")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(matches) { entry in
                                HStack(spacing: 8) {
                                    Button {
                                        searchText = entry.text
                                        performSearch()
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: entry.isSearch ? "magnifyingglass" : "globe")
                                                .foregroundStyle(SaveddBrand.gold)
                                            Text(entry.text).lineLimit(1)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .frame(minHeight: 44)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Open recent: \(entry.text)")
                                    Button {
                                        addressHistory.remove(entry.id)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.caption.weight(.semibold))
                                            .frame(width: 44, height: 44)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Delete history: \(entry.text)")
                                }
                                .padding(.leading, 16)
                                .padding(.trailing, 4)
                            }
                        }
                    }
                    .scrollDismissesKeyboard(.never)
                }
            }
        }
        .tint(SaveddBrand.gold)
        .background(Color(UIColor.secondarySystemBackground))
        .accessibilityIdentifier("addressHistory")
    }

    #if DEBUG
    private static func previewTabs() -> [BrowserTab] {
        let pages = [
            ("Savedd", "#17131f", "#d6af52", "Seek, and ye shall find.", "Search the web"),
            ("Garden Journal", "#eef3e8", "#31543b", "A little room to grow.", "Notes from the garden"),
            ("The Reading Room", "#f6eddf", "#76372d", "Find your next chapter.", "Books for a quiet afternoon")
        ]
        return pages.enumerated().map { index, page in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("tab-preview-safe-area-\(index).html")
            let html = """
            <html><head><meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
            <title>\(page.0)</title><style>
            body{margin:0;background:\(page.1);color:\(page.2);font:20px Georgia;padding:32px}
            header{font:14px sans-serif;letter-spacing:3px;border-bottom:1px solid;padding-bottom:20px}
            h1{font-size:42px;margin-top:70px}section{height:130px;border:1px solid;border-radius:20px;margin:24px 0;opacity:.7}
            </style></head><body><header>\(page.0.uppercased())</header><h1>\(page.3)</h1>
            <button style="position:fixed;top:4px;right:8px;z-index:10;padding:10px;font:16px sans-serif">Sign in</button>
            <p>\(page.4)</p><section></section><section></section></body></html>
            """
            if !FileManager.default.fileExists(atPath: url.path) {
                try? html.write(to: url, atomically: true, encoding: .utf8)
            }
            return BrowserTab(url: url, title: page.0)
        }
    }
    #endif

    // Bind by stable identity: a delayed WebKit callback must never update another tab.
    private func tabURL(_ id: UUID) -> Binding<URL> {
        Binding(
            get: { tabs.first(where: { $0.id == id })?.url ?? SaveddSearchEngine.homeURL },
            set: { url in
                guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
                tabs[index].url = url
            }
        )
    }

    private func activeState<Value>(_ binding: Binding<Value>, for id: UUID) -> Binding<Value> {
        Binding(get: { binding.wrappedValue }, set: { value in
            if tabs[activeTabIndex].id == id { binding.wrappedValue = value }
        })
    }

    private func performSearch() {
        guard let destination = SaveddSearchEngine.destination(for: searchText) else { return }
        addressHistory.record(searchText, url: destination.url, isSearch: destination.isSearch,
                              privacyMode: onboarding.preferences.privacyMode)
        loadURL(destination.url)
    }

    private func loadURL(_ url: URL) {
        snapshots[tabs[activeTabIndex].id] = nil
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
        let title = tabs[activeTabIndex].title
        sharePage = SharedBrowserPage(url: url,
                                      title: title.isEmpty || title == "New Tab" ? (url.host ?? url.absoluteString) : title)
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
    var snapshots: [UUID: UIImage]
    var onNewTab: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 280 : 150,
                            maximum: 320), spacing: 16)]
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(tabs) { tab in
                            tabCard(tab)
                                .id(tab.id)
                        }
                    }
                    .padding(20)
                }
                .onAppear { proxy.scrollTo(tabs[activeIndex].id, anchor: .center) }
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle(tabs.count == 1 ? "1 Tab" : "\(tabs.count) Tabs")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack {
                    Button {
                        onNewTab()
                        dismiss()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .semibold))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("New tab")
                    .accessibilityHint("Open a new Savedd tab")
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "checkmark.square")
                            .font(.system(size: 24, weight: .semibold))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Done")
                    .accessibilityHint("Return to the selected tab")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(.regularMaterial)
            }
            .tint(SaveddBrand.gold)
        }
    }

    private func tabCard(_ tab: BrowserTab) -> some View {
        let selected = tabs[activeIndex].id == tab.id
        let title = tab.title == "New Tab" ? (tab.url.host ?? "New Tab") : tab.title
        return VStack(spacing: 0) {
            // Separate controls avoid nesting a close button inside the selection button.
            HStack(spacing: 4) {
                Image(systemName: selected ? "checkmark.circle.fill" : "globe")
                    .foregroundStyle(selected ? SaveddBrand.gold : .secondary)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button {
                    closeTab(tab.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close tab: \(title)")
            }
            .padding(.leading, 12)

            Button {
                guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
                activeIndex = index
                dismiss()
            } label: {
                VStack(spacing: 0) {
                    GeometryReader { geometry in
                        if let snapshot = snapshots[tab.id] {
                            Image(uiImage: snapshot)
                                .resizable()
                                .scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.height,
                                       alignment: .top)
                                .clipped()
                        } else {
                            VStack(spacing: 12) {
                                SaveddMark()
                                    .fill(SaveddBrand.gold)
                                    .frame(width: 48, height: 48)
                                Text(tab.url.host ?? "New Tab")
                                    .font(.caption)
                                    .foregroundStyle(SaveddBrand.muted)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(SaveddBrand.background)
                        }
                    }
                    .aspectRatio(0.65, contentMode: .fit)
                    Text(tab.url.host ?? tab.url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(10)
                        .frame(maxWidth: .infinity)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open tab: \(title), \(tab.url.host ?? "")")
            .accessibilityAddTraits(selected ? [.isSelected] : [])
        }
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(selected ? SaveddBrand.gold : Color.primary.opacity(0.1),
                              lineWidth: selected ? 3 : 1)
                .allowsHitTesting(false)
        }
    }

    private func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let selectedID = tabs[activeIndex].id
        // Keep the browser's nonempty-tab invariant even when the last tab is closed.
        if tabs.count == 1 {
            onNewTab()
        }
        tabs.remove(at: index)
        if let selected = tabs.firstIndex(where: { $0.id == selectedID }) {
            activeIndex = selected
        } else {
            activeIndex = min(index, tabs.count - 1)
        }
    }
}

struct BookmarksView: View {
    @ObservedObject var store: BookmarkStore
    var onSelect: (Bookmark) -> Void
    @Environment(\.dismiss) private var dismiss
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
                BookmarkEditorView(title: "", url: "", onSave: { bookmark in
                    store.add(bookmark)
                    showAdd = false
                }, onCancel: { showAdd = false })
            }
        }
    }
}

struct BookmarkEditorView: View {
    @State private var title: String
    @State private var address: String
    let onSave: (Bookmark) -> Void
    let onCancel: () -> Void

    init(title: String, url: String, onSave: @escaping (Bookmark) -> Void, onCancel: @escaping () -> Void) {
        _title = State(initialValue: title)
        _address = State(initialValue: url)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    private var bookmarkURL: URL? {
        guard let destination = SaveddSearchEngine.destination(for: address), !destination.isSearch,
              destination.url.user == nil, destination.url.password == nil else { return nil }
        return destination.url
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                    .accessibilityIdentifier("bookmarkTitle")
                TextField("Website address", text: $address)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("bookmarkAddress")
            }
            .navigationTitle("Add Bookmark")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let url = bookmarkURL else { return }
                        onSave(Bookmark(title: title.trimmingCharacters(in: .whitespacesAndNewlines), url: url))
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || bookmarkURL == nil)
                }
            }
            .tint(SaveddBrand.gold)
        }
    }
}

/// A native action in the system share menu, using its built-in activity-editor
/// presentation rather than trying to present a second SwiftUI sheet mid-dismissal.
final class AddBookmarkActivity: UIActivity {
    private var url: URL?
    private let title: String
    private let onSave: (Bookmark) -> Void

    init(title: String, onSave: @escaping (Bookmark) -> Void) {
        self.title = title
        self.onSave = onSave
        super.init()
    }

    override class var activityCategory: UIActivity.Category { .action }
    override var activityType: UIActivity.ActivityType? {
        UIActivity.ActivityType("com.savedd.browser.add-bookmark")
    }
    override var activityTitle: String? { "Add Bookmark" }
    override var activityImage: UIImage? { UIImage(systemName: "bookmark") }

    override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
        activityItems.contains { item in
            guard let url = (item as? URL) ?? (item as? BrowserPageShareItem)?.page.url else { return false }
            return ["https", "http"].contains(url.scheme?.lowercased() ?? "")
                && url.host != nil && url.user == nil && url.password == nil
        }
    }

    override func prepare(withActivityItems activityItems: [Any]) {
        url = activityItems.compactMap { ($0 as? URL) ?? ($0 as? BrowserPageShareItem)?.page.url }.first
    }

    override var activityViewController: UIViewController? {
        guard let url else { return nil }
        return UIHostingController(rootView: BookmarkEditorView(
            title: title.isEmpty ? (url.host ?? url.absoluteString) : title,
            url: url.absoluteString,
            onSave: { [weak self] bookmark in
                self?.onSave(bookmark)
                self?.activityDidFinish(true)
            },
            onCancel: { [weak self] in self?.activityDidFinish(false) }
        ))
    }
}

struct SharedBrowserPage: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
}

/// Supply preview metadata locally rather than waiting for a website preview fetch.
final class BrowserPageShareItem: NSObject, UIActivityItemSource {
    let page: SharedBrowserPage
    init(page: SharedBrowserPage) { self.page = page; super.init() }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any { page.url }
    func activityViewController(_ activityViewController: UIActivityViewController,
                                itemForActivityType activityType: UIActivity.ActivityType?) -> Any? { page.url }
    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = page.title
        metadata.originalURL = page.url
        metadata.url = page.url
        return metadata
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    var page: SharedBrowserPage
    var onAddBookmark: (Bookmark) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [BrowserPageShareItem(page: page)],
                                 applicationActivities: [AddBookmarkActivity(title: page.title, onSave: onAddBookmark)])
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(OnboardingStore())
    }
}

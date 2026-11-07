import SwiftUI
import WebKit

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
    @State private var showShare = false
    @State private var showSettings = false
    @State private var showVoiceSearch = false
    @State private var focusAfterDictation = false
    @State private var shareItems: [Any] = []
    @State private var isEditingAddress = false
    @FocusState private var addressFieldFocused: Bool

    init(initialURL: URL = SaveddSearchEngine.homeURL) {
        #if DEBUG
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
            // Keep the functional page viewport inside the top and side safe areas.
            // A CSS-fixed website header must not sit behind the camera/status icons.
            .clipped()
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
        .sheet(isPresented: $showShare) {
            ShareSheet(activityItems: shareItems)
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onNewTab()
                        dismiss()
                    } label: {
                        Label("New Tab", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
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

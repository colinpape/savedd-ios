import SwiftUI
import WebKit

struct ContentView: View {
    @State private var url: URL = SaveddSearchEngine.homeURL
    @State private var searchText: String = ""
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var webViewProxy: WKWebView? // optional for later navigation controls

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search / address bar
                HStack {
                    Button(action: goBack) {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(!canGoBack)

                    Button(action: goForward) {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(!canGoForward)

                    TextField("Search Savedd or enter address", text: $searchText, onCommit: performSearch)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    Button("Go", action: performSearch)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(UIColor.systemBackground))

                Divider()

                WebView(url: $url, canGoBack: $canGoBack, canGoForward: $canGoForward)
                    .edgesIgnoringSafeArea(.bottom)
            }
            .navigationTitle("Savedd")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func performSearch() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if trimmed.contains(".") && !trimmed.contains(" ") {
            // Treat as URL
            var urlString = trimmed
            if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
                urlString = "https://" + urlString
            }
            if let parsed = URL(string: urlString) {
                url = parsed
                return
            }
        }

        // Default to Savedd search
        if let searchURL = SaveddSearchEngine.searchURL(for: trimmed) {
            url = searchURL
        }
    }

    private func goBack() {
        // Note: real back/forward requires a coordinator or @StateObject wrapper;
        // this is a placeholder for the MVP. Full navigation can be added next.
    }

    private func goForward() {
        // Placeholder
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

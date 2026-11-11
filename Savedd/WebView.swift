import SwiftUI
import WebKit

struct HistoryItem: Identifiable {
    let id = UUID()
    let title: String
    let url: URL
    let offset: Int
}

struct WebView: UIViewRepresentable {
    @Binding var url: URL
    @Binding var navigationRequest: BrowserNavigationRequest
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var backHistory: [HistoryItem]
    @Binding var forwardHistory: [HistoryItem]
    var preferences: SaveddPreferences = SaveddPreferences()
    var topContentInset: CGFloat = 0
    var isActive = true
    @Binding var snapshotRequest: UUID
    var onPageChanged: (URL, String) -> Void = { _, _ in }
    var onSnapshot: (UIImage) -> Void = { _ in }
    var goToHistoryItem: ((HistoryItem) -> Void)? = nil

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.userContentController.addUserScript(WKUserScript(
            source: preferences.bootstrapScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))

        let webView = WKWebView(frame: .zero, configuration: config)
        // Clip at the actual UIKit viewport, which includes the under-scroll
        // area on iOS 26 and stays inside the safe area on older versions.
        webView.clipsToBounds = true
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.observePage(of: webView)
        webView.allowsBackForwardNavigationGestures = true
        // The browser owns insets, including its bottom keyboard-aware toolbar.
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        updateViewport(webView)

        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 SaveddApp/1.0"

        webView.isOpaque = false
        webView.backgroundColor = preferences.appearance == .dark
            ? UIColor(SaveddBrand.background)
            : UIColor(red: 0.96, green: 0.94, blue: 0.89, alpha: 1)
        webView.scrollView.backgroundColor = webView.backgroundColor

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        updateViewport(webView)
        let becameActive = isActive && !context.coordinator.parent.isActive
        context.coordinator.parent = self
        if becameActive {
            DispatchQueue.main.async { context.coordinator.parent.updateHistory(webView) }
        }
        if isActive, context.coordinator.snapshotRequest != snapshotRequest {
            context.coordinator.snapshotRequest = snapshotRequest
            DispatchQueue.main.async { context.coordinator.capture(webView) }
        }
        let preferencesChanged = context.coordinator.appliedPreferences != preferences.webPayload
        if preferencesChanged {
            context.coordinator.appliedPreferences = preferences.webPayload
            webView.configuration.userContentController.removeAllUserScripts()
            webView.configuration.userContentController.addUserScript(WKUserScript(
                source: preferences.bootstrapScript, injectionTime: .atDocumentStart, forMainFrameOnly: true
            ))
            webView.backgroundColor = preferences.appearance == .dark
                ? UIColor(SaveddBrand.background)
                : UIColor(red: 0.96, green: 0.94, blue: 0.89, alpha: 1)
            webView.scrollView.backgroundColor = webView.backgroundColor
        }
        let request = navigationRequest
        let isNewRequest = context.coordinator.lastNavigationRequestID != request.id
        if isNewRequest {
            context.coordinator.lastNavigationRequestID = request.id
            switch request.action {
            case .load(let destination):
                load(webView, destination)
            case .back:
                if webView.canGoBack { webView.goBack() }
            case .forward:
                if webView.canGoForward { webView.goForward() }
            case .history(let offset, let destination):
                if let item = webView.backForwardList.item(at: offset), item.url == destination {
                    webView.go(to: item)
                }
            }
        } else if simulateLegacyURLSync && webView.url != url {
            // Debug negative control: recreate the previous homepage-replay bug.
            load(webView, url)
        } else if preferencesChanged, let currentURL = webView.url,
                  currentURL.scheme == "https",
                  ["savedd.com", "www.savedd.com"].contains(currentURL.host ?? ""),
                  currentURL.port == nil || currentURL.port == 443 {
            webView.evaluateJavaScript(preferences.bootstrapScript) { _, error in
                // Reload the current Savedd page so React reads the new config.
                // Keep the same WKWebView and its back/forward list. If the user
                // navigated elsewhere while JS ran, leave that page alone.
                if error == nil, webView.url == currentURL { webView.reload() }
            }
        }
        // Navigation delegate callbacks publish history; avoid changing SwiftUI
        // state synchronously during updateUIView.
    }

    private func load(_ webView: WKWebView, _ url: URL) {
        if url.isFileURL {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--visual-tabs-preview"),
               let html = try? String(contentsOf: url, encoding: .utf8) {
                webView.loadHTMLString(html, baseURL: url)
            } else {
                webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            }
            #else
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            #endif
        } else {
            webView.load(URLRequest(url: url))
        }
    }

    private var simulateLegacyURLSync: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--simulate-legacy-url-sync")
        #else
        return false
        #endif
    }

    private func updateViewport(_ webView: WKWebView) {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            let insets = UIEdgeInsets(top: max(0, topContentInset), left: 0, bottom: 0, right: 0)
            guard webView.obscuredContentInsets != insets || webView.scrollView.contentInset != insets else { return }
            let wasAtTop = webView.scrollView.contentOffset.y <= -webView.scrollView.contentInset.top + 1
            webView.obscuredContentInsets = insets
            webView.scrollView.contentInset = insets
            webView.scrollView.verticalScrollIndicatorInsets = insets
            if wasAtTop {
                webView.scrollView.setContentOffset(CGPoint(x: webView.scrollView.contentOffset.x, y: -insets.top), animated: false)
            }
        }
        #endif
    }

    private func updateHistory(_ webView: WKWebView) {
        guard isActive else { return }
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward

        let list = webView.backForwardList
        backHistory = list.backList.reversed().enumerated().map { offset, item in
            HistoryItem(title: item.title ?? item.url.absoluteString, url: item.url, offset: -(offset + 1))
        }
        forwardHistory = list.forwardList.enumerated().map { offset, item in
            HistoryItem(title: item.title ?? item.url.absoluteString, url: item.url, offset: offset + 1)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: WebView
        var appliedPreferences: String
        var snapshotRequest: UUID
        private var titleObservation: NSKeyValueObservation?
        private var urlObservation: NSKeyValueObservation?
        var lastNavigationRequestID: UUID?
        #if DEBUG
        private var regressionStarted = false
        #endif

        func observePage(of webView: WKWebView) {
            if !parent.simulateLegacyURLSync {
                // History API changes (pushState/replaceState/popstate) need not
                // trigger didCommit/didFinish or a document-title change.
                urlObservation = webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
                    guard let url = webView.url else { return }
                    DispatchQueue.main.async { [weak self, weak webView] in
                        guard let self, let webView, webView.url == url else { return }
                        self.parent.onPageChanged(url, webView.title ?? url.host ?? "New Tab")
                        self.parent.url = url
                        self.parent.updateHistory(webView)
                    }
                }
            }
            titleObservation = webView.observe(\.title, options: [.new]) { [weak self] webView, _ in
                guard let url = webView.url, let title = webView.title, !title.isEmpty else { return }
                DispatchQueue.main.async { [weak self, weak webView] in
                    guard webView?.url == url else { return }
                    self?.parent.onPageChanged(url, title)
                }
            }
        }

        init(_ parent: WebView) {
            self.parent = parent
            self.snapshotRequest = parent.snapshotRequest
            self.appliedPreferences = parent.preferences.webPayload
        }

        // Use WebKit's callback API: the async overlay requires a newer runtime.
        func capture(_ webView: WKWebView) {
            guard parent.isActive, !webView.isLoading, webView.bounds.width > 0,
                  webView.bounds.height > 0, let url = webView.url else { return }
            let configuration = WKSnapshotConfiguration()
            configuration.snapshotWidth = 320
            configuration.afterScreenUpdates = false
            webView.takeSnapshot(with: configuration) { [weak self, weak webView] image, _ in
                guard let self, let webView, webView.url == url,
                      !webView.isLoading, let image else { return }
                // Keep small in-memory previews; never persist page screenshots to disk.
                let size = CGSize(width: 320, height: 320 * image.size.height / image.size.width)
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                let thumbnail = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                    image.draw(in: CGRect(origin: .zero, size: size))
                }
                self.parent.onSnapshot(thumbnail)
            }
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url,
               let callback = SaveddAccountConfiguration.callbackURL(url) {
                decisionHandler(.cancel)
                webView.load(URLRequest(url: callback))
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--navigation-regression"), !regressionStarted {
                regressionStarted = true
                Task { @MainActor in await self.runNavigationRegression(webView) }
            }
            #endif
            if let url = webView.url {
                parent.onPageChanged(url, webView.title?.isEmpty == false ? webView.title! : (url.host ?? "New Tab"))
                webView.evaluateJavaScript("document.title") { [weak self, weak webView] result, _ in
                    guard webView?.url == url, let title = result as? String, !title.isEmpty else { return }
                    self?.parent.onPageChanged(url, title)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self, weak webView] in
                if let webView { self?.capture(webView) }
            }
            parent.updateHistory(webView)
            if let current = webView.url, current != parent.url {
                parent.url = current
            }
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            if let url = webView.url { parent.onPageChanged(url, url.host ?? "New Tab") }
            parent.updateHistory(webView)
            if let current = webView.url, current != parent.url {
                parent.url = current
            }
        }
    }
}

#if DEBUG
@MainActor
private extension WebView.Coordinator {
    func regressionJS(_ source: String, in webView: WKWebView) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(source) { result, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: result as? String ?? "") }
            }
        }
    }

    func requireRegression(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "SaveddNavigationRegression", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    func runNavigationRegression(_ webView: WKWebView) async {
        var stages: [String] = []
        var passed = false
        var failure = ""
        do {
            try await Task.sleep(for: .seconds(1))
            let originalBackCount = webView.backForwardList.backList.count
            let originalDocument = try await regressionJS("window.documentID", in: webView)
            _ = try await regressionJS("document.getElementById('search').requestSubmit(); 'submitted'", in: webView)
            // Force the same SwiftUI redraw that previously replayed the homepage.
            parent.snapshotRequest = UUID()
            try await Task.sleep(for: .seconds(2))
            try requireRegression(webView.url?.query?.contains("q=coffee") == true,
                                  "Website search was sent back to the homepage")
            try requireRegression(parent.url == webView.url, "The address bar missed a History API URL change")
            let result = try await regressionJS("document.getElementById('result').textContent", in: webView)
            try requireRegression(result == "Results: coffee", "Expected search results to stay visible")
            try requireRegression(webView.backForwardList.backList.count == originalBackCount + 1,
                                  "Search added an unexpected extra navigation")
            stages.append("website-search-and-redraw")

            _ = try await regressionJS("history.replaceState({}, '', '?q=tea'); render(); 'replaced'", in: webView)
            parent.snapshotRequest = UUID()
            try await Task.sleep(for: .seconds(1))
            try requireRegression(parent.url.query == "q=tea", "replaceState did not update the browser address")
            try requireRegression(webView.backForwardList.backList.count == originalBackCount + 1,
                                  "replaceState unexpectedly added history")
            stages.append("replaceState")

            parent.navigationRequest = BrowserNavigationRequest(.back)
            try await Task.sleep(for: .seconds(2))
            try requireRegression(webView.url?.query == nil, "Native Back did not return home")
            let home = try await regressionJS("document.getElementById('result').textContent", in: webView)
            try requireRegression(home == "Home", "Back did not restore the homepage state")
            try requireRegression(webView.canGoForward, "Back destroyed the forward history")
            stages.append("native-back")

            parent.navigationRequest = BrowserNavigationRequest(.forward)
            try await Task.sleep(for: .seconds(2))
            try requireRegression(webView.url?.query == "q=tea", "Native Forward did not restore results")
            try requireRegression(webView.backForwardList.backList.count == originalBackCount + 1,
                                  "Back/Forward created duplicate history entries")
            stages.append("native-forward")

            // A title change and a redraw must leave the document intact.
            _ = try await regressionJS("document.title = 'Updated results'; 'updated'", in: webView)
            parent.snapshotRequest = UUID()
            try await Task.sleep(for: .seconds(1))
            let sameDocument = try await regressionJS("window.documentID", in: webView)
            try requireRegression(sameDocument == originalDocument, "A title/SwiftUI update reloaded the document")
            stages.append("title-update-without-reload")

            parent.navigationRequest = BrowserNavigationRequest(.history(offset: -1, url: webView.backForwardList.backItem!.url))
            try await Task.sleep(for: .seconds(2))
            try requireRegression(webView.url?.query == nil && webView.canGoForward,
                                  "History-menu selection loaded a new page instead of moving in history")
            stages.append("history-menu")

            var components = URLComponents(url: webView.url!, resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "q", value: "typed")]
            let typedURL = components.url!
            parent.navigationRequest = BrowserNavigationRequest(.load(typedURL))
            try await Task.sleep(for: .seconds(2))
            try requireRegression(webView.url == typedURL && parent.url == typedURL,
                                  "An explicit address-bar navigation was ignored")
            let firstLoadID = try await regressionJS("window.documentID", in: webView)
            parent.navigationRequest = BrowserNavigationRequest(.load(typedURL))
            try await Task.sleep(for: .seconds(2))
            let secondLoadID = try await regressionJS("window.documentID", in: webView)
            try requireRegression(!firstLoadID.isEmpty && firstLoadID != secondLoadID,
                                  "Re-submitting the same address did not load it")
            stages.append("explicit-and-same-url-navigation")

            _ = try await regressionJS("location.replace('?q=redirect'); 'redirecting'", in: webView)
            try await Task.sleep(for: .seconds(2))
            try requireRegression(webView.url?.query == "q=redirect" && parent.url == webView.url,
                                  "A page-driven navigation replayed an old address-bar command")
            stages.append("page-driven-redirect")
            passed = true
        } catch { failure = error.localizedDescription }

        let report: [String: Any] = [
            "passed": passed, "stages": stages, "error": failure,
            "url": webView.url?.absoluteString ?? "",
            "backHistory": webView.backForwardList.backList.map { $0.url.absoluteString }
        ]
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: documents.appendingPathComponent("navigation-regression.json"), options: .atomic)
        }
    }
}
#endif

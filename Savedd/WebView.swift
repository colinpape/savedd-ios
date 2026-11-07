import SwiftUI
import WebKit

struct HistoryItem: Identifiable {
    let id = UUID()
    let title: String
    let url: URL
}

struct WebView: UIViewRepresentable {
    @Binding var url: URL
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var backHistory: [HistoryItem]
    @Binding var forwardHistory: [HistoryItem]
    var preferences: SaveddPreferences = SaveddPreferences()
    var topContentInset: CGFloat = 0
    var isActive = true
    var snapshotRequest = UUID()
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
        context.coordinator.observeTitle(of: webView)
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
        if webView.url != url {
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
        backHistory = list.backList.map { item in
            HistoryItem(title: item.title ?? item.url.absoluteString, url: item.url)
        }.reversed()

        forwardHistory = list.forwardList.map { item in
            HistoryItem(title: item.title ?? item.url.absoluteString, url: item.url)
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

        func observeTitle(of webView: WKWebView) {
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

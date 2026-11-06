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
    var goToHistoryItem: ((HistoryItem) -> Void)? = nil

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 SaveddApp/1.0"

        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0)
        webView.scrollView.backgroundColor = webView.backgroundColor

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if webView.url != url {
            let request = URLRequest(url: url)
            webView.load(request)
        }
        updateHistory(webView)
    }

    private func updateHistory(_ webView: WKWebView) {
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

        init(_ parent: WebView) {
            self.parent = parent
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
            parent.updateHistory(webView)
            if let current = webView.url, current != parent.url {
                parent.url = current
            }
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            parent.updateHistory(webView)
            if let current = webView.url, current != parent.url {
                parent.url = current
            }
        }
    }
}

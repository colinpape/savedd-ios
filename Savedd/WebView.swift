import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    @Binding var url: URL
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true

        // Force color-scheme: dark so sites that check prefers-color-scheme see dark mode
        let darkSchemeScript = """
        (function() {
            const style = document.createElement('style');
            style.id = 'savedd-force-dark';
            style.innerHTML = 'html { color-scheme: dark !important; }';
            (document.head || document.documentElement).appendChild(style);
            document.documentElement.style.colorScheme = 'dark';
        })();
        """

        let userScript = WKUserScript(
            source: darkSchemeScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(userScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        // Also set the UIKit trait so the web view itself reports dark
        webView.overrideUserInterfaceStyle = .dark

        // Dark background so there's no white flash before the page loads
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
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebView

        init(_ parent: WebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.canGoBack = webView.canGoBack
            parent.canGoForward = webView.canGoForward
            if let current = webView.url {
                parent.url = current
            }
        }
    }
}

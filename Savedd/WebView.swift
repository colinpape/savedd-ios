import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    @Binding var url: URL
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true

        // Inject dark mode CSS into every page
        let darkModeScript = """
        (function() {
            const style = document.createElement('style');
            style.id = 'savedd-dark-mode';
            style.innerHTML = `
                html, body {
                    color-scheme: dark !important;
                    background-color: #1c1c1e !important;
                    color: #e5e5e7 !important;
                }
                body, div, section, article, main, header, footer, nav, aside, p, span, h1, h2, h3, h4, h5, h6, li, td, th {
                    background-color: transparent !important;
                    color: #e5e5e7 !important;
                }
                a { color: #0a84ff !important; }
                input, textarea, select, button {
                    background-color: #2c2c2e !important;
                    color: #e5e5e7 !important;
                    border-color: #3a3a3c !important;
                }
            `;
            document.documentElement.appendChild(style);
        })();
        """

        let userScript = WKUserScript(
            source: darkModeScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(userScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0) // #1c1c1e
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

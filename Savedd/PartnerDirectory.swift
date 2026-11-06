import SwiftUI
import WebKit

struct SaveddPartner: Codable, Equatable, Identifiable {
    let slug: String
    let pubkey: String
    let name: String
    var id: String { pubkey }
    var initials: String {
        String(name.split(separator: " ").prefix(2).compactMap(\.first)).uppercased()
    }
    func matches(_ text: String) -> Bool {
        text.isEmpty || name.localizedCaseInsensitiveContains(text)
            || slug.localizedCaseInsensitiveContains(text)
            || pubkey.caseInsensitiveCompare(text) == .orderedSame
    }
}

/// Reads the same signed public directory used by the website's PartnerAdmin.
/// The bundled reader verifies event signatures AND the owner/admin trust chain.
/// No login, private keys, web page, or referral tracking is involved in this read.
@MainActor
final class PartnerDirectory: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate {
    @Published private(set) var partners: [SaveddPartner] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    private var webView: WKWebView?
    private var timeout: Task<Void, Never>?

    func load() {
        guard !isLoading else { return }
        stop()
        isLoading = true
        error = nil
        let controller = WKUserContentController()
        controller.add(self, name: "partnerDirectory")
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController = controller
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        webView = view
        view.loadHTMLString("<html><head><meta charset='utf-8'></head><body></body></html>", baseURL: nil)
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            self?.failed()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = Bundle.main.url(forResource: "PartnerDirectory", withExtension: "js"),
              let script = try? String(contentsOf: url, encoding: .utf8) else { failed(); return }
        webView.evaluateJavaScript(script) { [weak self] _, error in
            if error != nil { self?.failed() }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "partnerDirectory", message.frameInfo.isMainFrame,
              let body = message.body as? [String: Any],
              let status = body["status"] as? String else { return }
        guard status == "ready", let raw = body["partners"],
              let data = try? JSONSerialization.data(withJSONObject: raw),
              let records = try? JSONDecoder().decode([SaveddPartner].self, from: data) else { failed(); return }
        partners = records.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        isLoading = false
        stop()
    }

    func stop() {
        isLoading = false
        timeout?.cancel()
        timeout = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "partnerDirectory")
        webView?.stopLoading()
        webView = nil
    }

    private func failed() {
        error = "We couldn’t load the partner directory. You can retry, enter a code, or skip for now."
        isLoading = false
        stop()
    }
}

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

/// Reads the website's public admin-managed directory without requiring login.
/// URLSession handles networking; the bundled JS performs synchronous signature
/// and trust-chain verification. WebKit background-page timers are never needed.
@MainActor
final class PartnerDirectory: NSObject, ObservableObject, WKNavigationDelegate {
    @Published private(set) var partners: [SaveddPartner] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    private var webView: WKWebView?
    private var readerTask: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private static let owner = "c45041618951bb6012ac23f5cdf3d740465f2d640be841fd9bb1d0733370cd3c"
    private static let relays = [
        "wss://savedd-sip-relay.savedd-sip-relay.workers.dev/", "wss://relay.ditto.pub/",
        "wss://relay-na1.metanomalist.com/", "wss://relay.primal.net/",
        "wss://test-sip-relay.sip-01test.workers.dev/", "wss://sip-relay-2.sip-booster-relay.workers.dev/",
        "wss://sip-relay-3.uncaged-sip.workers.dev/", "wss://sip-relay-4.sip-relay-4.workers.dev/",
        "wss://jskitty.cat/nostr", "wss://search.nos.today/", "wss://relay.nostr.band/",
        "wss://relay.noswhere.com/", "wss://relay.pocketnostr.com/", "wss://relay.damus.io/"
    ]

    func load() {
        guard !isLoading else { return }
        stop()
        isLoading = true
        error = nil
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        webView = view
        view.loadHTMLString("<html><head><meta charset='utf-8'></head><body></body></html>", baseURL: nil)
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(25))
            guard !Task.isCancelled else { return }
            self?.failed()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard readerTask == nil else { return }
        readerTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard let url = Bundle.main.url(forResource: "PartnerDirectory", withExtension: "js") else {
                    throw DirectoryError.unavailable
                }
                let script = try String(contentsOf: url, encoding: .utf8)
                _ = try await evaluate(script + "; true;", in: webView)
                let roles = try await query(authors: [Self.owner], tags: ["savedd:admin-roles", "presearchstr:admin-roles"], limit: 8)
                let rolesJSON = try json(roles)
                let authorsResult = try await evaluate("SaveddPartnerReader.trustedAuthors(\(rolesJSON))", in: webView)
                guard let authors = authorsResult as? [String] else { throw DirectoryError.unavailable }
                let events = try await query(authors: authors, tags: ["savedd:partners"], limit: 20)
                let eventsJSON = try json(events)
                let authorsJSON = try json(authors)
                let result = try await evaluate("SaveddPartnerReader.resolveDirectory(\(eventsJSON), \(authorsJSON))", in: webView)
                try Task.checkCancellation()
                let data = try JSONSerialization.data(withJSONObject: result)
                let records = try JSONDecoder().decode([SaveddPartner].self, from: data)
                partners = records.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                isLoading = false
                stop()
            } catch {
                if !Task.isCancelled { failed() }
            }
        }
    }

    private struct RelayReply: Sendable {
        let events: [String]
        let complete: Bool
    }
    private enum DirectoryError: Error { case unavailable }

    private func json(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value)
        guard let text = String(data: data, encoding: .utf8) else { throw DirectoryError.unavailable }
        return text
    }

    /// Use the Objective-C completion API: WebKit's Swift async overlay can
    /// introduce a libswiftWebKit dependency absent on supported runtimes.
    /// JSON arguments above are encoded as data, never interpolated raw strings.
    private func evaluate(_ script: String, in view: WKWebView) async throws -> Any {
        try await withCheckedThrowingContinuation { continuation in
            view.evaluateJavaScript(script) { result, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: result ?? NSNull()) }
            }
        }
    }

    private func query(authors: [String], tags: [String], limit: Int) async throws -> [[String: Any]] {
        let filter: [String: Any] = ["kinds": [30078], "authors": authors, "#d": tags, "limit": limit]
        let request = String(data: try JSONSerialization.data(withJSONObject: ["REQ", "savedd-ios-directory", filter]), encoding: .utf8)!
        let replies = await withTaskGroup(of: RelayReply.self, returning: [RelayReply].self) { group in
            for relay in Self.relays {
                group.addTask { await Self.queryRelay(relay, request: request, authors: authors, tags: tags, limit: limit) }
            }
            var replies: [RelayReply] = []
            for await reply in group { replies.append(reply) }
            return replies
        }
        try Task.checkCancellation()
        guard replies.contains(where: \.complete) else { throw DirectoryError.unavailable }
        return replies.flatMap(\.events).compactMap { json in
            guard let data = json.data(using: .utf8) else { return nil }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
    }

    private nonisolated static func queryRelay(_ address: String, request: String, authors: [String], tags: [String], limit: Int) async -> RelayReply {
        guard let url = URL(string: address), !Task.isCancelled else { return RelayReply(events: [], complete: false) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 5
        let session = URLSession(configuration: configuration)
        let socket = session.webSocketTask(with: url)
        let deadline = Task {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { socket.cancel(with: .goingAway, reason: nil) }
        }
        defer {
            deadline.cancel()
            socket.cancel(with: .normalClosure, reason: nil)
            session.invalidateAndCancel()
        }
        return await withTaskCancellationHandler {
            var events: [String] = []
            do {
                socket.resume()
                try await socket.send(.string(request))
                for _ in 0..<256 {
                    try Task.checkCancellation()
                    let message = try await socket.receive()
                    let data: Data
                    switch message {
                    case .string(let text): data = Data(text.utf8)
                    case .data(let bytes): data = bytes
                    @unknown default: continue
                    }
                    guard data.count <= 1_000_000,
                          let frame = try JSONSerialization.jsonObject(with: data) as? [Any], frame.count >= 2,
                          frame[1] as? String == "savedd-ios-directory" else { continue }
                    if frame[0] as? String == "EOSE" { return RelayReply(events: events, complete: true) }
                    guard frame[0] as? String == "EVENT", frame.count >= 3,
                          let event = frame[2] as? [String: Any], event["kind"] as? Int == 30078,
                          let author = event["pubkey"] as? String, authors.contains(author),
                          let eventTags = event["tags"] as? [[String]],
                          let d = eventTags.first(where: { $0.first == "d" }), d.count >= 2, tags.contains(d[1]),
                          events.count < limit,
                          let encoded = try? JSONSerialization.data(withJSONObject: event),
                          let json = String(data: encoded, encoding: .utf8) else { continue }
                    events.append(json)
                }
            } catch { /* an offline relay must not block the others */ }
            return RelayReply(events: events, complete: false)
        } onCancel: {
            socket.cancel(with: .goingAway, reason: nil)
        }
    }

    func stop() {
        isLoading = false
        readerTask?.cancel()
        readerTask = nil
        timeout?.cancel()
        timeout = nil
        webView?.stopLoading()
        webView = nil
    }

    private func failed() {
        error = "We couldn’t load the partner directory. You can retry, enter a code, or skip for now."
        stop()
    }
}

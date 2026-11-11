import Foundation

final class DirectoryProtocol: URLProtocol {
    static var reply: (Int, Data) = (200, Data())
    static var requests: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.reply.0, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.reply.1)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
struct OnboardingIntegrationTests {
    @MainActor
    static func finish(_ directory: PartnerDirectory) async throws {
        for _ in 0..<200 {
            if !directory.isLoading { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        preconditionFailure("Directory load did not finish")
    }

    @MainActor
    static func main() async throws {
        let key = String(repeating: "a", count: 64)
        let records: [[String: String]] = [
            ["slug": "alex", "pubkey": key, "name": "Alex Newman"],
            ["slug": "alex", "pubkey": String(repeating: "b", count: 64), "name": "Duplicate"],
            ["slug": "admin", "pubkey": String(repeating: "c", count: 64), "name": "Reserved"],
            ["slug": "invalid", "pubkey": "invalid", "name": "Bad key"]
        ]
        func data(_ partners: [[String: String]], enabled: Bool = true) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["partners": partners, "config": ["enabled": enabled]])
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DirectoryProtocol.self]
        let session = URLSession(configuration: config)
        DirectoryProtocol.reply = (200, try data(records))
        let directory = PartnerDirectory(session: session)
        directory.loadIfNeeded()
        directory.loadIfNeeded()
        try await finish(directory)
        precondition(directory.partners.count == 1 && directory.partners[0].slug == "alex")
        precondition(directory.partners[0].matches("newman") && directory.error == nil)
        precondition(DirectoryProtocol.requests.count == 1)
        let request = DirectoryProtocol.requests[0]
        precondition(request.url == SaveddReferralService.endpoint && request.httpMethod == "POST")
        precondition(request.value(forHTTPHeaderField: "apikey") == SaveddReferralService.publishableKey)
        precondition(request.value(forHTTPHeaderField: "Authorization") == nil)
        directory.loadIfNeeded()
        precondition(DirectoryProtocol.requests.count == 1)
        let empty = PartnerDirectory(session: session)
        DirectoryProtocol.reply = (200, try data([]))
        empty.loadIfNeeded(); try await finish(empty)
        let count = DirectoryProtocol.requests.count
        empty.loadIfNeeded()
        precondition(empty.partners.isEmpty && empty.error == nil && DirectoryProtocol.requests.count == count)
        let retry = PartnerDirectory(session: session)
        DirectoryProtocol.reply = (503, Data())
        retry.loadIfNeeded(); try await finish(retry)
        precondition(retry.error != nil)
        DirectoryProtocol.reply = (200, try data(records))
        retry.load(); try await finish(retry)
        precondition(retry.error == nil && retry.partners.count == 1)
        let paused = PartnerDirectory(session: session)
        DirectoryProtocol.reply = (200, try data(records, enabled: false))
        paused.loadIfNeeded(); try await finish(paused)
        precondition(!paused.isEnabled && paused.partners.isEmpty)
        let stopped = PartnerDirectory(session: session)
        stopped.load(); stopped.stop()
        try await Task.sleep(nanoseconds: 30_000_000)
        precondition(!stopped.isLoading && stopped.partners.isEmpty && stopped.error == nil)
        let callback = SaveddAccountConfiguration.callbackURL(URL(string: "savedd://auth/callback?code=test-code")!)!
        precondition(callback.absoluteString == "https://www.savedd.com/?code=test-code")
        for raw in ["https://evil.test/?code=x", "savedd://evil/callback?code=x", "savedd://auth/other?code=x", "savedd://auth/callback?code=", "savedd://auth/callback?code=x&code=y", "savedd://auth/callback?code=x&redirect=https://evil.test", "savedd://user@auth/callback?code=x", "savedd://auth/callback?code=x#token"] {
            precondition(SaveddAccountConfiguration.callbackURL(URL(string: raw)!) == nil)
        }
        precondition(SaveddAccountConfiguration.signupURL?.host == "www.savedd.com")
        let suite = "savedd.onboarding-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var prefs = SaveddPreferences()
        prefs.partner = SaveddPartner(slug: "alex", pubkey: key, name: "Alex Newman")
        prefs.referralCode = "alex"
        defaults.set(try JSONEncoder().encode(prefs), forKey: "savedd.onboarding.preferences.v1")
        let store = OnboardingStore(defaults: defaults)
        precondition(store.preferences == prefs && store.preferences.appearance == .dark)
        print("Database directory, cache, retry, paused program, cancellation, auth callback allowlist and existing preference migration passed")
    }
}

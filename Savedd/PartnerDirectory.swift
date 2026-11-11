import SwiftUI

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

/// Public client configuration, matching Savedd-com/Savedd's deployed website.
/// This publishable key is not a service-role key and grants no private table access.
enum SaveddReferralService {
    static let endpoint = URL(string: "https://iofxuntxecxcqihuugcr.supabase.co/functions/v1/referrals")!
    static let publishableKey = "sb_publishable_oqVo1X1z9GlHeozNVs_RsQ_kD3ZLW98"

    struct Directory: Decodable {
        struct Configuration: Decodable { let enabled: Bool }
        let partners: [SaveddPartner]
        let config: Configuration
    }

    static func request() -> URLRequest {
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.httpBody = Data(#"{"action":"public"}"#.utf8)
        return request
    }

    static func decode(_ data: Data) throws -> Directory {
        guard data.count <= 2_000_000 else { throw URLError(.dataLengthExceedsMaximum) }
        return try JSONDecoder().decode(Directory.self, from: data)
    }

    static func approvedPartners(in directory: Directory) -> [SaveddPartner] {
        guard directory.config.enabled else { return [] }
        let reserved = Set("about admin api assets bookmarks build community dashboard docs explore goodbye heaven index instances network partners policy protocol remoteloginsuccess settings www".split(separator: " ").map(String.init))
        var slugs = Set<String>(), keys = Set<String>()
        return directory.partners.compactMap { partner in
            let slug = partner.slug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let key = partner.pubkey.lowercased()
            let name = partner.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (2...32).contains(slug.count), !reserved.contains(slug),
                  slug.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) != nil,
                  key.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
                  !name.isEmpty, name.count <= 60, !slugs.contains(slug), !keys.contains(key) else { return nil }
            slugs.insert(slug); keys.insert(key)
            return SaveddPartner(slug: slug, pubkey: key, name: name)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// Prefetched once at onboarding entry; successes (including an empty directory)
/// stay in memory throughout that session. All active reads use the database API.
@MainActor
final class PartnerDirectory: ObservableObject {
    @Published private(set) var partners: [SaveddPartner] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var isEnabled = true
    private var readerTask: Task<Void, Never>?
    private var hasLoaded = false
    private var generation = UUID()
    private let session: URLSession

    init(session: URLSession? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        self.session = session ?? URLSession(configuration: configuration)
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        load()
    }

    func load() {
        guard !isLoading else { return }
        error = nil
        isLoading = true
        let current = UUID()
        generation = current
        readerTask = Task { [weak self] in
            guard let self else { return }
            do {
                let (data, response) = try await session.data(for: SaveddReferralService.request())
                try Task.checkCancellation()
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                let directory = try SaveddReferralService.decode(data)
                guard generation == current else { return }
                partners = SaveddReferralService.approvedPartners(in: directory)
                isEnabled = directory.config.enabled
                hasLoaded = true
                isLoading = false
                readerTask = nil
            } catch {
                guard !Task.isCancelled, generation == current else { return }
                isLoading = false
                readerTask = nil
                self.error = "We couldn’t load the partner directory. You can retry, enter a code, or skip for now."
            }
        }
    }

    func stop() {
        generation = UUID()
        readerTask?.cancel()
        readerTask = nil
        isLoading = false
    }
}

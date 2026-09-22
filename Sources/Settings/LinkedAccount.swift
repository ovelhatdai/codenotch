import Foundation

enum AccountService: String, Codable, CaseIterable, Identifiable {
    case claude, codex
    var id: String { rawValue }
    var title: String { self == .claude ? "Claude Code" : "Codex" }
}

/// Metadata only. The official CLI owns credentials in an isolated directory.
struct LinkedAccount: Codable, Identifiable {
    let id: String
    let name: String
    let email: String
    let directory: URL
    var service: AccountService = .claude
    var profile: ClaudeProfile { ClaudeProfile(slug: "linked-" + id, configDirectory: directory) }
    var codexProfile: CodexProfile { CodexProfile(slug: "linked-" + id, configDirectory: directory) }
    var providerID: String { service == .claude ? profile.id : codexProfile.id }
    static let key = "linkedAccounts"
    static func load(defaults: UserDefaults = .standard) -> [Self] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Self].self, from: data)) ?? []
    }
    func save(defaults: UserDefaults = .standard) throws {
        var accounts = Self.load(defaults: defaults)
        accounts.removeAll { $0.id == id }
        accounts.append(self)
        defaults.set(try JSONEncoder().encode(accounts), forKey: Self.key)
    }
    static func matches(email: String, service: AccountService, summaries: [ProviderSummary]) -> [String] {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return summaries.filter {
            (service == .claude ? ClaudeProfile.isClaude(providerID: $0.id) : CodexProfile.isCodex(providerID: $0.id))
                && $0.account?.label?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized
        }.map(\.id)
    }
    static func account(providerID: String) -> Self? { load().first { $0.providerID == providerID } }
}
typealias LinkedClaudeAccount = LinkedAccount

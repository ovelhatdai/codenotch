import Foundation

/// Presentation only: source accounts, polling and history remain independent.
enum NotchGrouping: String, CaseIterable, Identifiable {
    case accounts, services, claude, codex
    static let key = "notchGrouping"
    static let prefix = "account-group:"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .accounts: return "Todas as contas"
        case .services: return "Grupos por serviço"
        case .claude: return "Só Claude"
        case .codex: return "Só Codex"
        }
    }
    static func service(_ snapshot: ProviderSnapshot) -> String? {
        if ClaudeProfile.isClaude(providerID: snapshot.providerID) { return "claude" }
        if CodexProfile.isCodex(providerID: snapshot.providerID) { return "codex" }
        return nil
    }
    func apply(to snapshots: [ProviderSnapshot], quota: NotchQuota, names: Data = Data()) -> [ProviderSnapshot] {
        switch self {
        case .accounts:
            // Keep the user's relative order within each service, but never
            // interleave a Codex profile between two Claude accounts.
            return snapshots.filter { Self.service($0) == "claude" }
                + snapshots.filter { Self.service($0) == "codex" }
                + snapshots.filter { Self.service($0) == nil }
        case .claude, .codex: return snapshots.filter { Self.service($0) == rawValue }
        case .services:
            var seen = Set<String>()
            return snapshots.compactMap { snapshot in
                guard let service = Self.service(snapshot) else { return snapshot }
                guard seen.insert(service).inserted else { return nil }
                let members = snapshots.filter { Self.service($0) == service }
                let windows = members.map { member in
                    let reading = quota.reading(from: member).headline
                    let name = AccountNames.name(for: member.id, fallback: member.displayName, in: names, email: member.accountEmail)
                    let valid = member.status == .ok
                    return LimitWindow(id: member.id, label: name,
                        usedFraction: valid ? reading?.usedFraction : nil,
                        detail: valid ? (reading == nil ? "Sem leitura" : reading?.label) : "Verificar conexão / leitura antiga",
                        resetsAt: valid ? reading?.resetsAt : nil)
                }
                return ProviderSnapshot(id: Self.prefix + service,
                    displayName: service == "claude" ? "Claude" : "Codex",
                    glyph: snapshot.glyph, fidelity: .official, status: .ok,
                    windows: windows, headlineID: "no-combined-quota",
                    plan: "\(members.count) \(members.count == 1 ? "conta" : "contas") · clique para abrir o dashboard")
            }
        }
    }
}

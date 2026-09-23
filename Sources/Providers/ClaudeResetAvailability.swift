import Foundation

/// Read-only offer metadata from Claude Code's usage response. A surface
/// restriction does not mean the account has no resets on claude.ai.
enum ClaudeResetAvailability {
    struct Reading: Equatable {
        var credits: CodexResetCredits?
        var explanation: String?
    }
    private struct Response: Decodable { let cedar_ember: Offer? }
    private struct Offer: Decodable {
        let eligible: Bool
        let ineligible_reason: String?
        let grants: [Grant]?
    }
    private struct Grant: Decodable {
        let id: String
        let resets_left: Int
        let starts_at: String?
        let ends_at: String?
        let paused: Bool?
    }
    static func read(_ data: Data, now: Date = Date()) -> Reading {
        guard let offer = try? JSONDecoder().decode(Response.self, from: data).cedar_ember else {
            return Reading(explanation: "O Claude não informou as redefinições nesta consulta.")
        }
        guard offer.eligible else {
            if offer.ineligible_reason == "no_grant" {
                return Reading(credits: CodexResetCredits(availableCount: 0))
            }
            return Reading(explanation: "Consulte no Claude: a API não disponibilizou a oferta para este acesso.")
        }
        guard let grants = offer.grants, grants.allSatisfy({ $0.resets_left >= 0 && !$0.id.isEmpty }),
              Set(grants.map(\.id)).count == grants.count else {
            return Reading(explanation: "O Claude enviou uma oferta incompleta. Consulte no Claude.")
        }
        let parser = ISO8601DateFormatter()
        func date(_ value: String?) -> Date? {
            guard let value else { return nil }
            parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let result = parser.date(from: value) { return result }
            parser.formatOptions = [.withInternetDateTime]
            return parser.date(from: value)
        }
        // An unreadable expiry must never turn an expired grant into a live one.
        guard grants.allSatisfy({ ($0.starts_at == nil || date($0.starts_at) != nil)
            && ($0.ends_at == nil || date($0.ends_at) != nil) }) else {
            return Reading(explanation: "Validade da oferta não reconhecida. Consulte no Claude.")
        }
        let active = grants.filter {
            !$0.id.isEmpty && $0.paused != true && (date($0.starts_at) ?? .distantPast) <= now
                && (date($0.ends_at) ?? .distantFuture) > now
        }
        // Keep one record per grant rather than allocating one object per reset.
        var count = 0
        for grant in active {
            let sum = count.addingReportingOverflow(grant.resets_left)
            guard !sum.overflow else { return Reading(explanation: "Quantidade de redefinições inválida.") }
            count = sum.partialValue
        }
        return Reading(credits: CodexResetCredits(availableCount: count, credits: active.filter { $0.resets_left > 0 }.map {
            .init(id: $0.id, status: "available", expiresAt: date($0.ends_at))
        }))
    }
}

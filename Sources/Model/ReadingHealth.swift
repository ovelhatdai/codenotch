import Foundation

struct ReadingHealth: Equatable {
    enum State: String, Codable { case current, previous, offline, expired, denied, identityMismatch, unavailable }
    var state: State
    var measuredAt: Date?
    var attemptedAt: Date?
    var currentUntil: Date? = nil

    func at(_ now: Date) -> Self {
        guard state == .current, let currentUntil, now > currentUntil else { return self }
        var aged = self
        aged.state = .previous
        return aged
    }
    static func success(_ snapshot: ProviderSnapshot, now: Date, staleAfter: TimeInterval) -> Self {
        guard snapshot.hasReading else {
            return Self(state: .unavailable, measuredAt: nil, attemptedAt: now)
        }
        let measuredAt = snapshot.sourceUpdatedAt ?? now
        let old = snapshot.status.isStale || now.timeIntervalSince(measuredAt) > staleAfter
        return Self(state: old ? .previous : .current, measuredAt: measuredAt, attemptedAt: now,
                    currentUntil: measuredAt.addingTimeInterval(staleAfter))
    }
    var title: String {
        switch state {
        case .current: return "Leitura atualizada"
        case .previous: return "Última leitura conhecida"
        case .offline: return "Sem conexão · última leitura conhecida"
        case .expired: return "Login expirado · reconecte a conta"
        case .denied: return "Acesso à sessão não autorizado"
        case .identityMismatch: return "Identidade diferente · reconecte a conta"
        case .unavailable: return "Sem leitura disponível"
        }
    }
    static func failure(_ error: Error, measuredAt: Date?, now: Date) -> Self {
        let state: State
        switch error {
        case UsageProviderError.identityMismatch: state = .identityMismatch
        case UsageProviderError.needsAuth, UsageProviderError.credentialExpired, UsageProviderError.signedOutByOwner: state = .expired
        case UsageProviderError.accessDenied: state = .denied
        case is URLError: state = .offline
        default: state = measuredAt == nil ? .unavailable : .previous
        }
        return Self(state: state, measuredAt: measuredAt, attemptedAt: now)
    }
}

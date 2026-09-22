import Foundation
import SwiftUI

enum UsageDisplayMode: String, CaseIterable, Identifiable {
    case used, available
    static let key = "usageDisplayMode"
    var id: String { rawValue }
    var title: String { L10n.t(self == .used ? "Used" : "Available") }

    func fraction(for used: Double) -> Double {
        let clamped = min(max(used, 0), 1)
        return self == .used ? clamped : 1 - clamped
    }

    func text(for snapshot: ProviderSnapshot) -> String {
        guard snapshot.hasReading else { return "—" }
        guard self == .available, snapshot.kind != .localRuntime,
              snapshot.headline?.prefersUsedText != true,
              let used = snapshot.usedFraction else { return snapshot.headlineText }
        return Percent.halves(for: used).left + "%"
    }
}

/// Presentation-only aliases; provider IDs and authentication remain untouched.
enum AccountNames {
    static let key = "accountDisplayNames"

    static func name(for id: String, fallback: String, in data: Data, email: String? = nil) -> String {
        // The default Codex provider follows the work app, not a fixed person.
        // Never carry a per-provider nickname across a work-account switch.
        if id == "codex" {
            return email.map { "Codex ativo · " + $0 } ?? "Codex · conta ativa"
        }
        let names = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
        return names[id] ?? fallback
    }

    static func setting(_ name: String, for id: String, in data: Data) -> Data {
        var names = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        names[id] = trimmed.isEmpty ? nil : String(trimmed.prefix(80))
        return (try? JSONEncoder().encode(names)) ?? data
    }
}

private struct UsageDisplayModeKey: EnvironmentKey {
    static let defaultValue: UsageDisplayMode = .used
}
extension EnvironmentValues {
    var usageDisplayMode: UsageDisplayMode {
        get { self[UsageDisplayModeKey.self] }
        set { self[UsageDisplayModeKey.self] = newValue }
    }
}

/// Selects the compact bar's reading without changing provider data or alerts.
enum NotchQuota: String, CaseIterable, Identifiable {
    case automatic, session, weekly
    static let key = "notchQuota"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: return "Automático"
        case .session: return "Sessão atual"
        case .weekly: return "Semanal / todos os modelos"
        }
    }
    func reading(from snapshot: ProviderSnapshot) -> ProviderSnapshot {
        guard self != .automatic, snapshot.kind != .localRuntime else { return snapshot }
        let weekly = snapshot.weeklyLimitWindow ?? snapshot.windows.first {
            $0.group == nil && abs(($0.duration ?? 0) - 7 * 24 * 3600) < 60
        }
        let window = self == .session ? snapshot.fiveHourWindow : weekly
        var result = snapshot
        result.headlineID = window?.id
        if window == nil { result.windows = [] }
        return result
    }
}
private struct NotchQuotaKey: EnvironmentKey {
    static let defaultValue: NotchQuota = .automatic
}
extension EnvironmentValues {
    var notchQuota: NotchQuota {
        get { self[NotchQuotaKey.self] }
        set { self[NotchQuotaKey.self] = newValue }
    }
}

enum NotchPresentation: String, CaseIterable, Identifiable {
    case minimal, compact, complete
    static let key = "notchPresentation"
    var id: String { rawValue }
    var title: String { self == .minimal ? "Mínimo" : self == .compact ? "Compacto" : "Completo" }
    var width: CGFloat { self == .minimal ? NotchLayout.ringDiameter : self == .compact ? 96 : 138 }
    var height: CGFloat { self == .minimal ? NotchLayout.cellExtent : self == .compact ? 96 : 152 }
}
private struct NotchPresentationKey: EnvironmentKey { static let defaultValue: NotchPresentation = .minimal }
private struct ReadingHealthKey: EnvironmentKey { static let defaultValue: [String: ReadingHealth] = [:] }
extension EnvironmentValues {
    var notchPresentation: NotchPresentation {
        get { self[NotchPresentationKey.self] }
        set { self[NotchPresentationKey.self] = newValue }
    }
    var readingHealth: [String: ReadingHealth] {
        get { self[ReadingHealthKey.self] }
        set { self[ReadingHealthKey.self] = newValue }
    }
}

import Foundation
import CryptoKit

/// Only measured aggregates are retained; never authentication or API-key data.
@MainActor
final class ConsumptionHistory: ObservableObject {
    struct Quota: Codable, Equatable {
        var label: String
        var minimum: Double
        var maximum: Double
        var latest: Double
        var resetsAt: Date?
    }
    struct Day: Codable, Identifiable, Equatable {
        var id: String { accountKey + ":" + day }
        var accountKey: String
        var providerID: String
        var day: String
        var observedAt: Date
        var quotas: [String: Quota] = [:]
        var tokens: Int?
        var inputTokens: Int?
        var outputTokens: Int?
        var costs: [String: Double] = [:]
        var displayQuotaIDs: [String] {
            quotas.keys.sorted().filter { id in
                // Older Claude readings stored the same Fable limit under both
                // names. Keep the archive intact and show one line when equal.
                id != "weekly_scoped" || quotas[id] != quotas["weekly_fable"]
            }
        }
    }
    struct Summary {
        let observedDays: Int
        let daysAtLimit: Int
        let highestObservedFraction: Double?
        let highestTokenDay: Day?
        let monthlyCosts: [String: [String: Double]]
        let costDays: [String: [String: Int]]
    }
    /// Missing readings remain unknown. Monetary totals never cross currencies.
    static func summarize(_ records: [Day]) -> Summary {
        let observed = records.filter { !$0.quotas.isEmpty }
        var costs: [String: [String: Double]] = [:]
        var coverage: [String: [String: Int]] = [:]
        for day in records {
            let month = String(day.day.prefix(7))
            for (currency, value) in day.costs where value.isFinite && value >= 0 {
                costs[month, default: [:]][currency, default: 0] += value
                coverage[month, default: [:]][currency, default: 0] += 1
            }
        }
        return Summary(
            observedDays: observed.count,
            daysAtLimit: observed.filter { $0.quotas.values.contains { $0.maximum >= 1 } }.count,
            highestObservedFraction: observed.flatMap { $0.quotas.values.map(\.maximum) }.max(),
            highestTokenDay: records.filter { $0.tokens != nil }.sorted {
                if $0.tokens == $1.tokens { return $0.day > $1.day }
                return $0.tokens! > $1.tokens!
            }.first,
            monthlyCosts: costs, costDays: coverage)
    }
    @Published private(set) var days: [Day] = []
    @Published private(set) var persistenceError: String?
    private let url: URL
    private let calendar: Calendar
    init(url: URL, calendar: Calendar = .current) {
        self.url = url; self.calendar = calendar
        if FileManager.default.fileExists(atPath: url.path) {
            do { days = try JSONDecoder().decode([Day].self, from: Data(contentsOf: url)) }
            catch { persistenceError = "Não foi possível ler o histórico. O arquivo existente foi preservado." }
        }
    }
    static var storageURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodeNotch Pessoal/consumption-history.json")
    }
    static func accountKey(providerID: String, email: String?) -> String {
        let service = ClaudeProfile.isClaude(providerID: providerID) ? "claude" : CodexProfile.isCodex(providerID: providerID) ? "codex" : providerID
        let identity = email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? providerID
        return SHA256.hash(data: Data((service + ":" + identity).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func record(_ snapshot: ProviderSnapshot, email: String?, at now: Date) {
        guard persistenceError == nil, snapshot.kind == .usage, snapshot.hasReading else { return }
        let key = Self.accountKey(providerID: snapshot.providerID, email: email)
        let dayKey = CodexTokenUsage.dayKey(for: now, calendar: calendar)
        var today = days.first { $0.accountKey == key && $0.day == dayKey }
            ?? Day(accountKey: key, providerID: snapshot.providerID, day: dayKey, observedAt: now)
        today.observedAt = now
        for window in snapshot.windows {
            guard let value = window.usedFraction, value.isFinite else { continue }
            let prior = today.quotas[window.id]
            today.quotas[window.id] = Quota(label: window.label, minimum: min(prior?.minimum ?? value, value),
                maximum: max(prior?.maximum ?? value, value), latest: value, resetsAt: window.resetsAt)
        }
        upsert(today)
        // Daily buckets are cumulative totals. Replace a day's reading; never add
        // the same cumulative response again on each poll.
        for bucket in snapshot.tokenUsage?.dailyUsageBuckets ?? [] where bucket.tokens >= 0 {
            var day = days.first { $0.accountKey == key && $0.day == bucket.startDate }
                ?? Day(accountKey: key, providerID: snapshot.providerID, day: bucket.startDate, observedAt: now)
            day.tokens = bucket.tokens; day.observedAt = now
            upsert(day)
        }
        if let detail = snapshot.usageDetail {
            var daily: [String: (input: Int, output: Int, cost: Double)] = [:]
            var sourceCalendar = Calendar(identifier: .gregorian)
            sourceCalendar.timeZone = TimeZone(secondsFromGMT: detail.timeZoneSeconds) ?? .gmt
            for group in detail.groups {
                for point in group.days {
                    let date = CodexTokenUsage.dayKey(for: point.date, calendar: sourceCalendar)
                    let old = daily[date] ?? (0, 0, 0)
                    daily[date] = (old.input + point.cacheHitTokens + point.cacheMissTokens,
                                   old.output + point.outputTokens, old.cost + point.cost)
                }
            }
            for (date, value) in daily {
                var day = days.first { $0.accountKey == key && $0.day == date }
                    ?? Day(accountKey: key, providerID: snapshot.providerID, day: date, observedAt: now)
                day.inputTokens = value.input; day.outputTokens = value.output
                day.tokens = value.input + value.output
                if value.cost.isFinite && value.cost >= 0 { day.costs[detail.currency] = value.cost }
                day.observedAt = now; upsert(day)
            }
        }
        let cutoff = CodexTokenUsage.dayKey(for: calendar.date(byAdding: .day, value: -180, to: now) ?? now, calendar: calendar)
        days.removeAll { $0.day < cutoff }
        persist()
    }
    private func upsert(_ day: Day) {
        if let i = days.firstIndex(where: { $0.id == day.id }) { days[i] = day }
        else { days.append(day) }
    }
    private func persist() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                   attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(days).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { persistenceError = "Não foi possível salvar o histórico local." }
    }
    func records(providerID: String, email: String?, since day: String) -> [Day] {
        let key = Self.accountKey(providerID: providerID, email: email)
        return days.filter { $0.accountKey == key && $0.day >= day }.sorted { $0.day < $1.day }
    }
}

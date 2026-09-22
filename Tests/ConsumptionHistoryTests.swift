import XCTest
@testable import Codenotch

@MainActor
final class ConsumptionHistoryTests: XCTestCase {
    func testDailyTokensReplaceInsteadOfAccumulatingAndSurviveRestart() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("history.json")
        let history = ConsumptionHistory(url: url)
        let now = Date()
        let day = CodexTokenUsage.dayKey(for: now, calendar: .current)
        let snapshot = ProviderSnapshot(id: "codex", displayName: "Example", glyph: .openai, fidelity: .official,
            status: .ok, windows: [LimitWindow(id: "weekly", label: "Week", usedFraction: 0.9)],
            headlineID: "weekly", tokenUsage: CodexTokenUsage(dailyUsageBuckets: [.init(startDate: day, tokens: 123)]))
        history.record(snapshot, email: "example@test.invalid", at: now)
        history.record(snapshot, email: "example@test.invalid", at: now)
        let reloaded = ConsumptionHistory(url: url)
        XCTAssertEqual(reloaded.days.count, 1)
        XCTAssertEqual(reloaded.days.first?.tokens, 123)
        XCTAssertEqual(reloaded.days.first?.quotas["weekly"]?.maximum, 0.9)
        XCTAssertFalse(String(data: try Data(contentsOf: url), encoding: .utf8)!.contains("example@test.invalid"))
        XCTAssertTrue(reloaded.records(providerID: "codex", email: "different@test.invalid", since: "").isEmpty)
    }
    func testHistorySummarySeparatesMissingDataCurrenciesAndMonths() {
        let records = [
            ConsumptionHistory.Day(accountKey: "a", providerID: "p", day: "2026-09-20", observedAt: Date(),
                quotas: ["weekly": .init(label: "Week", minimum: 0.1, maximum: 1, latest: 0.1)],
                tokens: 200, costs: ["USD": 12, "BRL": 50]),
            ConsumptionHistory.Day(accountKey: "a", providerID: "p", day: "2026-09-21", observedAt: Date(),
                tokens: 400, costs: ["USD": 3]),
            ConsumptionHistory.Day(accountKey: "a", providerID: "p", day: "2026-08-20", observedAt: Date(),
                costs: ["USD": 99])]
        let summary = ConsumptionHistory.summarize(records)
        XCTAssertEqual(summary.observedDays, 1)
        XCTAssertEqual(summary.daysAtLimit, 1)
        XCTAssertEqual(summary.highestObservedFraction, 1)
        XCTAssertEqual(summary.highestTokenDay?.day, "2026-09-21")
        XCTAssertEqual(summary.monthlyCosts["2026-09"], ["USD": 15, "BRL": 50])
        XCTAssertEqual(summary.monthlyCosts["2026-08"], ["USD": 99])
        XCTAssertEqual(summary.costDays["2026-09"], ["USD": 2, "BRL": 1])
        let empty = ConsumptionHistory.summarize([])
        XCTAssertNil(empty.highestTokenDay)
        XCTAssertNil(empty.highestObservedFraction)
        XCTAssertTrue(empty.monthlyCosts.isEmpty)
    }
    func testActiveCodexNeverUsesNicknameFromPreviousAccount() {
        let names = AccountNames.setting("Daiane", for: "codex", in: Data())
        XCTAssertEqual(AccountNames.name(for: "codex", fallback: "Codex", in: names, email: "juridico@example.invalid"), "Codex ativo · juridico@example.invalid")
        XCTAssertEqual(AccountNames.name(for: "codex", fallback: "Codex", in: names), "Codex · conta ativa")
        XCTAssertNotEqual(ConsumptionHistory.accountKey(providerID: "codex", email: "daiane@example.invalid"),
                          ConsumptionHistory.accountKey(providerID: "codex", email: "juridico@example.invalid"))
    }
    func testInvalidHistoryIsPreserved() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let original = Data("invalid".utf8)
        try original.write(to: url)
        let history = ConsumptionHistory(url: url)
        XCTAssertNotNil(history.persistenceError)
        history.record(Fixtures.snapshots()[0], email: nil, at: Date())
        XCTAssertEqual(try Data(contentsOf: url), original)
    }
    func testBudgetSeparatesCurrenciesPeriodsAndManualValues() throws {
        let records = [ConsumptionHistory.Day(accountKey: "a", providerID: "p", day: "2026-09-20", observedAt: Date(), costs: ["USD": 12, "BRL": 50]),
                       ConsumptionHistory.Day(accountKey: "a", providerID: "p", day: "2026-08-20", observedAt: Date(), costs: ["USD": 99])]
        var budget = SpendingBudget(limit: 20, currency: "USD", month: "2026-09")
        XCTAssertEqual(budget.spent(records: records), 12)
        budget.currency = "EUR"
        XCTAssertNil(budget.spent(records: records))
        budget.manualSpend = 7
        XCTAssertEqual(budget.spent(records: records), 7)
        let data = try SpendingBudget.save(budget, accountKey: "a", into: Data())
        XCTAssertEqual(SpendingBudget.budget(in: data, accountKey: "a", month: "2026-09"), budget)
        budget.limit = -.infinity
        XCTAssertThrowsError(try SpendingBudget.save(budget, accountKey: "a", into: data))
    }
    func testBudgetKeepsPriorMonthsAndRejectsInvalidCalendarMonth() throws {
        let september = SpendingBudget(limit: 200, currency: "BRL", manualSpend: 50, month: "2026-09")
        let legacy = try JSONEncoder().encode(["a": september])
        var october = SpendingBudget(limit: 300, currency: "BRL", month: "2026-10")
        let data = try SpendingBudget.save(october, accountKey: "a", into: legacy)
        XCTAssertEqual(SpendingBudget.budget(in: data, accountKey: "a", month: "2026-09"), september)
        XCTAssertEqual(SpendingBudget.budget(in: data, accountKey: "a", month: "2026-10"), october)
        XCTAssertNil(SpendingBudget.budget(in: data, accountKey: "a", month: "2026-11"))
        october.month = "2026-13"
        XCTAssertThrowsError(try SpendingBudget.save(october, accountKey: "a", into: data))
    }
    func testReadingHealthDistinguishesOfflineExpiredAndMismatch() {
        let date = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(ReadingHealth.failure(URLError(.notConnectedToInternet), measuredAt: date, now: Date()).state, .offline)
        XCTAssertEqual(ReadingHealth.failure(UsageProviderError.credentialExpired, measuredAt: date, now: Date()).state, .expired)
        XCTAssertEqual(ReadingHealth.failure(UsageProviderError.identityMismatch, measuredAt: date, now: Date()).state, .identityMismatch)
        XCTAssertEqual(ReadingHealth.failure(UsageProviderError.badResponse(status: 500), measuredAt: date, now: Date()).measuredAt, date)
    }
    func testSuccessfulFetchDoesNotMakeAnOldCacheOrMissingLimitCurrent() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var snapshot = Fixtures.snapshots()[0]
        snapshot.sourceUpdatedAt = now.addingTimeInterval(-3600)
        let cached = ReadingHealth.success(snapshot, now: now, staleAfter: 900)
        XCTAssertEqual(cached.state, .previous)
        XCTAssertEqual(cached.measuredAt, snapshot.sourceUpdatedAt)
        XCTAssertEqual(cached.attemptedAt, now)
        snapshot.sourceUpdatedAt = now
        XCTAssertEqual(ReadingHealth.success(snapshot, now: now, staleAfter: 900).state, .current)
        snapshot.status = .stale(since: now)
        XCTAssertEqual(ReadingHealth.success(snapshot, now: now, staleAfter: 900).state, .previous)
        snapshot.windows = []
        XCTAssertEqual(ReadingHealth.success(snapshot, now: now, staleAfter: 900).state, .unavailable)
        XCTAssertNil(ReadingHealth.success(snapshot, now: now, staleAfter: 900).measuredAt)
    }
    func testReadingAgesWithoutAnotherFetchAndPreservesFailureReason() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var snapshot = Fixtures.snapshots()[0]
        snapshot.sourceUpdatedAt = now.addingTimeInterval(-300)
        let health = ReadingHealth.success(snapshot, now: now, staleAfter: 900)
        XCTAssertEqual(health.at(now.addingTimeInterval(600)).state, .current)
        let aged = health.at(now.addingTimeInterval(601))
        XCTAssertEqual(aged.state, .previous)
        XCTAssertEqual(aged.measuredAt, snapshot.sourceUpdatedAt)
        XCTAssertEqual(aged.attemptedAt, now)
        let expired = ReadingHealth.failure(UsageProviderError.credentialExpired, measuredAt: now, now: now)
        XCTAssertEqual(expired.at(now.addingTimeInterval(3600)).state, .expired)
        let offline = ReadingHealth.failure(URLError(.notConnectedToInternet), measuredAt: now, now: now)
        XCTAssertEqual(offline.at(now.addingTimeInterval(3600)).state, .offline)
    }
    func testUnitsSurviveCodingWithoutBecomingPercentOrMoney() throws {
        let window = LimitWindow(id: "signatures", label: "Documents", remaining: 12, unit: .signatures)
        let decoded = try JSONDecoder().decode(LimitWindow.self, from: JSONEncoder().encode(window))
        XCTAssertEqual(decoded.unit, .signatures)
        XCTAssertEqual(decoded.remaining, 12)
        XCTAssertNil(decoded.usedFraction)
        XCTAssertNil(decoded.money)
    }
}

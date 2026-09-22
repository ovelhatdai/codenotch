import XCTest
@testable import Codenotch

@MainActor
final class NotchGroupingTests: XCTestCase {
    private func account(_ id: String, used: Double, status: ProviderStatus = .ok) -> ProviderSnapshot {
        ProviderSnapshot(id: id, displayName: id, glyph: id.hasPrefix("claude") ? .claude : .openai,
            fidelity: .official, status: status,
            windows: [LimitWindow(id: "session", label: "Sessão", usedFraction: 0.1, duration: 18000),
                      LimitWindow(id: "weekly_all", label: "Semana", usedFraction: used,
                        resetsAt: Date().addingTimeInterval(172800), duration: 604800)],
            headlineID: "session", weeklyID: "weekly_all")
    }
    func testGroupsDoNotInventAnAggregateQuotaOrMixAccounts() {
        let source = [account("claude-a", used: 0.2), account("codex-b", used: 0.8), account("claude-c", used: 0.6)]
        let grouped = NotchGrouping.services.apply(to: source, quota: .weekly)
        XCTAssertEqual(grouped.map(\.id), ["account-group:claude", "account-group:codex"])
        XCTAssertNil(grouped[0].headline)
        XCTAssertEqual(grouped[0].windows.map(\.usedFraction), [0.2, 0.6])
        XCTAssertEqual(grouped[1].windows.map(\.usedFraction), [0.8])
        XCTAssertEqual(source.count, 3)
    }
    func testFiltersRetainStableIdentitiesAndOtherProvidersRemainUngrouped() {
        let source = [account("claude-a", used: 0.2), account("codex-b", used: 0.8), account("other", used: 0.6)]
        XCTAssertEqual(NotchGrouping.claude.apply(to: source, quota: .session).map(\.id), ["claude-a"])
        XCTAssertEqual(NotchGrouping.codex.apply(to: source, quota: .session).map(\.id), ["codex-b"])
        XCTAssertEqual(NotchGrouping.services.apply(to: source, quota: .session).last?.id, "other")
        XCTAssertEqual(NotchGrouping.accounts.apply(to: source, quota: .session), source)
    }
    func testIndividualAccountsStayTogetherByServiceWithoutLosingTheirOrder() {
        let source = [account("claude-a", used: 0.2), account("codex-mentoria", used: 0.29),
                      account("claude-b", used: 0.6), account("codex-juridico", used: 0.24)]
        let ordered = NotchGrouping.accounts.apply(to: source, quota: .weekly)
        XCTAssertEqual(ordered.map(\.id), ["claude-a", "claude-b", "codex-mentoria", "codex-juridico"])
        XCTAssertEqual(ordered[2].weeklyLimitWindow?.usedFraction, 0.29)
        XCTAssertEqual(NotchGrouping.accounts.apply(to: ordered, quota: .weekly), ordered)
    }
    func testExpiredAndMissingReadingsNeverBecomeZeroConsumption() {
        var missing = account("claude-b", used: 0.7)
        missing.windows = []
        let grouped = NotchGrouping.services.apply(to: [account("claude-a", used: 0.2, status: .needsAuth), missing], quota: .weekly)
        XCTAssertNil(grouped[0].windows[0].usedFraction)
        XCTAssertNil(grouped[0].windows[1].usedFraction)
        XCTAssertNotNil(grouped[0].windows[0].detail)
    }
    func testWeeklySelectionKeepsWeeklyQuotaWithDailyPaceEnabled() {
        let raw = account("claude-a", used: 0.65)
        let paced = DailyPace.apply(to: raw, now: Date())
        XCTAssertEqual(paced.weeklyID, "session")
        XCTAssertEqual(NotchQuota.weekly.reading(from: paced).usedFraction, 0.65)
        XCTAssertEqual(NotchQuota.session.reading(from: paced).usedFraction, 0.1)
    }
    func testGroupingPreferenceSurvivesRelaunch() {
        let name = "NotchGroupingTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        XCTAssertEqual(preferences.notchGrouping, .accounts)
        preferences.notchGrouping = .services
        XCTAssertEqual(Preferences(defaults: defaults).notchGrouping, .services)
    }
}

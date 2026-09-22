import XCTest
@testable import Codenotch

final class UsageDisplayModeTests: XCTestCase {
    private func snapshot(_ fraction: Double?) -> ProviderSnapshot {
        ProviderSnapshot(id: "claude", displayName: "Claude", glyph: .claude,
                         fidelity: .official, status: .ok,
                         windows: fraction.map { [LimitWindow(id: "session", label: "Session", usedFraction: $0)] } ?? [],
                         headlineID: "session")
    }

    func testAvailableCountsDownWithoutChangingTheSourceReading() {
        let reading = snapshot(0.09)
        XCTAssertEqual(UsageDisplayMode.used.text(for: reading), "9%")
        XCTAssertEqual(UsageDisplayMode.available.text(for: reading), "91%")
        XCTAssertEqual(UsageDisplayMode.available.fraction(for: 0.09), 0.91, accuracy: 0.0001)
        XCTAssertEqual(reading.usedFraction, 0.09)
        XCTAssertEqual(UsageDisplayMode.available.text(for: snapshot(0)), "100%")
        XCTAssertEqual(UsageDisplayMode.available.text(for: snapshot(1)), "0%")
    }

    func testMissingReadingIsNotAFullAllowance() {
        XCTAssertEqual(UsageDisplayMode.available.text(for: snapshot(nil)), "—")
    }

    func testAvailableUsesTheSameRoundingAsTheDetailCard() {
        XCTAssertEqual(UsageDisplayMode.available.text(for: snapshot(0.095)), "90%")
        XCTAssertEqual(UsageDisplayMode.available.fraction(for: 1.2), 0)
        XCTAssertEqual(UsageDisplayMode.available.fraction(for: -0.2), 1)
    }
    func testAccountAliasesStayIsolatedAndCanBeRestored() {
        var data = AccountNames.setting("  Mentoria  ", for: "claude-mentoria", in: Data())
        data = AccountNames.setting("Jurídico", for: "codex-juridico", in: data)
        XCTAssertEqual(AccountNames.name(for: "claude-mentoria", fallback: "Claude", in: data), "Mentoria")
        XCTAssertEqual(AccountNames.name(for: "codex-mentoria", fallback: "Codex", in: data), "Codex")
        data = AccountNames.setting("  ", for: "claude-mentoria", in: data)
        XCTAssertEqual(AccountNames.name(for: "claude-mentoria", fallback: "Claude", in: data), "Claude")
        XCTAssertEqual(AccountNames.name(for: "codex-juridico", fallback: "Codex", in: data), "Jurídico")
    }

    @MainActor
    func testClaudeAuthorizationAcceptsOnlyOfficialAuthorizationLinks() {
        XCTAssertNil(ClaudeAccountLogin.authorizationURL(in: "https://example.test/oauth/authorize?code=test"))
        XCTAssertNil(ClaudeAccountLogin.authorizationURL(in: "https://claude.ai.example.test/oauth/authorize"))
        XCTAssertNil(ClaudeAccountLogin.authorizationURL(in: "https://claude.ai/settings"))
        XCTAssertEqual(ClaudeAccountLogin.authorizationURL(in: "Open https://claude.ai/oauth/authorize?state=test")?.host, "claude.ai")
    }

    func testLinkedAccountsPersistSeparateDirectoriesWithoutCredentialContents() throws {
        let suite = "LinkedAccountsTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = LinkedClaudeAccount(id: "first", name: "Personal", email: "first@example.test", directory: URL(fileURLWithPath: "/tmp/profile-first"))
        let second = LinkedClaudeAccount(id: "second", name: "Work", email: "second@example.test", directory: URL(fileURLWithPath: "/tmp/profile-second"))
        try first.save(defaults: defaults); try second.save(defaults: defaults)
        let loaded = LinkedClaudeAccount.load(defaults: defaults)
        XCTAssertEqual(loaded.map(\.email), ["first@example.test", "second@example.test"])
        XCTAssertNotEqual(loaded[0].profile.keychainServices, loaded[1].profile.keychainServices)
        XCTAssertEqual(loaded[0].profile.configDirectory, first.directory)
        try first.save(defaults: defaults)
        XCTAssertEqual(LinkedClaudeAccount.load(defaults: defaults).count, 2)
    }

    @MainActor
    func testPlainDragHasAToleranceForOrdinaryClicks() {
        XCTAssertFalse(NotchPanel.startsPlainDrag(dx: 2, dy: 2))
        XCTAssertTrue(NotchPanel.startsPlainDrag(dx: -5, dy: 0))
        XCTAssertTrue(NotchPanel.startsPlainDrag(dx: 0, dy: 5))
    }

    func testWeeklySelectionUsesAllModelsWithoutMutatingSession() {
        var source = snapshot(0.08)
        source.windows.append(LimitWindow(id: "weekly", label: "All models", usedFraction: 0.82))
        source.weeklyID = "weekly"
        let selected = NotchQuota.weekly.reading(from: source)
        XCTAssertEqual(UsageDisplayMode.available.text(for: selected), "18%")
        XCTAssertEqual(selected.ringFraction, 0.82)
        XCTAssertNil(selected.weeklyFraction)
        XCTAssertEqual(source.usedFraction, 0.08)
        XCTAssertEqual(NotchQuota.automatic.reading(from: source), source)
    }
    func testUnavailableSelectedLimitDoesNotFallBackToAnotherNumber() {
        XCTAssertEqual(UsageDisplayMode.available.text(for: NotchQuota.weekly.reading(from: snapshot(0.08))), "—")
    }

    func testCodexWeeklyPrimaryIsSelectedWithoutASecondaryWindow() {
        var source = snapshot(0.19)
        source.windows = [LimitWindow(id: "primary", label: "Weekly", usedFraction: 0.19, duration: 604800)]
        source.headlineID = "primary"
        source.weeklyID = "secondary"
        XCTAssertEqual(UsageDisplayMode.available.text(for: NotchQuota.weekly.reading(from: source)), "81%")
        XCTAssertEqual(UsageDisplayMode.available.text(for: NotchQuota.session.reading(from: source)), "—")
    }

}

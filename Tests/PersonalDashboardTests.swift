import AppKit
import XCTest
@testable import Codenotch

@MainActor
final class PersonalDashboardTests: XCTestCase {
    func testClosingDashboardReleasesViewTreeAndWindow() {
        let suite = "dashboard-lifetime-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = UsageDashboardController(defaults: defaults)
        weak var releasedView: NSView?
        autoreleasepool {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
                                 styleMask: [.titled], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            let view = NSView()
            releasedView = view
            panel.contentView = view
            controller.window = panel
            controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: panel))
            XCTAssertNil(panel.contentView)
            XCTAssertNil(controller.window)
        }
        XCTAssertNil(releasedView, "A closed dashboard must not retain its UI tree")
    }

    func testGridNeverLeavesAThreePlusOneRowForFourAccounts() {
        XCTAssertEqual(UsageDashboard.columnCount(width: 380), 1)
        XCTAssertEqual(UsageDashboard.columnCount(width: 900), 2)
        XCTAssertEqual(UsageDashboard.columnCount(width: 1300), 4)
    }
    func testDisconnectedMonitorFrameReturnsInsideVisibleScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1080, height: 1920)
        let recovered = UsageDashboardController.visibleFrame(CGRect(x: 6000, y: -500, width: 1300, height: 700), on: screen)
        XCTAssertTrue(screen.contains(recovered))
        XCTAssertEqual(recovered.width, 1080)
        XCTAssertEqual(recovered.height, 700)
    }
    func testAllBarPresentationsGrowGeometryConsistently() {
        for edge in NotchEdge.allCases {
            for presentation in NotchPresentation.allCases {
                let along = NotchLayout.cellAlong(for: edge, presentation: presentation)
                let first = NotchLayout.ringCenter(index: 0, edge: edge, presentation: presentation)
                let second = NotchLayout.ringCenter(index: 1, edge: edge, presentation: presentation)
                XCTAssertEqual(second - first, along + NotchLayout.cellSpacing, accuracy: 0.001)
                XCTAssertGreaterThan(NotchLayout.bodyDepth(for: edge, presentation: presentation), edge.isVertical ? presentation.width : presentation.height)
            }
        }
    }
    func testCodexDeviceFlowOnlyAcceptsOfficialHostAndCode() {
        XCTAssertNotNil(ClaudeAccountLogin.authorizationURL(in: "https://auth.openai.com/codex/device", service: .codex))
        XCTAssertNil(ClaudeAccountLogin.authorizationURL(in: "https://auth.openai.com.example.test/codex/device", service: .codex))
        XCTAssertEqual(ClaudeAccountLogin.deviceCode(in: "Code: ABCD-12345"), "ABCD-12345")
        XCTAssertEqual(ClaudeAccountLogin.deviceCode(in: "  \u{1B}[94mABCD-12345\u{1B}[0m\n"), "ABCD-12345")
        XCTAssertNil(ClaudeAccountLogin.deviceCode(in: "\u{1B}[94mhttps://auth.openai.com/codex/device\u{1B}[0m"))
    }
    func testDuplicateIdentityIsScopedToTheServiceNotThePersonGroup() {
        let account = ProviderAccount(label: "same@example.test", plan: nil, source: "test", manageURL: nil)
        let summaries = [
            ProviderSummary(id: "claude", name: "Person", glyph: .claude, account: account, signIn: .guidance("")),
            ProviderSummary(id: "codex", name: "Person", glyph: .openai, account: account, signIn: .guidance("")),
            ProviderSummary(id: "codex-work", name: "Another nickname", glyph: .openai, account: account, signIn: .guidance(""))
        ]
        XCTAssertEqual(LinkedAccount.matches(email: "SAME@example.test ", service: .claude, summaries: summaries), ["claude"])
        XCTAssertEqual(LinkedAccount.matches(email: "same@example.test", service: .codex, summaries: summaries), ["codex", "codex-work"])
    }
    func testDashboardReceivesLiveActivityWithoutMixingProfiles() {
        let fleet = NotchFleet(scope: .mainDisplay, edge: .top)
        let claude = AgentSession(id: "task-a", name: "Working", detail: "test", state: .busy,
                                  waitingFor: nil, since: Date())
        let codex = AgentSession(id: "task-b", name: "Waiting", detail: "test", state: .waiting,
                                 waitingFor: "approval", since: Date())
        fleet.setSessions(providerID: "claude-juridico", sessions: [claude])
        fleet.setSessions(providerID: "codex-daiane", sessions: [codex])
        let dashboardModel = fleet.menuModel
        XCTAssertEqual(dashboardModel.activity(for: "claude-juridico")?.state, .working)
        XCTAssertEqual(dashboardModel.activity(for: "codex-daiane")?.state, .waiting)
        XCTAssertNil(dashboardModel.activity(for: "claude-daiane"))
        fleet.setSessions(providerID: "claude-juridico", sessions: [])
        XCTAssertNil(dashboardModel.activity(for: "claude-juridico"))
        XCTAssertEqual(dashboardModel.activity(for: "codex-daiane")?.sessions, [codex])
    }

    func testDashboardReceivesEveryAlertKindEvenWithNoVisibleNotch() {
        let fleet = NotchFleet(scope: .mainDisplay, edge: .top)
        for kind in [UsageAlertKind.reset, .sessionLimitReached, .weeklyLimitReached] {
            let event = alert(kind)
            XCTAssertFalse(fleet.showResetAlert(event, duration: 5))
            XCTAssertEqual(fleet.menuModel.activeResetAlert, event)
            fleet.menuModel.dismissDashboardAlert()
            XCTAssertNil(fleet.menuModel.activeResetAlert)
        }
    }

    func testNewAlertCannotBeDismissedByPreviousTimeout() async throws {
        let model = NotchViewModel()
        let event = alert(.reset)
        model.showDashboardAlert(event, duration: 0.03)
        model.showDashboardAlert(event, duration: 0.25)
        try await Task.sleep(nanoseconds: 90_000_000)
        XCTAssertEqual(model.activeResetAlert, event)
        try await Task.sleep(nanoseconds: 230_000_000)
        XCTAssertNil(model.activeResetAlert)
    }

    func testDashboardDailyPaceMatchesBarAndPreservesExplicitWeeklyChoice() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let reset = now.addingTimeInterval(5 * 86_400)
        let claude = ProviderSnapshot(id: "claude-juridico", displayName: "Test", glyph: .claude,
            fidelity: .official, status: .ok, windows: [
                LimitWindow(id: "session", label: "Session", usedFraction: 0.1, duration: 5 * 3600),
                LimitWindow(id: "weekly_all", label: "Week", usedFraction: 0.3, resetsAt: reset, duration: 7 * 86_400)
            ], headlineID: "session", weeklyID: "weekly_all")
        let bar = DailyPace.apply(to: [claude], enabled: true, now: now)
        let dashboard = UsageDashboard.readings([claude], dailyPace: true, now: now)
        XCTAssertEqual(dashboard, bar)
        let paced = try XCTUnwrap(dashboard.first)
        XCTAssertEqual(paced.headlineID, DailyPace.windowID)
        XCTAssertEqual(try XCTUnwrap(paced.usedFraction), 0.7, accuracy: 0.0001)
        XCTAssertEqual(paced.weeklyWindow?.id, "session")
        XCTAssertEqual(NotchQuota.weekly.reading(from: paced).usedFraction, 0.3)
        XCTAssertEqual(NotchQuota.session.reading(from: paced).usedFraction, 0.1)
        XCTAssertEqual(UsageDashboard.readings([claude], dailyPace: false, now: now), [claude])
    }

    private func alert(_ kind: UsageAlertKind) -> UsageAlertEvent {
        UsageAlertEvent(kind: kind, providerID: "claude-juridico", providerName: "Test",
            windowLabel: "Week", glyph: .claude, previousFraction: 0.99,
            currentFraction: kind == .reset ? 0 : 1, resetsAt: Date().addingTimeInterval(3600))
    }

}

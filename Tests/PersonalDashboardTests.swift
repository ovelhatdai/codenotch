import XCTest
@testable import Codenotch

@MainActor
final class PersonalDashboardTests: XCTestCase {
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
}

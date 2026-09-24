import XCTest
import SwiftUI
@testable import Codenotch

@MainActor
final class DashboardFitLayoutTests: XCTestCase {
    func testDashboardRendersEightDemoAccountsInPortrait() async throws {
        let previousLocale = L10n.testLocale
        L10n.testLocale = Locale(identifier: "pt-BR")
        defer { L10n.testLocale = previousLocale }
        let suite = "dashboard-preview-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "dashboardFitWindow")
        defaults.set("available", forKey: UsageDisplayMode.key)
        let providers = (0..<8).map { DashboardDemoProvider(index: $0) }
        let store = UsageStore(providers: providers, archive: UsageArchive(defaults: defaults))
        defer { store.stop() }
        await store.refresh()
        XCTAssertEqual(store.notchSnapshots.count, 8)
        let preferences = Preferences(defaults: defaults)
        let model = NotchViewModel()
        let view = UsageDashboard(store: store, preferences: preferences, liveModel: model, moveTo: { _ in }, stayOnTop: { _ in })
            .defaultAppStorage(defaults)
            .frame(width: 1440, height: 2400)
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 2400), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hosting
        defer { window.contentView = nil; window.close() }
        hosting.frame = NSRect(x: 0, y: 0, width: 1440, height: 2400)
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        XCTAssertEqual(hosting.bounds.size, CGSize(width: 1440, height: 2400))
        if let path = ProcessInfo.processInfo.environment["DASHBOARD_RENDER_PATH"] {
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
        }
    }

    func testPortraitAndLandscapeFitAllEightWithoutScroll() {
        for size in [CGSize(width: 1010, height: 1600), CGSize(width: 1500, height: 780)] {
            let plan = DashboardFitLayout(size: size, count: 8)
            XCTAssertEqual(plan.pageCount, 1)
            XCTAssertEqual(plan.range(page: 0, count: 8), 0..<8)
        }
    }
    func testWidePortraitUsesFourReadableRowsWithoutOversizedCards() {
        let plan = DashboardFitLayout(size: CGSize(width: 1440, height: 2400), count: 8)
        XCTAssertEqual(plan.columns, 2)
        XCTAssertEqual(plan.capacity, 8)
        XCTAssertEqual(plan.pageCount, 1)
        XCTAssertEqual(plan.cardHeight, 340)
        XCTAssertEqual(plan.contentScale, 1)
        XCTAssertLessThanOrEqual(plan.cardHeight * 4 + 3 * 12 + 36, 2400)
        let landscape = DashboardFitLayout(size: CGSize(width: 1440, height: 800), count: 8)
        XCTAssertEqual(landscape.columns, 4)
        XCTAssertEqual(landscape.pageCount, 1)
    }
    func testCompactListPaginatesWithoutLosingAccounts() {
        for size in [CGSize(width: 1080, height: 1700), CGSize(width: 380, height: 580)] {
            let plan = DashboardFitLayout(size: size, count: 8, compact: true)
            XCTAssertEqual(plan.columns, 1)
            XCTAssertLessThanOrEqual(plan.cardHeight, 136)
            XCTAssertEqual((0..<plan.pageCount).flatMap { Array(plan.range(page: $0, count: 8)) }, Array(0..<8))
        }
    }
    func testAlmostSquareWindowKeepsTwoReadableColumns() {
        let plan = DashboardFitLayout(size: CGSize(width: 1080, height: 1000), count: 8)
        XCTAssertEqual(plan.columns, 2)
        XCTAssertEqual((0..<plan.pageCount).flatMap { Array(plan.range(page: $0, count: 8)) }, Array(0..<8))
    }

    func testPortraitToLandscapeResizingPreservesEveryAccount() {
        for size in [CGSize(width: 1080, height: 1700), CGSize(width: 1440, height: 2400),
                     CGSize(width: 1400, height: 700), CGSize(width: 800, height: 900)] {
            let plan = DashboardFitLayout(size: size, count: 8)
            XCTAssertEqual((0..<plan.pageCount).flatMap { Array(plan.range(page: $0, count: 8)) }, Array(0..<8))
        }
    }

    func testSmallWindowsPaginateWithoutDroppingOrRepeatingAccounts() {
        let plan = DashboardFitLayout(size: CGSize(width: 340, height: 290), count: 8)
        XCTAssertEqual(plan.columns, 1)
        XCTAssertEqual(plan.capacity, 1)
        XCTAssertGreaterThanOrEqual(plan.cardHeight, 232)
        XCTAssertEqual((0..<plan.pageCount).flatMap { Array(plan.range(page: $0, count: 8)) }, Array(0..<8))
    }
    func testEmptyAndTemporaryZeroGeometryAreSafe() {
        let plan = DashboardFitLayout(size: .zero, count: 0)
        XCTAssertEqual(plan.pageCount, 1)
        XCTAssertTrue(plan.range(page: 0, count: 0).isEmpty)
    }
    func testDragUsesGlobalCoordinatesOnNegativeOriginMonitor() {
        let screen = CGRect(x: -1080, y: -200, width: 1080, height: 1920)
        let center = CGPoint(x: screen.midX, y: screen.midY)
        XCTAssertEqual(NotchWindowController.dragOffset(at: center, screen: screen, edge: .top), 0)
        XCTAssertEqual(NotchWindowController.dragOffset(at: CGPoint(x: center.x + 100, y: center.y - 150), screen: screen, edge: .left), 150)
        XCTAssertEqual(NotchWindowController.dragOffset(at: CGPoint(x: center.x + 100, y: center.y - 150), screen: screen, edge: .top), 100)
    }
}

private struct DashboardDemoProvider: UsageProvider {
    let index: Int
    var id: String { "demo-\(index)" }
    var displayName: String { "Conta de exemplo \(index % 4 + 1)" }
    var glyph: ProviderGlyph { index < 4 ? .claude : .openai }
    func fetchSnapshot() async throws -> ProviderSnapshot {
        ProviderSnapshot(id: id, displayName: displayName, glyph: glyph, fidelity: .manual, status: .ok,
            windows: [LimitWindow(id: "weekly", label: "Limite semanal", usedFraction: Double(index + 1) / 10, resetsAt: Date().addingTimeInterval(86400)),
                      LimitWindow(id: "session", label: "Sessão atual", usedFraction: 0.05, resetsAt: Date().addingTimeInterval(7200))],
            headlineID: "weekly", resetCredits: CodexResetCredits(availableCount: 1))
    }
}

import XCTest
@testable import Codenotch

final class PersonalEditionTests: XCTestCase {
    func testMigrationCopiesOnlyPresentationAndNeverOverwritesChoices() {
        let suite = "PersonalEditionTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("used", forKey: "usageDisplayMode")
        PersonalEdition.importAppearance(from: ["usageDisplayMode": "available", "notchQuota": "weekly",
            "accessToken": "secret", "linkedClaudeAccounts": Data([1]), "lastGoodReadings": Data([2]),
            "SUAutomaticallyUpdate": true], into: defaults)
        XCTAssertEqual(defaults.string(forKey: "usageDisplayMode"), "used")
        XCTAssertEqual(defaults.string(forKey: "notchQuota"), "weekly")
        for key in ["accessToken", "linkedClaudeAccounts", "lastGoodReadings", "SUAutomaticallyUpdate"] {
            XCTAssertNil(defaults.object(forKey: key))
        }
        PersonalEdition.importAppearance(from: ["notchEdge": "left"], into: defaults)
        XCTAssertNil(defaults.object(forKey: "notchEdge"))
    }

    @MainActor
    func testPersonalEditionCannotStartUpstreamUpdates() {
        XCTAssertTrue(PersonalEdition.isEnabled)
        let updater = Updater()
        updater.automatic = true
        updater.start()
        updater.checkNow()
        XCTAssertFalse(updater.automatic)
        XCTAssertNil(updater.lastChecked)
        XCTAssertEqual(updater.outcome, .idle)
    }
}

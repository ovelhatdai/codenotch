import XCTest
@testable import Codenotch

final class ClaudeResetAvailabilityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private func read(_ json: String) -> ClaudeResetAvailability.Reading {
        ClaudeResetAvailability.read(Data(json.utf8), now: now)
    }
    func testSurfaceRestrictionDoesNotReportZero() {
        let reading = read(#"{"cedar_ember":{"eligible":false,"ineligible_reason":"surface","grants":[]}}"#)
        XCTAssertNil(reading.credits)
        XCTAssertNotNil(reading.explanation)
    }
    func testConfirmedNoGrantIsZeroButMissingIsUnknown() {
        XCTAssertEqual(read(#"{"cedar_ember":{"eligible":false,"ineligible_reason":"no_grant"}}"#).credits?.availableCount, 0)
        for json in ["{}", #"{"cedar_ember":null}"#, #"{"cedar_ember":{"eligible":true}}"#] {
            XCTAssertNil(read(json).credits)
        }
    }
    func testCountsRemainingResetsNotNumberOfGrantsAndExcludesExpiredFuturePaused() {
        let result = read(#"{"cedar_ember":{"eligible":true,"grants":[{"id":"a","resets_left":3,"ends_at":"2027-01-01T00:00:00Z"},{"id":"b","resets_left":2,"ends_at":"2026-12-01T00:00:00.000Z"},{"id":"expired","resets_left":20,"ends_at":"2020-01-01T00:00:00Z"},{"id":"future","resets_left":20,"starts_at":"2030-01-01T00:00:00Z"},{"id":"paused","resets_left":20,"paused":true}]}}"#)
        XCTAssertEqual(result.credits?.availableCount, 5)
        XCTAssertEqual(result.credits?.available.count, 2)
        XCTAssertEqual(result.credits?.nextExpiry, ISO8601DateFormatter().date(from: "2026-12-01T00:00:00Z"))
    }
    func testMalformedGrantsNeverBecomeFalseAvailability() {
        for grants in [#"[{"id":"a","resets_left":-1}]"#, #"[{"id":"a","resets_left":1,"ends_at":"unknown"}]"#, #"[{"id":"a","resets_left":1},{"id":"a","resets_left":1}]"#] {
            XCTAssertNil(read("{\"cedar_ember\":{\"eligible\":true,\"grants\":" + grants + "}}").credits)
        }
    }
    func testAccountsHaveIndependentReadings() {
        XCTAssertEqual(read(#"{"cedar_ember":{"eligible":true,"grants":[{"id":"same","resets_left":2}]}}"#).credits?.availableCount, 2)
        XCTAssertEqual(read(#"{"cedar_ember":{"eligible":true,"grants":[{"id":"same","resets_left":0}]}}"#).credits?.availableCount, 0)
    }
}

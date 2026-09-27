import XCTest
@testable import Trueframe

final class SessionAnnouncementsTests: XCTestCase {

    func testCapturing_isOneQuietWord() {
        XCTAssertEqual(SessionAnnouncements.capturing, "capturing")
    }
}

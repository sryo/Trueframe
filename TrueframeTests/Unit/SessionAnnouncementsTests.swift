import XCTest
@testable import Trueframe

final class SessionAnnouncementsTests: XCTestCase {

    func testCapturing_isOneQuietWord() {
        XCTAssertEqual(SessionAnnouncements.capturing, "capturing")
    }
}

final class KeptAnnouncementTests: XCTestCase {

    func testKept_one_isSingular() {
        XCTAssertEqual(SessionAnnouncements.kept(1), "1 photo kept")
    }

    func testKept_many_isPlural() {
        XCTAssertEqual(SessionAnnouncements.kept(4), "4 photos kept")
        XCTAssertEqual(SessionAnnouncements.kept(50), "50 photos kept")
    }

    func testKept_none_isPlural() {
        XCTAssertEqual(SessionAnnouncements.kept(0), "0 photos kept")
    }
}

// Authorization gating for LibrarySaver.

import Photos
import XCTest
@testable import Trueframe

final class LibrarySaverTests: XCTestCase {

    private let items = [LibrarySaver.Item(data: Data([0xFF, 0xD8, 0xFF]), isProxy: false, capturedAt: Date())]

    func testSave_withoutAddAccess_savesNothing() async {
        for status in [PHAuthorizationStatus.notDetermined, .denied, .restricted] {
            let saver = LibrarySaver(authorizationStatus: { status })

            let saved = await saver.save(items)

            XCTAssertEqual(saved, 0, "Status \(status.rawValue) should not reach the photo library")
        }
    }

    func testSave_emptyBatch_savesNothing() async {
        let saver = LibrarySaver(authorizationStatus: { .authorized })

        let saved = await saver.save([])

        XCTAssertEqual(saved, 0)
    }
}

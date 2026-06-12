// Unit tests for SessionStore.

import XCTest
@testable import Trueframe

final class SessionStoreTests: XCTestCase {

    var sut: SessionStore!

    override func setUp() async throws {
        try await super.setUp()
        sut = SessionStore()
        await sut.clearSession()
    }

    override func tearDown() async throws {
        await sut.clearSession()
        sut = nil
        try await super.tearDown()
    }

    func testEmptyStore_hasNoEntries() async {
        let count = await sut.count
        XCTAssertEqual(count, 0)
        let previews = await sut.previews
        XCTAssertTrue(previews.isEmpty)
    }

    func testAdd_storesEntryAndPreview() async {
        let asset = FakeCaptureEngine.makeAsset()

        await sut.add(asset)

        let count = await sut.count
        XCTAssertEqual(count, 1)
        let previews = await sut.previews
        XCTAssertEqual(previews.count, 1)
    }

    func testAdd_preservesOrder() async {
        let first = FakeCaptureEngine.makeAsset()
        let second = FakeCaptureEngine.makeAsset()

        await sut.add(first)
        await sut.add(second)

        let entries = await sut.allEntries()
        XCTAssertEqual(entries.map(\.id), [first.id, second.id])
    }

    func testFileData_roundTripsUntouched() async {
        let asset = FakeCaptureEngine.makeAsset()

        await sut.add(asset)

        let data = await sut.fileData(for: asset.id)
        XCTAssertEqual(data, asset.fileData, "Stored data must be byte-identical (no re-encoding)")
    }

    func testFileData_unknownID_returnsNil() async {
        let data = await sut.fileData(for: UUID())
        XCTAssertNil(data)
    }

    func testClearSession_removesEverything() async {
        let asset = FakeCaptureEngine.makeAsset()
        await sut.add(asset)

        await sut.clearSession()

        let count = await sut.count
        XCTAssertEqual(count, 0)
        let data = await sut.fileData(for: asset.id)
        XCTAssertNil(data, "Backing file should be deleted")
    }

    func testEntry_carriesProxyFlagAndDate() async {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let asset = CapturedAsset(
            id: UUID(),
            fileData: Data([0x01]),
            preview: nil,
            isProxy: true,
            capturedAt: date
        )

        await sut.add(asset)

        let entries = await sut.allEntries()
        XCTAssertEqual(entries.first?.isProxy, true)
        XCTAssertEqual(entries.first?.capturedAt, date)
    }
}

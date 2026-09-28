import XCTest
@testable import Trueframe

final class SessionStoreTests: XCTestCase {

    private var directory: URL!
    private var sut: SessionStore!

    override func setUp() async throws {
        try await super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        sut = SessionStore(directory: directory)
    }

    override func tearDown() async throws {
        sut = nil
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        try await super.tearDown()
    }

    private func storedFiles() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    }

    func testEmptyStore_hasNoEntries() async {
        let count = await sut.count
        XCTAssertEqual(count, 0)
        let previews = await sut.allEntries().compactMap(\.preview)
        XCTAssertTrue(previews.isEmpty)
    }

    func testAdd_storesEntryAndPreview() async {
        let asset = FakeCaptureEngine.makeAsset()

        await sut.add(asset)

        let count = await sut.count
        XCTAssertEqual(count, 1)
        let previews = await sut.allEntries().compactMap(\.preview)
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

    func testAdd_writesIntoInjectedDirectory() async {
        let asset = FakeCaptureEngine.makeAsset()

        await sut.add(asset)

        XCTAssertEqual(storedFiles(), ["\(asset.id.uuidString).photo"])
    }

    func testClearSession_emptiesInjectedDirectory() async {
        await sut.add(FakeCaptureEngine.makeAsset())

        await sut.clearSession()

        XCTAssertTrue(storedFiles().isEmpty)
    }

    func testDetachSession_forgetsEntriesButKeepsTheirFiles() async {
        let asset = FakeCaptureEngine.makeAsset()
        await sut.add(asset)

        await sut.detachSession()

        let count = await sut.count
        XCTAssertEqual(count, 0)
        let data = await sut.fileData(for: asset.id)
        XCTAssertEqual(data, asset.fileData)
    }

    func testClearSession_afterDetach_leavesDetachedFilesAlone() async {
        let detached = FakeCaptureEngine.makeAsset()
        await sut.add(detached)
        await sut.detachSession()
        await sut.add(FakeCaptureEngine.makeAsset())

        await sut.clearSession()

        XCTAssertEqual(storedFiles(), ["\(detached.id.uuidString).photo"])
    }

    func testRemoveFiles_deletesOnlyTheNamedFiles() async {
        let gone = FakeCaptureEngine.makeAsset()
        let kept = FakeCaptureEngine.makeAsset()
        await sut.add(gone)
        await sut.add(kept)
        await sut.detachSession()

        await sut.removeFiles(for: [gone.id])

        XCTAssertEqual(storedFiles(), ["\(kept.id.uuidString).photo"])
    }
}

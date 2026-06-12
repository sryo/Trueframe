// Phase transition tests for SessionCoordinator, run against a fake engine.

import XCTest
@testable import Trueframe

@MainActor
final class SessionCoordinatorTests: XCTestCase {

    var engine: FakeCaptureEngine!
    var sut: SessionCoordinator!

    override func setUp() async throws {
        try await super.setUp()
        engine = FakeCaptureEngine()
        sut = SessionCoordinator(engine: engine, requestPermissions: { true })
        await sut.start()
    }

    override func tearDown() async throws {
        engine = nil
        sut = nil
        TestDefaults.clear()
        try await super.tearDown()
    }

    /// Polls until the condition holds or the timeout passes.
    private func waitUntil(
        timeout: TimeInterval = 2.0,
        _ condition: @MainActor () async -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while await !condition() && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private func waitForStoredPhotos(_ count: Int) async {
        await waitUntil { await self.sut.store.count >= count }
    }

    // MARK: - Begin Session

    func testInitialPhase_isIdle() {
        XCTAssertEqual(sut.phase, .idle)
    }

    func testBeginSession_fromIdle_entersCapturing() async {
        sut.beginSession()

        XCTAssertEqual(sut.phase, .capturing)
        await waitUntil { self.engine.startCallCount == 1 }
        XCTAssertEqual(engine.startCallCount, 1)
    }

    func testBeginSession_whileCapturing_isIgnored() async {
        sut.beginSession()
        await waitUntil { self.engine.startCallCount == 1 }

        sut.beginSession()
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(engine.startCallCount, 1, "Second begin should be a no-op")
    }

    func testBeginSession_withoutPermissions_staysIdle() async {
        let denied = SessionCoordinator(engine: FakeCaptureEngine(), requestPermissions: { false })
        await denied.start()

        denied.beginSession()

        XCTAssertEqual(denied.phase, .idle)
    }

    func testBeginSession_snapshotsConfiguration() async {
        sut.captureSettings.captureInterval = 2.0
        sut.cameraSelectionSettings.select(.telephoto)

        sut.beginSession()
        await waitUntil { self.engine.startCallCount == 1 }

        XCTAssertEqual(engine.lastConfiguration?.interval, 2.0)
        XCTAssertEqual(engine.lastConfiguration?.lens, .telephoto)
    }

    // MARK: - End Session

    func testEndSession_withPhotos_entersCelebrating() async {
        sut.beginSession()
        await waitUntil { self.engine.startCallCount == 1 }

        engine.emitCapturedPhoto()
        await waitForStoredPhotos(1)

        await sut.endSession()

        XCTAssertEqual(sut.phase, .celebrating)
        XCTAssertFalse(sut.sessionPreviews.isEmpty)
        XCTAssertEqual(engine.stopCallCount, 1)
    }

    func testEndSession_withoutPhotos_returnsToIdle() async {
        sut.beginSession()
        await waitUntil { self.engine.startCallCount == 1 }

        await sut.endSession()
        await waitUntil { self.sut.phase == .idle }

        XCTAssertEqual(sut.phase, .idle)
        XCTAssertTrue(sut.sessionPreviews.isEmpty)
    }

    func testEndSession_whenIdle_isIgnored() async {
        await sut.endSession()

        XCTAssertEqual(sut.phase, .idle)
        XCTAssertEqual(engine.stopCallCount, 0)
    }

    // MARK: - Dark Frame Abort

    func testThreeConsecutiveDarkFrames_endSession() async {
        sut.beginSession()
        await waitUntil { self.engine.startCallCount == 1 }

        for _ in 0..<CurationPolicy.maxConsecutiveDarkFrames {
            engine.emitCapturedPhoto(brightness: 0.01)
        }

        await waitUntil { self.sut.phase == .idle }
        XCTAssertEqual(sut.phase, .idle, "Dark-frame abort with no real photos should reset to idle")
        XCTAssertEqual(engine.stopCallCount, 1)
    }

    func testDarkFrameCounter_resetsOnBrightFrame() async {
        sut.beginSession()
        await waitUntil { self.engine.startCallCount == 1 }

        engine.emitCapturedPhoto(brightness: 0.01)
        engine.emitCapturedPhoto(brightness: 0.01)
        engine.emitCapturedPhoto(brightness: 0.8)  // resets the counter
        engine.emitCapturedPhoto(brightness: 0.01)
        engine.emitCapturedPhoto(brightness: 0.01)

        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(sut.phase, .capturing, "Session should survive interleaved dark frames")
    }

    // MARK: - Photo Limit

    func testMaxPhotoCount_endsSession() async {
        sut.beginSession()
        await waitUntil { self.engine.startCallCount == 1 }

        for _ in 0..<CurationPolicy.maxPhotosPerSession {
            engine.emitCapturedPhoto()
        }

        await waitUntil { self.sut.phase == .celebrating }
        XCTAssertEqual(sut.phase, .celebrating)
        XCTAssertEqual(engine.stopCallCount, 1)
    }

    // MARK: - Tumble Completion

    func testTumbleAnimationComplete_whenNotCelebrating_isIgnored() {
        sut.tumbleAnimationComplete()

        XCTAssertEqual(sut.phase, .idle)
    }

    func testTumbleAnimationComplete_savesAndReturnsToIdle() async {
        sut.beginSession()
        await waitUntil { self.engine.startCallCount == 1 }
        engine.emitCapturedPhoto()
        await waitForStoredPhotos(1)
        await sut.endSession()
        XCTAssertEqual(sut.phase, .celebrating)

        sut.tumbleAnimationComplete()
        XCTAssertEqual(sut.phase, .saving)

        // Saving runs scoring + a photo-library write that fails without
        // authorization in the test host; either way it must land on idle.
        await waitUntil(timeout: 10) { self.sut.phase == .idle }
        XCTAssertEqual(sut.phase, .idle)
        XCTAssertTrue(sut.sessionPreviews.isEmpty)
    }

    // MARK: - Prewarm

    func testReturnToIdle_prewarmsEngine() async {
        let prewarmsAfterStart = engine.prewarmCallCount

        sut.beginSession()
        await waitUntil { self.engine.startCallCount == 1 }
        await sut.endSession()  // no photos -> straight to idle

        await waitUntil { self.engine.prewarmCallCount > prewarmsAfterStart }
        XCTAssertGreaterThan(engine.prewarmCallCount, prewarmsAfterStart)
    }
}

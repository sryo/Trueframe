// Phase transition tests for SessionCoordinator, run against a fake engine.

import XCTest
@testable import Trueframe

@MainActor
final class SessionCoordinatorTests: XCTestCase {

    var engine: FakeCaptureEngine!
    var scorer: FakePhotoScorer!
    var saver: FakePhotoSaver!
    var haptics: FakeHeartbeat!
    var proximity: FakeProximitySource!
    var sut: SessionCoordinator!

    override func setUp() async throws {
        try await super.setUp()
        engine = FakeCaptureEngine()
        scorer = FakePhotoScorer()
        saver = FakePhotoSaver()
        haptics = FakeHeartbeat()
        proximity = FakeProximitySource()
        sut = makeCoordinator()
        await sut.start()
    }

    override func tearDown() async throws {
        engine = nil
        scorer = nil
        saver = nil
        haptics = nil
        proximity = nil
        sut = nil
        TestDefaults.clear()
        try await super.tearDown()
    }

    private func makeCoordinator(
        requestPermissions: @escaping @Sendable () async -> Bool = { true }
    ) -> SessionCoordinator {
        SessionCoordinator(
            engine: engine,
            requestPermissions: requestPermissions,
            scorer: scorer,
            saver: saver,
            haptics: haptics,
            proximity: proximity
        )
    }

    /// Polls until the condition holds, failing the test if it never does.
    /// Only for effects of the engine's event stream, which has no handle to await.
    private func waitUntil(
        timeout: TimeInterval = 2.0,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @MainActor () async -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while await !condition() {
            guard Date() < deadline else {
                XCTFail("Condition not met within \(timeout)s", file: file, line: line)
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
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
        let denied = makeCoordinator(requestPermissions: { false })
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

        XCTAssertEqual(sut.phase, .idle)
        XCTAssertTrue(sut.sessionPreviews.isEmpty)
    }

    func testEndSession_whenIdle_isIgnored() async {
        await sut.endSession()

        XCTAssertEqual(sut.phase, .idle)
        XCTAssertEqual(engine.stopCallCount, 0)
    }

    func testEndSession_keepsCapturesDrainedByStop() async {
        engine.eventsDrainedOnStop = [.captured(FakeCaptureEngine.makeAsset())]
        sut.beginSession()
        await waitUntil { self.engine.startCallCount == 1 }
        engine.emitCapturedPhoto()
        await waitForStoredPhotos(1)

        await sut.endSession()

        XCTAssertEqual(sut.phase, .celebrating)
        XCTAssertEqual(sut.sessionPreviews.count, 2)
    }

    func testEndSession_drainedCaptureAloneStillCelebrates() async {
        engine.eventsDrainedOnStop = [.captured(FakeCaptureEngine.makeAsset())]
        sut.beginSession()
        await waitUntil { self.engine.startCallCount == 1 }

        await sut.endSession()

        XCTAssertEqual(sut.phase, .celebrating)
        XCTAssertEqual(sut.sessionPreviews.count, 1)
    }

    func testAutoEnd_keepsCapturesDrainedByStop() async {
        engine.eventsDrainedOnStop = [.captured(FakeCaptureEngine.makeAsset())]
        sut.beginSession()
        await waitUntil { self.engine.startCallCount == 1 }

        for _ in 0..<CurationPolicy.maxPhotosPerSession {
            engine.emitCapturedPhoto()
        }

        await waitUntil { self.sut.phase == .celebrating }
        XCTAssertEqual(sut.sessionPreviews.count, CurationPolicy.maxPhotosPerSession + 1)
    }

    func testEngineFinishingStream_endsSession() async {
        sut.beginSession()
        await waitUntil { self.engine.startCallCount == 1 }
        engine.emitCapturedPhoto()
        await waitForStoredPhotos(1)

        engine.finishStream()

        await waitUntil { self.sut.phase == .celebrating }
        XCTAssertEqual(haptics.endCount, 1)
    }

    func testEngineFailingToStart_returnsToIdle() async {
        engine.finishesStreamOnStart = true
        sut.beginSession()
        XCTAssertEqual(sut.phase, .capturing)
        await waitUntil { self.engine.startCallCount == 1 }

        await waitUntil { self.sut.phase == .idle }
        XCTAssertEqual(haptics.endCount, 1)
    }

    func testEndSession_whilePreparingHaptics_endsHapticsAfterPrepare() async {
        haptics.holdsPrepare = true
        sut.beginSession()
        await waitUntil { self.haptics.prepareCount == 1 }

        let ending = Task { await sut.endSession() }
        await Task.yield()
        haptics.releasePrepare()
        await ending.value
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertFalse(haptics.isPrepared, "Haptic engine left running after the session ended")
        XCTAssertEqual(sut.phase, .idle)
    }

    func testEndSession_whileEngineStarting_leavesEngineStopped() async {
        engine.holdsStart = true
        sut.beginSession()
        await waitUntil { self.engine.startCallCount == 1 }

        let ending = Task { await sut.endSession() }
        await Task.yield()
        engine.releaseStart()
        await waitUntil { self.sut.phase == .idle }

        XCTAssertFalse(engine.isRunning, "Camera kept capturing after the lift")
        engine.finishStream()
        await ending.value
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

    // MARK: - Capture Count

    func testCapturedCount_countsKeptPhotosButNotDarkFrames() async {
        sut.beginSession()
        await waitUntil { self.engine.startCallCount == 1 }
        XCTAssertEqual(sut.capturedCount, 0)

        engine.emitCapturedPhoto()
        engine.emitCapturedPhoto(brightness: 0.0)
        engine.emitCapturedPhoto()
        await waitForStoredPhotos(2)
        await waitUntil { self.sut.capturedCount >= 2 }
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(sut.capturedCount, 2)
    }

    func testCapturedCount_resetsWhenTheNextSessionBegins() async {
        sut.beginSession()
        await waitUntil { self.engine.startCallCount == 1 }
        engine.emitCapturedPhoto()
        await waitForStoredPhotos(1)
        await sut.endSession()
        sut.tumbleAnimationComplete()
        await sut.saveTask?.value
        XCTAssertEqual(sut.capturedCount, 1)

        sut.beginSession()

        XCTAssertEqual(sut.capturedCount, 0)
        await sut.endSession()
    }

    // MARK: - Tumble Completion

    func testTumbleAnimationComplete_whenNotCelebrating_isIgnored() {
        sut.tumbleAnimationComplete()

        XCTAssertEqual(sut.phase, .idle)
    }

    func testTumbleAnimationComplete_savesCuratedPhotosAndReturnsToIdle() async throws {
        await scorer.setScores([0.9, 0.1])
        let keeper = FakeCaptureEngine.makeAsset(fileData: Data([0x01]))
        let reject = FakeCaptureEngine.makeAsset(fileData: Data([0x02]))

        sut.beginSession()
        await waitUntil { self.engine.startCallCount == 1 }
        engine.emit(.captured(keeper))
        engine.emit(.captured(reject))
        await waitForStoredPhotos(2)
        await sut.endSession()
        XCTAssertEqual(sut.phase, .celebrating)

        sut.tumbleAnimationComplete()
        XCTAssertEqual(sut.phase, .saving)

        let saveTask = try XCTUnwrap(sut.saveTask)
        await saveTask.value
        await sut.libraryWrite?.value

        XCTAssertEqual(sut.phase, .idle)
        XCTAssertTrue(sut.sessionPreviews.isEmpty)
        let batches = await saver.savedBatches
        XCTAssertEqual(batches.count, 1)
        XCTAssertEqual(batches.first?.map(\.data), [keeper.fileData])
    }

    func testTumbleAnimationComplete_withHungLibraryWrite_stillReturnsToIdle() async throws {
        await saver.holdSaves()
        sut.beginSession()
        await waitUntil { self.engine.startCallCount == 1 }
        engine.emitCapturedPhoto()
        await waitForStoredPhotos(1)
        await sut.endSession()

        sut.tumbleAnimationComplete()
        await waitUntil { self.sut.phase == .idle }

        XCTAssertEqual(sut.phase, .idle)
        await waitUntil { await self.saver.savedBatches.first?.count == 1 }
        await saver.releaseSaves()
        await sut.libraryWrite?.value
    }

    private func endSessionWithPhotos(_ assets: [CapturedAsset]) async {
        sut.beginSession()
        await waitUntil { self.engine.startCallCount == 1 }
        for asset in assets { engine.emit(.captured(asset)) }
        await waitForStoredPhotos(assets.count)
        await sut.endSession()
    }

    func testVerdict_isPublishedWhileTheAnimationPlays() async {
        await scorer.setScores([0.9, 0.1, 0.5])
        await endSessionWithPhotos((0..<3).map { _ in FakeCaptureEngine.makeAsset() })

        await waitUntil { self.sut.keptPreviews != nil }

        XCTAssertEqual(sut.phase, .celebrating)
        XCTAssertEqual(sut.keptPreviews, [true, false, true])
    }

    func testVerdict_isUnknownUntilScoringAnswers() async {
        await scorer.holdScores()
        await endSessionWithPhotos([FakeCaptureEngine.makeAsset()])
        await waitUntil { await self.scorer.callCount == 1 }

        XCTAssertEqual(sut.phase, .celebrating)
        XCTAssertNil(sut.keptPreviews)

        await scorer.releaseScores()
        await waitUntil { self.sut.keptPreviews == [true] }
    }

    func testVerdict_linesUpWithThePreviewsShown() async {
        await scorer.setScores([0.9, 0.9, 0.1])
        let unseen = CapturedAsset(id: UUID(), fileData: Data([0x01]), preview: nil, isProxy: false, capturedAt: .now)
        await endSessionWithPhotos([FakeCaptureEngine.makeAsset(), unseen, FakeCaptureEngine.makeAsset()])

        await waitUntil { self.sut.keptPreviews != nil }

        XCTAssertEqual(sut.sessionPreviews.count, 2)
        XCTAssertEqual(sut.keptPreviews, [true, false])
    }

    func testSaving_usesTheVerdictTheAnimationShowed() async throws {
        await scorer.setScores([0.9, 0.1])
        let keeper = FakeCaptureEngine.makeAsset(fileData: Data([0x01]))
        let reject = FakeCaptureEngine.makeAsset(fileData: Data([0x02]))
        await endSessionWithPhotos([keeper, reject])
        await waitUntil { self.sut.keptPreviews != nil }
        // A second pass would now pick the other photo
        await scorer.setScores([0.1, 0.9])

        sut.tumbleAnimationComplete()
        await sut.saveTask?.value
        await sut.libraryWrite?.value

        let batches = await saver.savedBatches
        XCTAssertEqual(batches.first?.map(\.data), [keeper.fileData])
        XCTAssertEqual(sut.keptCount, 1)
    }

    func testScoring_runsOncePerSession() async {
        await endSessionWithPhotos([FakeCaptureEngine.makeAsset(), FakeCaptureEngine.makeAsset()])
        await waitUntil { self.sut.keptPreviews != nil }

        sut.tumbleAnimationComplete()
        await sut.saveTask?.value

        let calls = await scorer.callCount
        XCTAssertEqual(calls, 1)
    }

    func testSlowScorer_savingWaitsForTheVerdict() async {
        await scorer.setScores([0.1, 0.9])
        await scorer.holdScores()
        let reject = FakeCaptureEngine.makeAsset(fileData: Data([0x01]))
        let keeper = FakeCaptureEngine.makeAsset(fileData: Data([0x02]))
        await endSessionWithPhotos([reject, keeper])

        sut.tumbleAnimationComplete()
        XCTAssertEqual(sut.phase, .saving)
        await scorer.releaseScores()
        await sut.saveTask?.value
        await sut.libraryWrite?.value

        XCTAssertEqual(sut.phase, .idle)
        let batches = await saver.savedBatches
        XCTAssertEqual(batches.first?.map(\.data), [keeper.fileData])
        let calls = await scorer.callCount
        XCTAssertEqual(calls, 1)
    }

    func testVerdict_clearsWhenTheSessionIsOver() async {
        await endSessionWithPhotos([FakeCaptureEngine.makeAsset()])
        await waitUntil { self.sut.keptPreviews != nil }

        sut.tumbleAnimationComplete()
        await sut.saveTask?.value

        XCTAssertNil(sut.keptPreviews)
    }

    func testKeptCount_isUnknownUntilSavingHasSelected() async throws {
        await scorer.setScores([0.9, 0.1, 0.5])
        sut.beginSession()
        await waitUntil { self.engine.startCallCount == 1 }
        engine.emitCapturedPhoto()
        engine.emitCapturedPhoto()
        engine.emitCapturedPhoto()
        await waitForStoredPhotos(3)
        await sut.endSession()
        XCTAssertNil(sut.keptCount)

        sut.tumbleAnimationComplete()
        await sut.saveTask?.value

        XCTAssertEqual(sut.keptCount, 2)
        let batches = await saver.savedBatches
        XCTAssertEqual(batches.first?.count, 2)
    }

    func testKeptCount_clearsWhenTheNextSessionBegins() async {
        sut.beginSession()
        await waitUntil { self.engine.startCallCount == 1 }
        engine.emitCapturedPhoto()
        await waitForStoredPhotos(1)
        await sut.endSession()
        sut.tumbleAnimationComplete()
        await sut.saveTask?.value
        XCTAssertEqual(sut.keptCount, 1)

        sut.beginSession()

        XCTAssertNil(sut.keptCount)
        await sut.endSession()
    }

    // MARK: - Heartbeat

    func testHeartbeat_beatsOnContactAndBeforeEachCapture() async {
        sut.beginSession()
        await waitUntil { self.engine.startCallCount == 1 }

        XCTAssertEqual(haptics.prepareCount, 1)
        XCTAssertEqual(haptics.beatCount, 1, "One beat at contact, before any capture")

        engine.emit(.willCapture)
        engine.emit(.willCapture)
        await waitUntil { self.haptics.beatCount == 3 }

        await sut.endSession()
        XCTAssertEqual(haptics.endCount, 1)
    }

    // MARK: - Proximity

    func testProximity_coveringBeginsSessionAndClearingEndsIt() async {
        XCTAssertEqual(proximity.startCount, 1)

        proximity.send(covered: true)
        await waitUntil { self.engine.startCallCount == 1 }
        XCTAssertEqual(sut.phase, .capturing)

        proximity.send(covered: false)
        await waitUntil { self.sut.phase == .idle }
        XCTAssertEqual(engine.stopCallCount, 1)
    }

    func testStart_twice_consumesProximityOnce() async {
        await sut.start()

        XCTAssertEqual(proximity.startCount, 1)
    }

    func testStart_doesNotKeepCoordinatorAlive() async {
        proximity = FakeProximitySource()
        var coordinator: SessionCoordinator? = makeCoordinator()
        weak let released = coordinator
        await coordinator?.start()

        coordinator = nil

        XCTAssertNil(released)
    }

    func testStop_stopsProximityAndIgnoresLaterCovers() async {
        sut.stop()
        proximity.send(covered: true)
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(proximity.stopCount, 1)
        XCTAssertEqual(sut.phase, .idle)
        XCTAssertEqual(engine.startCallCount, 0)
    }

    // MARK: - Prewarm

    func testReturnToIdle_prewarmsEngine() async {
        let prewarmsAfterStart = engine.prewarmCallCount

        sut.beginSession()
        await waitUntil { self.engine.startCallCount == 1 }
        await sut.endSession()  // no photos -> straight to idle

        XCTAssertGreaterThan(engine.prewarmCallCount, prewarmsAfterStart)
    }
}

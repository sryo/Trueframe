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

    func testInitialPhase_isIdle() {
        XCTAssertEqual(sut.phase, .idle)
    }

    func testBeginSession_fromIdle_entersCapturing() async {
        sut.beginSession()

        XCTAssertEqual(sut.phase, .capturing)
        await waitUntil { self.engine.startCallCount == 1 }
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
        XCTAssertEqual(engine.stopCallCount, 1)
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

    func testThreeConsecutiveDarkFrames_endSession() async {
        sut.beginSession()
        await waitUntil { self.engine.startCallCount == 1 }

        for _ in 0..<CurationPolicy.maxConsecutiveDarkFrames {
            engine.emitCapturedPhoto(brightness: 0.01)
        }

        // With no real photos, the abort goes straight back to idle
        await waitUntil { self.sut.phase == .idle }
        XCTAssertEqual(engine.stopCallCount, 1)
    }

    func testDarkFrameCounter_resetsOnBrightFrame() async {
        sut.beginSession()
        await waitUntil { self.engine.startCallCount == 1 }

        engine.emitCapturedPhoto(brightness: 0.01)
        engine.emitCapturedPhoto(brightness: 0.01)
        engine.emitCapturedPhoto(brightness: 0.8)
        engine.emitCapturedPhoto(brightness: 0.01)
        engine.emitCapturedPhoto(brightness: 0.01)
        engine.emitCapturedPhoto(brightness: 0.8)

        await waitForStoredPhotos(2)
        XCTAssertEqual(sut.phase, .capturing, "Session should survive interleaved dark frames")
    }

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
        sut.celebrationHandedOff()
        await sut.saveTask?.value
        XCTAssertEqual(sut.capturedCount, 1)

        sut.beginSession()

        XCTAssertEqual(sut.capturedCount, 0)
        await sut.endSession()
    }

    func testCelebrationHandedOff_whenNotCelebrating_isIgnored() {
        sut.celebrationHandedOff()

        XCTAssertEqual(sut.phase, .idle)
    }

    func testCelebrationHandedOff_savesCuratedPhotosAndReturnsToIdle() async throws {
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

        sut.celebrationHandedOff()
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

    func testCelebrationHandedOff_withHungLibraryWrite_stillReturnsToIdle() async throws {
        await saver.holdSaves()
        sut.beginSession()
        await waitUntil { self.engine.startCallCount == 1 }
        engine.emitCapturedPhoto()
        await waitForStoredPhotos(1)
        await sut.endSession()

        sut.celebrationHandedOff()
        await waitUntil { self.sut.phase == .idle }

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

        await waitUntil { self.sut.verdict != nil }

        XCTAssertEqual(sut.phase, .celebrating)
        XCTAssertEqual(sut.verdict?.kept, [true, false, true])
    }

    func testVerdict_publishesTheScoresOfThePreviewsShown() async {
        await scorer.setScores([0.9, 0.3, 0.1])
        let unseen = CapturedAsset(id: UUID(), fileData: Data([0x01]), preview: nil, isProxy: false, capturedAt: .now)
        await endSessionWithPhotos([FakeCaptureEngine.makeAsset(), unseen, FakeCaptureEngine.makeAsset()])

        await waitUntil { self.sut.verdict != nil }

        XCTAssertEqual(sut.verdict?.scores, [0.9, 0.1])
        XCTAssertEqual(sut.verdict?.kept, [true, false])
    }

    func testVerdict_isUnknownUntilScoringAnswers() async {
        await scorer.holdScores()
        await endSessionWithPhotos([FakeCaptureEngine.makeAsset()])
        await waitUntil { await self.scorer.callCount == 1 }

        XCTAssertEqual(sut.phase, .celebrating)
        XCTAssertNil(sut.verdict)

        await scorer.releaseScores()
        await waitUntil { self.sut.verdict?.kept == [true] }
    }

    func testVerdict_linesUpWithThePreviewsShown() async {
        await scorer.setScores([0.9, 0.9, 0.1])
        let unseen = CapturedAsset(id: UUID(), fileData: Data([0x01]), preview: nil, isProxy: false, capturedAt: .now)
        await endSessionWithPhotos([FakeCaptureEngine.makeAsset(), unseen, FakeCaptureEngine.makeAsset()])

        await waitUntil { self.sut.verdict != nil }

        XCTAssertEqual(sut.sessionPreviews.count, 2)
        XCTAssertEqual(sut.verdict?.kept, [true, false])
    }

    func testSaving_usesTheVerdictTheAnimationShowed() async throws {
        await scorer.setScores([0.9, 0.1])
        let keeper = FakeCaptureEngine.makeAsset(fileData: Data([0x01]))
        let reject = FakeCaptureEngine.makeAsset(fileData: Data([0x02]))
        await endSessionWithPhotos([keeper, reject])
        await waitUntil { self.sut.verdict != nil }
        // A second pass would now pick the other photo
        await scorer.setScores([0.1, 0.9])

        sut.celebrationHandedOff()
        await sut.saveTask?.value
        await sut.libraryWrite?.value

        let batches = await saver.savedBatches
        XCTAssertEqual(batches.first?.map(\.data), [keeper.fileData])
        XCTAssertEqual(sut.keptCount, 1)
    }

    func testScoring_runsOncePerSession() async {
        await endSessionWithPhotos([FakeCaptureEngine.makeAsset(), FakeCaptureEngine.makeAsset()])
        await waitUntil { self.sut.verdict != nil }

        sut.celebrationHandedOff()
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

        sut.celebrationHandedOff()
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
        await waitUntil { self.sut.verdict != nil }

        sut.celebrationHandedOff()
        await sut.saveTask?.value

        XCTAssertNil(sut.verdict)
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

        sut.celebrationHandedOff()
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
        sut.celebrationHandedOff()
        await sut.saveTask?.value
        XCTAssertEqual(sut.keptCount, 1)

        sut.beginSession()

        XCTAssertNil(sut.keptCount)
        await sut.endSession()
    }

    func testBeginSession_whileCelebrating_startsNewSessionAtOnce() async {
        await endSessionWithPhotos([FakeCaptureEngine.makeAsset()])
        XCTAssertEqual(sut.phase, .celebrating)
        sut.cameraSelectionSettings.select(.telephoto)
        let beatsBefore = haptics.beatCount

        sut.beginSession()

        XCTAssertEqual(sut.phase, .capturing)
        await waitUntil { self.engine.startCallCount == 2 }
        XCTAssertEqual(engine.lastConfiguration?.lens, .telephoto)
        XCTAssertEqual(haptics.beatCount, beatsBefore + 1, "One beat at contact")
        await sut.endSession()
    }

    func testBeginSession_whileSaving_startsNewSessionAtOnce() async {
        await scorer.holdScores()
        await endSessionWithPhotos([FakeCaptureEngine.makeAsset()])
        sut.celebrationHandedOff()
        XCTAssertEqual(sut.phase, .saving)

        sut.beginSession()

        XCTAssertEqual(sut.phase, .capturing)
        await waitUntil { self.engine.startCallCount == 2 }
        await scorer.releaseScores()
        await sut.saveTask?.value
        XCTAssertEqual(sut.phase, .capturing, "The old save must not send the new session home")
        await sut.endSession()
    }

    func testProximityCover_whileCelebrating_startsNewSession() async {
        await endSessionWithPhotos([FakeCaptureEngine.makeAsset()])

        proximity.send(covered: true)

        await waitUntil { self.engine.startCallCount == 2 }
        XCTAssertEqual(sut.phase, .capturing)
        await sut.endSession()
    }

    func testBeginSession_whileEnding_isIgnored() async {
        haptics.holdsPrepare = true
        sut.beginSession()
        await waitUntil { self.haptics.prepareCount == 1 }
        let ending = Task { await sut.endSession() }
        await waitUntil { self.sut.phase == .ending }

        sut.beginSession()

        XCTAssertEqual(sut.phase, .ending)
        haptics.releasePrepare()
        await ending.value
        XCTAssertEqual(haptics.prepareCount, 1)
    }

    func testInterruptedSession_savesItsOwnKeepersOnce() async throws {
        await scorer.setScores([0.9, 0.1])
        let keeper = FakeCaptureEngine.makeAsset(fileData: Data([0x01]))
        let reject = FakeCaptureEngine.makeAsset(fileData: Data([0x02]))
        await endSessionWithPhotos([keeper, reject])
        await waitUntil { self.sut.verdict != nil }

        sut.beginSession()
        let interruptedSave = try XCTUnwrap(sut.saveTask)
        await waitUntil { self.engine.startCallCount == 2 }
        let next = FakeCaptureEngine.makeAsset(fileData: Data([0x03]))
        engine.emit(.captured(next))
        await waitForStoredPhotos(1)
        await interruptedSave.value
        await sut.libraryWrite?.value

        var batches = await saver.savedBatches
        XCTAssertEqual(batches.map { $0.map(\.data) }, [[keeper.fileData]])

        await sut.endSession()
        sut.celebrationHandedOff()
        await sut.saveTask?.value
        await sut.libraryWrite?.value

        batches = await saver.savedBatches
        XCTAssertEqual(batches.map { $0.map(\.data) }, [[keeper.fileData], [next.fileData]])
    }

    func testInterruptedSession_withoutVerdict_finishesScoringInTheBackground() async throws {
        await scorer.setScores([0.1, 0.9])
        await scorer.holdScores()
        let reject = FakeCaptureEngine.makeAsset(fileData: Data([0x01]))
        let keeper = FakeCaptureEngine.makeAsset(fileData: Data([0x02]))
        await endSessionWithPhotos([reject, keeper])

        sut.beginSession()
        let interruptedSave = try XCTUnwrap(sut.saveTask)
        await waitUntil { self.engine.startCallCount == 2 }
        engine.emit(.captured(FakeCaptureEngine.makeAsset(fileData: Data([0x03]))))
        await waitForStoredPhotos(1)
        await scorer.releaseScores()
        await interruptedSave.value
        await sut.libraryWrite?.value

        let batches = await saver.savedBatches
        XCTAssertEqual(batches.map { $0.map(\.data) }, [[keeper.fileData]])
        let storedForNewSession = await sut.store.count
        XCTAssertEqual(storedForNewSession, 1, "The new session's capture must survive the old save")
        await sut.endSession()
    }

    func testInterruptedWhileSaving_savesOnceAndKeepsTheNewSession() async {
        await scorer.setScores([0.9])
        await scorer.holdScores()
        let keeper = FakeCaptureEngine.makeAsset(fileData: Data([0x01]))
        await endSessionWithPhotos([keeper])
        sut.celebrationHandedOff()
        let interruptedSave = sut.saveTask

        sut.beginSession()
        await waitUntil { self.engine.startCallCount == 2 }
        engine.emit(.captured(FakeCaptureEngine.makeAsset(fileData: Data([0x03]))))
        await waitForStoredPhotos(1)
        await scorer.releaseScores()
        await interruptedSave?.value
        await sut.libraryWrite?.value

        let batches = await saver.savedBatches
        XCTAssertEqual(batches.map { $0.map(\.data) }, [[keeper.fileData]])
        XCTAssertEqual(sut.phase, .capturing)
        let storedForNewSession = await sut.store.count
        XCTAssertEqual(storedForNewSession, 1)
        await sut.endSession()
    }

    func testInterruptedSession_removesItsFilesOnceSaved() async throws {
        let keeper = FakeCaptureEngine.makeAsset(fileData: Data([0x01]))
        await endSessionWithPhotos([keeper])

        sut.beginSession()
        await sut.saveTask?.value

        let leftover = await sut.store.fileData(for: keeper.id)
        XCTAssertNil(leftover)
        await sut.endSession()
    }

    func testInterruptedSession_skipsKeptAnnouncementSoItCannotCollideWithCapturing() async {
        await endSessionWithPhotos([FakeCaptureEngine.makeAsset()])

        sut.beginSession()
        await sut.saveTask?.value

        XCTAssertNil(sut.keptCount)
        await sut.endSession()
    }

    func testInterruption_resetsWhatTheScreensShowForTheNewSession() async {
        await scorer.holdScores()
        await endSessionWithPhotos([FakeCaptureEngine.makeAsset(), FakeCaptureEngine.makeAsset()])
        XCTAssertEqual(sut.capturedCount, 2)

        sut.beginSession()

        XCTAssertEqual(sut.capturedCount, 0)
        XCTAssertTrue(sut.sessionPreviews.isEmpty)
        XCTAssertNil(sut.verdict)
        XCTAssertNil(sut.keptCount)

        // The old verdict arriving late must not paint the new session
        await scorer.releaseScores()
        await sut.saveTask?.value
        XCTAssertNil(sut.verdict)
        await sut.endSession()
    }

    func testCelebrationHandedOff_afterInterruption_isIgnored() async {
        await endSessionWithPhotos([FakeCaptureEngine.makeAsset()])
        sut.beginSession()
        let interruptedSave = sut.saveTask

        sut.celebrationHandedOff()

        XCTAssertEqual(sut.phase, .capturing)
        XCTAssertTrue(sut.saveTask == interruptedSave, "No second save was started")
        await interruptedSave?.value
        await sut.libraryWrite?.value
        let batches = await saver.savedBatches
        XCTAssertEqual(batches.count, 1)
        await sut.endSession()
    }

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

    func testReturnToIdle_prewarmsEngine() async {
        let prewarmsAfterStart = engine.prewarmCallCount

        sut.beginSession()
        await waitUntil { self.engine.startCallCount == 1 }
        await sut.endSession()  // no photos -> straight to idle

        XCTAssertGreaterThan(engine.prewarmCallCount, prewarmsAfterStart)
    }
}

#if DEBUG
import XCTest
@testable import Trueframe

@MainActor
final class DemoSessionTests: XCTestCase {

    func testLaunchArgument() {
        XCTAssertEqual(DemoSession.launchArgument, "-demoSession")
    }

    func testEngine_yieldsABeatThenABrightPhotoEachInterval_andFinishesOnStop() async {
        let engine = DemoCaptureEngine()
        let configuration = CaptureConfiguration(lens: .wide, flashEnabled: false, interval: 0.05)
        var iterator = await engine.start(configuration).makeAsyncIterator()

        guard case .willCapture? = await iterator.next() else { return XCTFail("Expected a beat first") }
        guard case .captured(let asset)? = await iterator.next() else { return XCTFail("Expected a photo") }
        let preview = try? XCTUnwrap(asset.preview)
        XCTAssertEqual(preview?.isPitchBlack, false)

        await engine.stop()
        while let _ = await iterator.next() {}
    }

    func testProximity_coversThenUncoversOnSchedule() async {
        let source = DemoProximitySource(schedule: .init(firstCover: .zero, covered: .milliseconds(20), period: .milliseconds(60)))
        var iterator = source.events.makeAsyncIterator()
        source.start()

        let first = await iterator.next()
        let second = await iterator.next()
        let third = await iterator.next()
        source.stop()

        XCTAssertEqual([first, second, third], [true, false, true])
    }
}
#endif

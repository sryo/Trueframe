import XCTest
@testable import Trueframe

final class FanLayoutTests: XCTestCase {

    func testSlots_emptySessionHasNoSlots() {
        XCTAssertTrue(FanLayout.slots(count: 0).isEmpty)
    }

    func testSlots_neverMoreThanSeven() {
        XCTAssertEqual(FanLayout.maxPhotos, 7)
        XCTAssertEqual(FanLayout.slots(count: 12).count, 7)
    }

    func testSlots_spreadEvenlyFromMinusToPlusTwentyFiveDegrees() {
        let degrees = FanLayout.slots(count: 7).map(\.rotation.degrees)
        let expected = (0..<7).map { -25.0 + Double($0) * 50.0 / 6 }
        XCTAssertEqual(degrees.count, expected.count)
        for (actual, want) in zip(degrees, expected) {
            XCTAssertEqual(actual, want, accuracy: 1e-9)
        }
    }

    func testSlots_sitOnAnArcAroundAPivotBelowCenter() {
        for slot in FanLayout.slots(count: 7) {
            let fromPivot = CGSize(width: slot.offset.width, height: slot.offset.height - FanLayout.pivotDrop)
            XCTAssertEqual(hypot(fromPivot.width, fromPivot.height), FanLayout.radius, accuracy: 1e-9)
        }
        let middle = FanLayout.slots(count: 7)[3]
        XCTAssertEqual(middle.offset.width, 0, accuracy: 1e-9)
        XCTAssertEqual(middle.offset.height, 200 - 240, accuracy: 1e-9)
    }

    func testSlots_mirrorAcrossTheMiddle() {
        let slots = FanLayout.slots(count: 4)
        XCTAssertEqual(slots[0].offset.width, -slots[3].offset.width, accuracy: 1e-9)
        XCTAssertEqual(slots[0].offset.height, slots[3].offset.height, accuracy: 1e-9)
        XCTAssertEqual(slots[1].rotation.degrees, -slots[2].rotation.degrees, accuracy: 1e-9)
    }

    func testSlots_singlePhotoStandsUprightAtTheTop() {
        let slots = FanLayout.slots(count: 1)
        XCTAssertEqual(slots.count, 1)
        XCTAssertEqual(slots[0].rotation.degrees, 0)
        XCTAssertEqual(slots[0].offset.width, 0, accuracy: 1e-9)
        XCTAssertEqual(slots[0].offset.height, -40, accuracy: 1e-9)
    }

    func testDelay_staggersThirtyMillisecondsPerPhoto() {
        XCTAssertEqual(FanLayout.delay(for: 0), 0)
        XCTAssertEqual(FanLayout.delay(for: 4), 0.12, accuracy: 1e-9)
    }

    private func verdict(_ kept: [Bool], scores: [Float]? = nil) -> FanLayout.Verdict {
        FanLayout.Verdict(kept: kept, scores: scores ?? kept.map { _ in 0.5 })
    }

    func testPlan_withoutAVerdictSkipsTheFan() {
        XCTAssertEqual(FanLayout.plan(for: nil), .skip)
    }

    func testPlan_showsOnlyKeptPhotosInCaptureOrder() {
        XCTAssertEqual(FanLayout.plan(for: verdict([true, false, true, true, false])), .fan([0, 2, 3]))
    }

    func testPlan_neverShowsADroppedPhoto() {
        for mask in 1..<(1 << 10) {
            let kept = (0..<10).map { mask & (1 << $0) != 0 }
            guard case .fan(let shown) = FanLayout.plan(for: verdict(kept)) else {
                return XCTFail("A verdict with keepers should fan")
            }
            XCTAssertTrue(shown.allSatisfy { kept[$0] }, "\(kept)")
            XCTAssertEqual(shown, shown.sorted())
            XCTAssertEqual(shown.count, min(kept.filter { $0 }.count, FanLayout.maxPhotos))
        }
    }

    func testPlan_withNoKeptPreviewSkipsTheFan() {
        XCTAssertEqual(FanLayout.plan(for: verdict([false, false])), .skip)
    }

    func testPlan_capsAtSevenChoosingTheBestScoredInCaptureOrder() {
        let kept = Array(repeating: true, count: 10)
        let scores: [Float] = [0.5, 0.9, 0.4, 0.8, 0.95, 0.45, 0.7, 0.6, 0.41, 0.85]
        XCTAssertEqual(FanLayout.plan(for: verdict(kept, scores: scores)), .fan([0, 1, 3, 4, 6, 7, 9]))
    }

    func testPlan_capsAtSevenIgnoringTheScoresOfDroppedPhotos() {
        let kept = [true, false, true, true, true, true, true, true, true, true]
        let scores: [Float] = [0.5, 1.0, 0.4, 0.8, 0.95, 0.45, 0.7, 0.6, 0.41, 0.85]
        XCTAssertEqual(FanLayout.plan(for: verdict(kept, scores: scores)), .fan([0, 3, 4, 5, 6, 7, 9]))
    }

    func testPlan_capsAtTheFirstSevenKeptWhenScoresDontLineUp() {
        let kept = Array(repeating: true, count: 9)
        XCTAssertEqual(FanLayout.plan(for: FanLayout.Verdict(kept: kept, scores: [])), .fan(Array(0..<7)))
    }

    func testVerdictDeadline_givesScoringABeatAndAHalf() {
        XCTAssertEqual(FanLayout.verdictDeadline, .seconds(1.5))
    }

    @MainActor
    func testAwaitVerdict_returnsAsSoonAsItIsKnown() async {
        let start = ContinuousClock.now
        let known = verdict([true, false])
        let answer = await FanLayout.awaitVerdict(within: .seconds(2)) { known }
        XCTAssertEqual(answer, known)
        XCTAssertLessThan(ContinuousClock.now - start, .milliseconds(100))
    }

    @MainActor
    func testAwaitVerdict_givesUpAtTheDeadline() async {
        let start = ContinuousClock.now
        let answer = await FanLayout.awaitVerdict(within: .milliseconds(60)) { nil as FanLayout.Verdict? }
        XCTAssertNil(answer)
        XCTAssertGreaterThanOrEqual(ContinuousClock.now - start, .milliseconds(60))
        XCTAssertLessThan(ContinuousClock.now - start, .milliseconds(500))
    }
}

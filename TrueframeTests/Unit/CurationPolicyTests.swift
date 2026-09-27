// Unit tests for CurationPolicy selection rules.

import XCTest
@testable import Trueframe

final class CurationPolicyTests: XCTestCase {

    func testSelection_keepsEverythingAboveThreshold() {
        let scores: [Float] = [0.9, 0.5, 0.4, 0.39, 0.1]

        let selected = CurationPolicy.selectionIndices(scores: scores)

        XCTAssertEqual(selected, [0, 1, 2], "Scores at or above 0.4 should be kept")
    }

    func testSelection_nothingPasses_keepsSingleBest() {
        let scores: [Float] = [0.1, 0.35, 0.2]

        let selected = CurationPolicy.selectionIndices(scores: scores)

        XCTAssertEqual(selected, [1], "The single best photo should be kept when nothing passes")
    }

    func testSelection_emptyScores_returnsEmpty() {
        XCTAssertTrue(CurationPolicy.selectionIndices(scores: []).isEmpty)
    }

    func testSelection_allPass_keepsAll() {
        let scores: [Float] = [0.9, 0.8, 0.7]

        let selected = CurationPolicy.selectionIndices(scores: scores)

        XCTAssertEqual(selected, [0, 1, 2])
    }

    func testSelection_tieBelowThreshold_keepsEarliest() {
        let scores: [Float] = [0.1, 0.3, 0.3, 0.2]

        XCTAssertEqual(CurationPolicy.selectionIndices(scores: scores), [1])
    }

    func testSelection_singleScoreBelowThreshold_isKept() {
        XCTAssertEqual(CurationPolicy.selectionIndices(scores: [0.05]), [0])
    }

    func testSelection_exactlyAtThreshold_isKept() {
        let scores: [Float] = [0.1, CurationPolicy.qualityThreshold]

        XCTAssertEqual(CurationPolicy.selectionIndices(scores: scores), [1])
    }

    func testSelection_preservesCaptureOrder() {
        let scores: [Float] = [0.5, 0.9, 0.1, 0.7, 0.45]

        XCTAssertEqual(CurationPolicy.selectionIndices(scores: scores), [0, 1, 3, 4])
    }

    func testUnscorableScore_passesThreshold() {
        // Unscorable photos must fail open (be saved, not dropped)
        XCTAssertGreaterThanOrEqual(CurationPolicy.unscorableScore, CurationPolicy.qualityThreshold)
    }

    // MARK: - Pitch black

    func testIsPitchBlack_belowThreshold() {
        XCTAssertTrue(CurationPolicy.isPitchBlack(brightness: 0))
        XCTAssertTrue(CurationPolicy.isPitchBlack(brightness: 0.049))
    }

    func testIsPitchBlack_atThreshold_isNotBlack() {
        XCTAssertEqual(CurationPolicy.pitchBlackBrightness, 0.05)
        XCTAssertFalse(CurationPolicy.isPitchBlack(brightness: 0.05))
    }

    func testIsPitchBlack_aboveThreshold_isNotBlack() {
        XCTAssertFalse(CurationPolicy.isPitchBlack(brightness: 0.051))
        XCTAssertFalse(CurationPolicy.isPitchBlack(brightness: 1))
    }
}

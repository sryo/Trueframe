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

    func testUnscorableScore_passesThreshold() {
        // Unscorable photos must fail open (be saved, not dropped)
        XCTAssertGreaterThanOrEqual(CurationPolicy.unscorableScore, CurationPolicy.qualityThreshold)
    }
}

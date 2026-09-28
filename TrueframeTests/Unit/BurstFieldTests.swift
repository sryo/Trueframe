import XCTest
import UIKit
@testable import Trueframe

final class BurstFieldTests: XCTestCase {

    func testSparks_seventyWithinTheirRanges() {
        let sparks = BurstField.sparks
        XCTAssertEqual(sparks.count, 70)
        for spark in sparks {
            XCTAssertTrue((0..<(2 * .pi)).contains(spark.angle))
            XCTAssertTrue((160...520).contains(spark.speed))
            XCTAssertTrue((0.6...1.1).contains(spark.life))
            XCTAssertTrue((1...2.6).contains(spark.radius))
        }
        XCTAssertGreaterThan(Set(sparks.map(\.angle)).count, 60, "Directions should scatter")
    }

    func testSparks_areTheSameEveryTime() {
        XCTAssertEqual(BurstField.makeSparks(), BurstField.makeSparks())
        XCTAssertEqual(BurstField.makeSparks(), BurstField.sparks)
    }

    func testSparkPosition_startsAtTheHeartAndDecelerates() {
        let spark = BurstField.Spark(angle: 0, speed: 400, life: 1, radius: 2)
        XCTAssertEqual(BurstField.distance(of: spark, at: 0), 0)
        let d1 = BurstField.distance(of: spark, at: 0.25)
        let d2 = BurstField.distance(of: spark, at: 0.5)
        let d3 = BurstField.distance(of: spark, at: 0.75)
        XCTAssertGreaterThan(d1, 0)
        XCTAssertGreaterThan(d2, d1)
        XCTAssertLessThan(d3 - d2, d2 - d1, "Slows as it flies")
        XCTAssertEqual(BurstField.distance(of: spark, at: 1), 400 / 1.6, accuracy: 1e-9)
    }

    func testSparkPosition_followsItsDirection() {
        let spark = BurstField.Spark(angle: .pi / 2, speed: 200, life: 1, radius: 2)
        let p = BurstField.position(of: spark, at: 0.5, around: CGPoint(x: 10, y: 20))
        XCTAssertEqual(p.x, 10, accuracy: 1e-9)
        XCTAssertGreaterThan(p.y, 20)
    }

    func testSpark_shrinksToHalfAndFades() {
        let spark = BurstField.Spark(angle: 0, speed: 200, life: 1, radius: 2)
        XCTAssertEqual(BurstField.radius(of: spark, at: 0), 2)
        XCTAssertEqual(BurstField.radius(of: spark, at: 1), 1, accuracy: 1e-9)
        XCTAssertEqual(BurstField.opacity(of: spark, at: 0), 0, "Eases in over the first frames")
        XCTAssertEqual(BurstField.opacity(of: spark, at: 0.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(BurstField.opacity(of: spark, at: 1), 0)
        XCTAssertEqual(BurstField.opacity(of: spark, at: 2), 0)
    }

    func testGlow_briefAndSoft() {
        XCTAssertEqual(BurstField.glowOpacity(at: 0), 0.25, accuracy: 1e-9)
        XCTAssertEqual(BurstField.glowOpacity(at: 0.35), 0, accuracy: 1e-9)
        XCTAssertEqual(BurstField.glowOpacity(at: 1), 0)
    }

    func testRing_startsSmallAfterTheBurstAndReachesPastTheCorners() {
        let cover: CGFloat = 700
        XCTAssertNil(BurstField.ring(at: 0.1, cover: cover))
        let start = BurstField.ring(at: BurstField.ringDelay + 1e-9, cover: cover)
        XCTAssertEqual(start?.radius ?? 0, 2, accuracy: 1e-3)
        XCTAssertEqual(start?.opacity ?? 0, 0.4, accuracy: 1e-3)
        XCTAssertEqual(start?.lineWidth ?? 0, 2, accuracy: 1e-3)
        let end = BurstField.ring(at: BurstField.ringDelay + BurstField.ringTime - 1e-9, cover: cover)
        XCTAssertEqual(end?.radius ?? 0, 2 + 0.9 * cover, accuracy: 1e-3)
        XCTAssertEqual(end?.opacity ?? 1, 0, accuracy: 1e-3)
        XCTAssertNil(BurstField.ring(at: BurstField.ringDelay + BurstField.ringTime, cover: cover))
    }

    func testCover_isTheDistanceToTheFurthestCorner() {
        let cover = BurstField.cover(from: CGPoint(x: 100, y: 700), in: CGSize(width: 400, height: 800))
        XCTAssertEqual(cover, hypot(300, 700), accuracy: 1e-9)
    }

    func testDuration_outlastsEverySparkAndTheRing() {
        XCTAssertGreaterThanOrEqual(BurstField.duration, BurstField.sparks.map(\.life).max() ?? 0)
        XCTAssertGreaterThanOrEqual(BurstField.duration, BurstField.ringDelay + BurstField.ringTime)
    }

    func testAverageColor_ofASolidImageIsThatColor() {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30)).image { context in
            UIColor(red: 0.8, green: 0.4, blue: 0.2, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        }
        let color = image.averageColor()
        XCTAssertEqual(color.red, 0.8, accuracy: 0.02)
        XCTAssertEqual(color.green, 0.4, accuracy: 0.02)
        XCTAssertEqual(color.blue, 0.2, accuracy: 0.02)
    }

    func testAverageColor_mixesHalves() {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 40))
            UIColor.white.setFill()
            context.fill(CGRect(x: 20, y: 0, width: 20, height: 40))
        }
        XCTAssertEqual(image.averageColor().green, 0.5, accuracy: 0.05)
    }

    func testTint_liftsDarkPhotosSoSparksShowOnBlack() {
        let tint = BurstField.tint(for: .init(red: 0.2, green: 0.1, blue: 0.05))
        XCTAssertEqual(max(tint.red, tint.green, tint.blue), BurstField.minimumTintBrightness, accuracy: 1e-9)
        XCTAssertEqual(tint.red / tint.green, 2, accuracy: 1e-9, "Keeps the hue")
        let bright = BurstField.RGB(red: 0.9, green: 0.5, blue: 0.3)
        XCTAssertEqual(BurstField.tint(for: bright), bright)
    }

    func testTint_blackBecomesWhite() {
        let tint = BurstField.tint(for: .init(red: 0, green: 0, blue: 0))
        XCTAssertEqual(tint.red, BurstField.minimumTintBrightness, accuracy: 1e-9)
        XCTAssertEqual(tint.red, tint.blue)
    }
}

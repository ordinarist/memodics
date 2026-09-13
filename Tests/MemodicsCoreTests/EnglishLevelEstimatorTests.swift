import XCTest
@testable import MemodicsCore

final class EnglishLevelEstimatorTests: XCTestCase {
    func testBelowA1ThresholdIsNil() {
        let est = EnglishLevelEstimator.estimate(understoodByLevel: [.a1: 5])
        XCTAssertNil(est.level)
        XCTAssertEqual(est.confidence, .low)
    }

    func testHighestBandThatClearsThresholdWins() {
        let est = EnglishLevelEstimator.estimate(understoodByLevel: [
            .a1: 20, .a2: 40, .b1: 60,
        ])
        XCTAssertEqual(est.level, .b1)
    }

    func testMonotonicGatingCapsAtGap() {
        // B2 is over threshold, but B1 is below → level is capped at A2.
        let est = EnglishLevelEstimator.estimate(understoodByLevel: [
            .a1: 20, .a2: 40, .b1: 10, .b2: 80,
        ])
        XCTAssertEqual(est.level, .a2)
    }

    func testDistributionIsPassedThrough() {
        let counts: [CEFRLevel: Int] = [.a1: 20, .a2: 5]
        let est = EnglishLevelEstimator.estimate(understoodByLevel: counts)
        XCTAssertEqual(est.distribution, counts)
    }

    func testConfidenceTiers() {
        XCTAssertEqual(EnglishLevelEstimator.estimate(understoodByLevel: [.a1: 49]).confidence, .low)
        XCTAssertEqual(EnglishLevelEstimator.estimate(understoodByLevel: [.a1: 100]).confidence, .medium)
        XCTAssertEqual(EnglishLevelEstimator.estimate(understoodByLevel: [.a1: 300]).confidence, .high)
    }
}

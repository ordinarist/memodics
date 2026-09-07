import XCTest
@testable import MemodicsCore

final class CacheKeyTests: XCTestCase {

    func testKeyIsDeterministic() {
        let k1 = CacheKey.make(fromRawText: "Hello world")
        let k2 = CacheKey.make(fromRawText: "Hello world")
        XCTAssertEqual(k1, k2)
    }

    func testKeyIsLowercaseHex64Chars() {
        let key = CacheKey.make(fromRawText: "anything")
        XCTAssertEqual(key.count, 64, "SHA-256 hex is 64 characters")
        XCTAssertTrue(key.allSatisfy { $0.isHexDigit && (!$0.isLetter || $0.isLowercase) })
    }

    func testNormalizedEquivalentInputsShareKey() {
        // SPEC §15: trailing whitespace must not change the cache key.
        let k1 = CacheKey.make(fromRawText: "The company withdrew its offer.")
        let k2 = CacheKey.make(fromRawText: "The company withdrew its offer.   ")
        XCTAssertEqual(k1, k2)
    }

    func testDifferentTextProducesDifferentKey() {
        XCTAssertNotEqual(CacheKey.make(fromRawText: "alpha"),
                          CacheKey.make(fromRawText: "beta"))
    }

    func testKnownVector() {
        // SHA-256("abc") — canonical published test vector.
        let key = CacheKey.hash(ofNormalizedText: "abc")
        XCTAssertEqual(key, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}

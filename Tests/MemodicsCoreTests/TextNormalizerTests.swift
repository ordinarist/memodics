import XCTest
@testable import MemodicsCore

final class TextNormalizerTests: XCTestCase {

    func testTrimsLeadingAndTrailingWhitespace() {
        XCTAssertEqual(TextNormalizer.normalize("   hello  "), "hello")
    }

    func testTrailingWhitespaceExampleFromSpec() {
        // SPEC §15: these two must resolve to the same normalized form.
        let a = TextNormalizer.normalize("The company withdrew its offer.")
        let b = TextNormalizer.normalize("The company withdrew its offer.   ")
        XCTAssertEqual(a, b)
        XCTAssertEqual(a, "The company withdrew its offer.")
    }

    func testCollapsesRepeatedWhitespace() {
        XCTAssertEqual(TextNormalizer.normalize("a   b\t\tc"), "a b c")
    }

    func testCollapsesNewlinesToSingleSpace() {
        XCTAssertEqual(TextNormalizer.normalize("line one\n\nline two"), "line one line two")
    }

    func testAppliesUnicodeCanonicalComposition() {
        // "é" as base "e" + combining acute (U+0301) must normalize to
        // the precomposed "é" (U+00E9) so equivalent selections share a key.
        let decomposed = "cafe\u{0301}"
        let precomposed = "caf\u{00E9}"
        XCTAssertEqual(TextNormalizer.normalize(decomposed),
                       TextNormalizer.normalize(precomposed))
    }

    func testEmptyAndWhitespaceOnlyNormalizeToEmpty() {
        XCTAssertEqual(TextNormalizer.normalize(""), "")
        XCTAssertEqual(TextNormalizer.normalize("   \n\t "), "")
    }

    func testInternalSingleSpacesPreserved() {
        XCTAssertEqual(TextNormalizer.normalize("hello world"), "hello world")
    }
}

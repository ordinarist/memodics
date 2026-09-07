import XCTest
@testable import MemodicsCore

final class TextQualifierTests: XCTestCase {

    let q = TextQualifier(maxCharacters: 4000)

    func testRejectsEmptyAndWhitespace() {
        XCTAssertFalse(q.isProcessable(""))
        XCTAssertFalse(q.isProcessable("    \n\t "))
    }

    func testRejectsPunctuationOnly() {
        XCTAssertFalse(q.isProcessable("!!!"))
        XCTAssertFalse(q.isProcessable("— …"))
    }

    func testAcceptsSingleWord() {
        XCTAssertTrue(q.isProcessable("ubiquitous"))
    }

    func testAcceptsSentencesAndParagraphs() {
        XCTAssertTrue(q.isProcessable("The company withdrew its offer."))
        XCTAssertTrue(q.isProcessable(String(repeating: "word ", count: 100)))
    }

    func testRejectsBeyondConfigurableMaximum() {
        let small = TextQualifier(maxCharacters: 10)
        XCTAssertFalse(small.isProcessable("this is definitely longer than ten"))
        XCTAssertTrue(small.isProcessable("short one"))
    }
}

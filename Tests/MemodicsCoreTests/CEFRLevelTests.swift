import XCTest
@testable import MemodicsCore

final class CEFRLevelTests: XCTestCase {
    func testOrderingIsAscending() {
        XCTAssertLessThan(CEFRLevel.a1, .a2)
        XCTAssertLessThan(CEFRLevel.b2, .c1)
        XCTAssertEqual(CEFRLevel.allCases, [.a1, .a2, .b1, .b2, .c1, .c2])
    }
    func testLooseParseAcceptsCaseAndWhitespace() {
        XCTAssertEqual(CEFRLevel(loose: "A1"), .a1)
        XCTAssertEqual(CEFRLevel(loose: " b2 "), .b2)
    }
    func testLooseParseRejectsJunk() {
        XCTAssertNil(CEFRLevel(loose: "Z9"))
        XCTAssertNil(CEFRLevel(loose: ""))
    }
}

import XCTest
@testable import MemodicsCore

final class FileLoggerTests: XCTestCase {

    private var dir: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileLoggerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("memodics.log")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func readLog() -> String {
        (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    func testWritesLeveledLineWithMessage() {
        let logger = FileLogger(fileURL: fileURL, minimumLevel: .debug)
        logger.error("boom")
        let contents = readLog()
        XCTAssertTrue(contents.contains("[ERROR]"), "should tag the level")
        XCTAssertTrue(contents.contains("boom"), "should include the message")
        XCTAssertTrue(contents.hasSuffix("\n"), "each entry ends with a newline")
    }

    func testAppendsAcrossCalls() {
        let logger = FileLogger(fileURL: fileURL, minimumLevel: .debug)
        logger.info("first")
        logger.info("second")
        let lines = readLog().split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("first"))
        XCTAssertTrue(lines[1].contains("second"))
    }

    func testDropsEntriesBelowMinimumLevel() {
        let logger = FileLogger(fileURL: fileURL, minimumLevel: .warning)
        logger.info("ignored")
        logger.warning("kept")
        let contents = readLog()
        XCTAssertFalse(contents.contains("ignored"))
        XCTAssertTrue(contents.contains("kept"))
    }

    func testRotatesWhenOverMaxBytes() {
        // Tiny cap so two short lines force a rollover.
        let logger = FileLogger(fileURL: fileURL, minimumLevel: .debug, maxBytes: 40)
        logger.info("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa") // > 40 bytes with prefix
        logger.info("second")
        let rolled = URL(fileURLWithPath: fileURL.path + ".1")
        XCTAssertTrue(FileManager.default.fileExists(atPath: rolled.path),
                      "primary log should have rolled to .1")
        let primary = readLog()
        XCTAssertTrue(primary.contains("second"))
        XCTAssertFalse(primary.contains("aaaaaaaaaa"), "old content moved to .1")
    }

    func testLoggingNeverThrowsToCaller() {
        // Directory does not exist yet and path is nested; logger must cope.
        let nested = dir.appendingPathComponent("a/b/c/memodics.log")
        let logger = FileLogger(fileURL: nested, minimumLevel: .debug)
        logger.info("ok") // must not crash
        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.path))
    }
}

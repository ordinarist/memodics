import XCTest
@testable import MemodicsCore

final class DatabaseTests: XCTestCase {

    func testInMemoryMigrationCreatesAllTables() throws {
        let db = try Database.inMemory()
        let tables = try db.tableNames()
        XCTAssertTrue(tables.contains("sentence_cache"), "missing sentence_cache")
        XCTAssertTrue(tables.contains("vocabulary"), "missing vocabulary")
        XCTAssertTrue(tables.contains("lookup"), "missing lookup")
        XCTAssertTrue(tables.contains("vocabulary_occurrence"), "missing vocabulary_occurrence")
    }

    func testSchemaVersionIsSetAfterMigration() throws {
        let db = try Database.inMemory()
        XCTAssertEqual(db.schemaVersion, Database.currentSchemaVersion)
        XCTAssertGreaterThanOrEqual(db.schemaVersion, 1)
    }

    func testMigrationIsIdempotentAcrossReopen() throws {
        let path = NSTemporaryDirectory() + "memodics-test-\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: path) }

        let first = try Database(path: path)
        XCTAssertEqual(first.schemaVersion, Database.currentSchemaVersion)

        // Reopening the same file must not error or reset the version.
        let second = try Database(path: path)
        XCTAssertEqual(second.schemaVersion, Database.currentSchemaVersion)
        XCTAssertTrue(try second.tableNames().contains("vocabulary"))
    }

    func testExecuteAndScalarQuery() throws {
        let db = try Database.inMemory()
        try db.execute("CREATE TABLE t(x INTEGER)")
        try db.execute("INSERT INTO t(x) VALUES (41)")
        try db.execute("INSERT INTO t(x) VALUES (1)")
        let sum = try db.queryScalarInt("SELECT SUM(x) FROM t")
        XCTAssertEqual(sum, 42)
    }
}

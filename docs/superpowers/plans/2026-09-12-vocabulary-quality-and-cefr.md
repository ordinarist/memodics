# Vocabulary Quality + CEFR Levelling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve vocabulary extraction quality (cut noise, add a conjunction type, keep multi-word units, rank dictionary headwords first) and add per-word CEFR levels plus a mastery-based overall English-level estimate.

**Architecture:** CEFR is supplied by the translation provider (full context, covers multi-word units) and flows through `AnalyzedVocabulary` → `VocabularyItem` → a new nullable `cefr` column (schema v2). A pure, test-first `EnglishLevelEstimator` in `MemodicsCore` computes the overall level from understood-word counts per band. The AppKit/SwiftUI layer stays thin: it renders Core output (a popup badge and a dashboard card + chart).

**Tech Stack:** Swift 5 (SwiftPM, Swift 5 language mode), system SQLite via the existing `Database`/`Schema` layer, XCTest, SwiftUI/AppKit for the thin UI.

**Spec:** `docs/superpowers/specs/2026-09-12-vocabulary-quality-and-cefr-design.md`

---

## File Structure

**Create:**
- `Sources/MemodicsCore/Services/EnglishLevelEstimator.swift` — pure mastery estimator + `EnglishLevelEstimate`.
- `Tests/MemodicsCoreTests/CEFRLevelTests.swift`
- `Tests/MemodicsCoreTests/VocabularyRankingTests.swift`
- `Tests/MemodicsCoreTests/EnglishLevelEstimatorTests.swift`

**Modify:**
- `Sources/MemodicsCore/Models/Models.swift` — `CEFRLevel` enum, `VocabularyType.conjunction` + `displayRank`, `VocabularyItem.cefr`.
- `Sources/MemodicsCore/Translation/TranslationResult.swift` — `AnalyzedVocabulary.cefr` + `rankedForDisplay()`.
- `Sources/MemodicsCore/Translation/TranslationResponseParser.swift` — parse `cefr`.
- `Sources/MemodicsCore/Translation/LLMTranslationProvider.swift` — testable `makeSystemPrompt`, updated content.
- `Sources/MemodicsCore/Database/Schema.swift` — `v2`.
- `Sources/MemodicsCore/Database/Database.swift` — bump version + migration case.
- `Sources/MemodicsCore/Services/VocabularyService.swift` — read/write `cefr`, `vocabularyCountsByCEFR()`.
- `Sources/MemodicsCore/Services/LookupPipeline.swift` — pass `cefr`, apply ranking.
- `Sources/Memodics/UI/PopupView.swift` — CEFR badge.
- `Sources/Memodics/UI/DashboardView.swift` — "Your English level" card + chart + view-model wiring.
- Existing test files: `TranslationParsingTests.swift`, `ServiceTests.swift`, `DatabaseTests.swift`, `LookupPipelineTests.swift`.

---

### Task 1: `CEFRLevel` enum

**Files:**
- Modify: `Sources/MemodicsCore/Models/Models.swift`
- Test: `Tests/MemodicsCoreTests/CEFRLevelTests.swift` (create)

- [ ] **Step 1: Write the failing test**

Create `Tests/MemodicsCoreTests/CEFRLevelTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CEFRLevelTests`
Expected: FAIL — "cannot find 'CEFRLevel' in scope".

- [ ] **Step 3: Add the enum**

In `Sources/MemodicsCore/Models/Models.swift`, after the `VocabularyStatus` enum, add:

```swift
/// Common European Framework of Reference level of a vocabulary item. SPEC §16.
public enum CEFRLevel: String, Codable, Sendable, CaseIterable, Comparable {
    case a1, a2, b1, b2, c1, c2

    /// Ordered by CaseIterable ordinal: a1 < a2 < … < c2.
    public static func < (lhs: CEFRLevel, rhs: CEFRLevel) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }

    /// Tolerant parse: lowercases/trims input; unknown → nil.
    public init?(loose raw: String) {
        self.init(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CEFRLevelTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MemodicsCore/Models/Models.swift Tests/MemodicsCoreTests/CEFRLevelTests.swift
git commit -m "feat(core): add CEFRLevel enum with ordering and tolerant parse"
```

---

### Task 2: `VocabularyType.conjunction` + display ranking

**Files:**
- Modify: `Sources/MemodicsCore/Models/Models.swift`
- Modify: `Sources/MemodicsCore/Translation/TranslationResult.swift`
- Test: `Tests/MemodicsCoreTests/VocabularyRankingTests.swift` (create)

- [ ] **Step 1: Write the failing test**

Create `Tests/MemodicsCoreTests/VocabularyRankingTests.swift`:

```swift
import XCTest
@testable import MemodicsCore

final class VocabularyRankingTests: XCTestCase {
    func testConjunctionTypeExists() {
        XCTAssertEqual(VocabularyType(rawValue: "conjunction"), .conjunction)
    }

    func testRankOrdersWordsThenMultiWordThenConjunction() {
        XCTAssertLessThan(VocabularyType.word.displayRank, VocabularyType.idiom.displayRank)
        XCTAssertLessThan(VocabularyType.phrasalVerb.displayRank, VocabularyType.conjunction.displayRank)
    }

    func testRankedForDisplayIsStableWithinRank() {
        let input = [
            AnalyzedVocabulary(surfaceForm: "however", lemma: "however", meaning: "", type: .conjunction),
            AnalyzedVocabulary(surfaceForm: "phase out", lemma: "phase out", meaning: "", type: .phrasalVerb),
            AnalyzedVocabulary(surfaceForm: "cats", lemma: "cat", meaning: "", type: .word),
            AnalyzedVocabulary(surfaceForm: "dogs", lemma: "dog", meaning: "", type: .word),
        ]
        let ranked = input.rankedForDisplay().map(\.lemma)
        XCTAssertEqual(ranked, ["cat", "dog", "phase out", "however"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter VocabularyRankingTests`
Expected: FAIL — "type 'VocabularyType' has no member 'conjunction'".

- [ ] **Step 3: Add the case, `displayRank`, and `rankedForDisplay`**

In `Sources/MemodicsCore/Models/Models.swift`, add the case to `VocabularyType`:

```swift
    case conjunction   // conjunctions / discourse connectives (e.g. "nevertheless")
```

Then, after the `VocabularyType` enum, add:

```swift
public extension VocabularyType {
    /// Display ordering for the popup: single dictionary headwords first,
    /// then multi-word units, then connectives. SPEC §9 ranking.
    var displayRank: Int {
        switch self {
        case .word: return 0
        case .phrase, .phrasalVerb, .idiom, .collocation: return 1
        case .conjunction: return 2
        }
    }
}
```

In `Sources/MemodicsCore/Translation/TranslationResult.swift`, after `AnalyzedVocabulary`, add:

```swift
public extension Array where Element == AnalyzedVocabulary {
    /// Stable sort by `type.displayRank`; provider order breaks ties.
    func rankedForDisplay() -> [AnalyzedVocabulary] {
        enumerated()
            .sorted { ($0.element.type.displayRank, $0.offset) < ($1.element.type.displayRank, $1.offset) }
            .map(\.element)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter VocabularyRankingTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MemodicsCore/Models/Models.swift Sources/MemodicsCore/Translation/TranslationResult.swift Tests/MemodicsCoreTests/VocabularyRankingTests.swift
git commit -m "feat(core): add conjunction type and display ranking for vocabulary"
```

---

### Task 3: `AnalyzedVocabulary.cefr` field (tolerant Codable)

**Files:**
- Modify: `Sources/MemodicsCore/Translation/TranslationResult.swift`
- Test: `Tests/MemodicsCoreTests/TranslationParsingTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `Tests/MemodicsCoreTests/TranslationParsingTests.swift` (inside the parsing test class near the other decode tests):

```swift
    func testAnalyzedVocabularyDecodesWithoutCEFRAsNil() throws {
        // Cache JSON written before CEFR existed has no "cefr" key.
        let json = #"[{"surfaceForm":"cats","lemma":"cat","meaning":"mèo","type":"word","partOfSpeech":"noun"}]"#
        let decoded = try JSONDecoder().decode([AnalyzedVocabulary].self, from: Data(json.utf8))
        XCTAssertEqual(decoded.first?.cefr, nil)
    }

    func testAnalyzedVocabularyRoundTripsCEFR() throws {
        let v = AnalyzedVocabulary(surfaceForm: "cats", lemma: "cat", meaning: "mèo",
                                   type: .word, partOfSpeech: "noun", cefr: .a1)
        let data = try JSONEncoder().encode([v])
        let back = try JSONDecoder().decode([AnalyzedVocabulary].self, from: data)
        XCTAssertEqual(back.first?.cefr, .a1)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TranslationParsingTests`
Expected: FAIL — "extra argument 'cefr' in call" / "value of type 'AnalyzedVocabulary' has no member 'cefr'".

- [ ] **Step 3: Add the field**

In `Sources/MemodicsCore/Translation/TranslationResult.swift`, add the stored property to `AnalyzedVocabulary` (after `partOfSpeech`):

```swift
    /// CEFR level of this item in context (A1–C2), if the provider supplied it. SPEC §16.
    public var cefr: CEFRLevel?
```

Update the initializer signature and body:

```swift
    public init(surfaceForm: String, lemma: String, meaning: String,
                type: VocabularyType = .word, partOfSpeech: String? = nil,
                cefr: CEFRLevel? = nil) {
        self.surfaceForm = surfaceForm
        self.lemma = lemma
        self.meaning = meaning
        self.type = type
        self.partOfSpeech = partOfSpeech
        self.cefr = cefr
    }
```

(Codable synthesis handles the optional: a missing `"cefr"` key decodes to `nil`.)

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter TranslationParsingTests`
Expected: PASS (existing tests + 2 new).

- [ ] **Step 5: Commit**

```bash
git add Sources/MemodicsCore/Translation/TranslationResult.swift Tests/MemodicsCoreTests/TranslationParsingTests.swift
git commit -m "feat(core): add optional cefr to AnalyzedVocabulary (tolerant Codable)"
```

---

### Task 4: Parser reads `cefr` and `conjunction`

**Files:**
- Modify: `Sources/MemodicsCore/Translation/TranslationResponseParser.swift`
- Test: `Tests/MemodicsCoreTests/TranslationParsingTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `Tests/MemodicsCoreTests/TranslationParsingTests.swift`:

```swift
    func testParsesCEFRAndConjunctionType() throws {
        let json = """
        {"translation":"x","vocabulary":[
          {"surfaceForm":"nevertheless","lemma":"nevertheless","meaning":"tuy nhiên","type":"conjunction","cefr":"B2"}
        ]}
        """
        let result = try TranslationResponseParser.parse(Data(json.utf8))
        XCTAssertEqual(result.vocabulary.first?.type, .conjunction)
        XCTAssertEqual(result.vocabulary.first?.cefr, .b2)
    }

    func testParsesMissingCEFRAsNil() throws {
        let json = #"{"translation":"x","vocabulary":[{"surfaceForm":"cat","lemma":"cat","meaning":"mèo","type":"word"}]}"#
        let result = try TranslationResponseParser.parse(Data(json.utf8))
        XCTAssertNil(result.vocabulary.first?.cefr)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TranslationParsingTests`
Expected: FAIL — `cefr` is nil for the B2 case (parser drops it).

- [ ] **Step 3: Extend the DTO and mapping**

In `Sources/MemodicsCore/Translation/TranslationResponseParser.swift`, add to `VocabDTO`:

```swift
        let cefr: String?
```

In the `compactMap` closure in `parse(_ data:)`, add the CEFR mapping and pass it through:

```swift
            let cefr = item.cefr.flatMap(CEFRLevel.init(loose:))
            return AnalyzedVocabulary(surfaceForm: surface, lemma: lemma,
                                      meaning: item.meaning ?? "", type: type,
                                      partOfSpeech: item.partOfSpeech, cefr: cefr)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter TranslationParsingTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MemodicsCore/Translation/TranslationResponseParser.swift Tests/MemodicsCoreTests/TranslationParsingTests.swift
git commit -m "feat(core): parse cefr and conjunction type from provider response"
```

---

### Task 5: `VocabularyItem.cefr` field

**Files:**
- Modify: `Sources/MemodicsCore/Models/Models.swift`

- [ ] **Step 1: Add the field (no new test — exercised by Task 7)**

In `Sources/MemodicsCore/Models/Models.swift`, add to `VocabularyItem` (after `lastSeenAt`):

```swift
    public var cefr: CEFRLevel?
```

Update the initializer — add `cefr` as the LAST parameter with a `nil` default so existing call sites (tests constructing `VocabularyItem`) keep compiling:

```swift
    public init(id: Int64, lemma: String, type: VocabularyType, meaning: String,
                translation: String, lookupCount: Int, status: VocabularyStatus,
                firstSeenAt: Date, lastSeenAt: Date, cefr: CEFRLevel? = nil) {
        self.id = id
        self.lemma = lemma
        self.type = type
        self.meaning = meaning
        self.translation = translation
        self.lookupCount = lookupCount
        self.status = status
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.cefr = cefr
    }
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: builds clean.

- [ ] **Step 3: Commit**

```bash
git add Sources/MemodicsCore/Models/Models.swift
git commit -m "feat(core): add optional cefr to VocabularyItem"
```

---

### Task 6: Schema v2 migration

**Files:**
- Modify: `Sources/MemodicsCore/Database/Schema.swift`
- Modify: `Sources/MemodicsCore/Database/Database.swift`
- Test: `Tests/MemodicsCoreTests/DatabaseTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `Tests/MemodicsCoreTests/DatabaseTests.swift`:

```swift
    func testSchemaV2AddsCefrColumn() throws {
        let db = try Database.inMemory()
        XCTAssertEqual(db.schemaVersion, 2)
        // Inserting with a cefr value must succeed (column exists, nullable).
        try db.run("""
            INSERT INTO vocabulary (lemma, type, meaning, translation, lookup_count, status, first_seen_at, last_seen_at, cefr)
            VALUES ('x', 'word', 'm', 't', 0, 'learning', 0, 0, 'b1')
            """)
        let level = try db.query("SELECT cefr FROM vocabulary WHERE lemma = 'x'") { $0.stringOptional(0) }.first
        XCTAssertEqual(level, "b1")
    }

    func testExistingRowsGetNullCefr() throws {
        let db = try Database.inMemory()
        try db.run("""
            INSERT INTO vocabulary (lemma, type, meaning, translation, lookup_count, status, first_seen_at, last_seen_at)
            VALUES ('y', 'word', 'm', 't', 0, 'learning', 0, 0)
            """)
        let level = try db.query("SELECT cefr FROM vocabulary WHERE lemma = 'y'") { $0.stringOptional(0) }.first ?? nil
        XCTAssertNil(level)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DatabaseTests`
Expected: FAIL — `schemaVersion` is 1; `cefr` column does not exist.

- [ ] **Step 3: Add the migration**

In `Sources/MemodicsCore/Database/Schema.swift`, add after `v1` (before the closing `}`):

```swift
    /// Version 2 — add per-item CEFR level (nullable; backfilled on next lookup).
    static let v2 = "ALTER TABLE vocabulary ADD COLUMN cefr TEXT;"
```

In `Sources/MemodicsCore/Database/Database.swift`, bump the version constant:

```swift
    public static let currentSchemaVersion: Int32 = 2
```

And add the migration case in `applyMigration(version:)`:

```swift
        case 2:
            try unsafeExecute(Schema.v2)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter DatabaseTests`
Expected: PASS (existing migration tests still pass — the `while version < current` loop applies v1 then v2 on a fresh DB, and is idempotent across reopen).

- [ ] **Step 5: Commit**

```bash
git add Sources/MemodicsCore/Database/Schema.swift Sources/MemodicsCore/Database/Database.swift Tests/MemodicsCoreTests/DatabaseTests.swift
git commit -m "feat(core): schema v2 adds nullable cefr column to vocabulary"
```

---

### Task 7: `VocabularyService` reads/writes `cefr` + grouped counts

**Files:**
- Modify: `Sources/MemodicsCore/Services/VocabularyService.swift`
- Test: `Tests/MemodicsCoreTests/ServiceTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `Tests/MemodicsCoreTests/ServiceTests.swift` (in the vocabulary-service test class; it already builds a `VocabularyService` over an in-memory DB — mirror the existing setup):

```swift
    func testUpsertStoresCEFROnInsert() throws {
        let db = try Database.inMemory()
        let vocab = VocabularyService(database: db)
        let item = try vocab.upsert(lemma: "ubiquitous", type: .word, meaning: "phổ biến",
                                    translation: "phổ biến", cefr: .c1)
        XCTAssertEqual(item.cefr, .c1)
        XCTAssertEqual(try vocab.get(id: item.id)?.cefr, .c1)
    }

    func testUpsertBackfillsCEFRWhenPreviouslyNil() throws {
        let db = try Database.inMemory()
        let vocab = VocabularyService(database: db)
        let first = try vocab.upsert(lemma: "issue", type: .word, meaning: "m", translation: "t", cefr: nil)
        XCTAssertNil(first.cefr)
        let second = try vocab.upsert(lemma: "issue", type: .word, meaning: "m", translation: "t", cefr: .b1)
        XCTAssertEqual(second.cefr, .b1)
    }

    func testUpsertDoesNotClobberExistingCEFRWithNil() throws {
        let db = try Database.inMemory()
        let vocab = VocabularyService(database: db)
        _ = try vocab.upsert(lemma: "issue", type: .word, meaning: "m", translation: "t", cefr: .b1)
        let again = try vocab.upsert(lemma: "issue", type: .word, meaning: "m", translation: "t", cefr: nil)
        XCTAssertEqual(again.cefr, .b1)
    }

    func testCountsByCEFRGroupsUnderstoodAndLearning() throws {
        let db = try Database.inMemory()
        let vocab = VocabularyService(database: db)
        let a = try vocab.upsert(lemma: "cat", type: .word, meaning: "m", translation: "t", cefr: .a1)
        let b = try vocab.upsert(lemma: "dog", type: .word, meaning: "m", translation: "t", cefr: .a1)
        _ = try vocab.upsert(lemma: "no-level", type: .word, meaning: "m", translation: "t", cefr: nil)
        try vocab.markUnderstood(id: a.id)   // a: understood, b: learning
        let counts = try vocab.vocabularyCountsByCEFR()
        XCTAssertEqual(counts[.a1]?.understood, 1)
        XCTAssertEqual(counts[.a1]?.learning, 1)
        XCTAssertNil(counts[.b1])            // no B1 rows
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ServiceTests`
Expected: FAIL — "extra argument 'cefr'" and "no member 'vocabularyCountsByCEFR'".

- [ ] **Step 3: Implement**

In `Sources/MemodicsCore/Services/VocabularyService.swift`:

Update `columns` to include `cefr` (append at the end):

```swift
    private static let columns = "id, lemma, type, meaning, translation, lookup_count, status, first_seen_at, last_seen_at, cefr"
```

Update `mapRow` to read it (index 9):

```swift
    private static func mapRow(_ r: Row) -> VocabularyItem {
        VocabularyItem(
            id: r.int(0),
            lemma: r.string(1),
            type: VocabularyType(rawValue: r.string(2)) ?? .word,
            meaning: r.string(3),
            translation: r.string(4),
            lookupCount: r.intValue(5),
            status: VocabularyStatus(rawValue: r.string(6)) ?? .learning,
            firstSeenAt: r.date(7),
            lastSeenAt: r.date(8),
            cefr: r.stringOptional(9).flatMap(CEFRLevel.init(loose:)))
    }
```

Replace the `upsert` method with a `cefr`-aware version:

```swift
    @discardableResult
    public func upsert(lemma: String, type: VocabularyType, meaning: String,
                       translation: String, cefr: CEFRLevel? = nil) throws -> VocabularyItem {
        let canonical = Self.canonicalLemma(lemma)
        if let existing = try find(lemma: canonical, type: type) {
            // Backfill CEFR when it was previously unknown; never clobber with nil.
            if existing.cefr == nil, let cefr {
                try db.run("UPDATE vocabulary SET cefr = ? WHERE id = ?",
                           [.text(cefr.rawValue), .int(existing.id)])
                return try get(id: existing.id) ?? existing
            }
            return existing
        }
        let ts = now().timeIntervalSince1970
        try db.run("""
            INSERT INTO vocabulary (lemma, type, meaning, translation, lookup_count, status, first_seen_at, last_seen_at, cefr)
            VALUES (?, ?, ?, ?, 0, 'learning', ?, ?, ?)
            """,
            [.text(canonical), .text(type.rawValue), .text(meaning), .text(translation),
             .double(ts), .double(ts), .text(cefr?.rawValue)])
        return try find(lemma: canonical, type: type)!
    }
```

(`SQLValue.text(String?)` maps a `nil` cefr to SQL `NULL`.)

Add the grouped-count query (place it near `all()`):

```swift
    /// Understood + learning counts per CEFR band, ignoring rows without a
    /// level. Understood feeds the level estimate; both feed the dashboard chart.
    public func vocabularyCountsByCEFR() throws -> [CEFRLevel: (understood: Int, learning: Int)] {
        let rows = try db.query("""
            SELECT cefr, status, COUNT(*) FROM vocabulary
            WHERE cefr IS NOT NULL
            GROUP BY cefr, status
            """) { (level: $0.stringOptional(0), status: $0.string(1), count: $0.intValue(2)) }

        var result: [CEFRLevel: (understood: Int, learning: Int)] = [:]
        for row in rows {
            guard let raw = row.level, let level = CEFRLevel(loose: raw) else { continue }
            var entry = result[level] ?? (understood: 0, learning: 0)
            if row.status == VocabularyStatus.understood.rawValue { entry.understood += row.count }
            else { entry.learning += row.count }
            result[level] = entry
        }
        return result
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ServiceTests`
Expected: PASS (existing service tests + 4 new).

- [ ] **Step 5: Commit**

```bash
git add Sources/MemodicsCore/Services/VocabularyService.swift Tests/MemodicsCoreTests/ServiceTests.swift
git commit -m "feat(core): persist cefr in VocabularyService and add grouped counts"
```

---

### Task 8: Pipeline passes `cefr` and ranks output

**Files:**
- Modify: `Sources/MemodicsCore/Services/LookupPipeline.swift`
- Test: `Tests/MemodicsCoreTests/LookupPipelineTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `Tests/MemodicsCoreTests/LookupPipelineTests.swift` (the file has a `makeHarness` helper and `MockTranslationProvider`; build the result with mixed types + cefr):

```swift
    func testOutcomeRanksHeadwordsFirstAndStoresCEFR() async throws {
        let result = TranslationResult(translation: "t", vocabulary: [
            AnalyzedVocabulary(surfaceForm: "however", lemma: "however", meaning: "m", type: .conjunction, cefr: .b1),
            AnalyzedVocabulary(surfaceForm: "cats", lemma: "cat", meaning: "m", type: .word, cefr: .a1),
        ])
        let harness = makeHarness(result: result)
        let outcome = try await harness.pipeline.lookup(rawText: "However, cats.", sourceApplication: nil)

        // Ranked: word ("cat") before conjunction ("however").
        XCTAssertEqual(outcome.vocabulary.map(\.item.lemma), ["cat", "however"])
        // CEFR persisted on the canonical item.
        XCTAssertEqual(outcome.vocabulary.first?.item.cefr, .a1)
    }
```

> If `makeHarness` in this file does not already accept a `result:` argument, use the existing pattern in the file to construct a `LookupPipeline` with a `MockTranslationProvider(result:)` and in-memory services, then call `.lookup`. Match the file's existing helper names.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LookupPipelineTests`
Expected: FAIL — order is `["however", "cat"]` and `cefr` is nil.

- [ ] **Step 3: Update the pipeline**

In `Sources/MemodicsCore/Services/LookupPipeline.swift`, apply ranking right after `analyzed` is resolved (works for both cache-hit and miss branches). Change the loop header from `for v in analyzed {` to iterate the ranked list, and pass `cefr` into `upsert`:

```swift
        // 7–8. Upsert vocab, bump counts (always), record occurrences.
        var displayVocab: [LookupVocabulary] = []
        for v in analyzed.rankedForDisplay() {
            let item = try vocabulary.upsert(lemma: v.lemma, type: v.type,
                                             meaning: v.meaning, translation: v.meaning,
                                             cefr: v.cefr)
            try vocabulary.incrementLookupCount(id: item.id)
            try history.addOccurrence(vocabularyId: item.id, lookupId: lookupRecord.id,
                                      surfaceForm: v.surfaceForm, context: rawText)
            let refreshed = try vocabulary.get(id: item.id) ?? item
            displayVocab.append(LookupVocabulary(
                item: refreshed, surfaceForm: v.surfaceForm, meaning: v.meaning,
                highlightLevel: HighlightLevel.level(for: refreshed)))
        }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter LookupPipelineTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MemodicsCore/Services/LookupPipeline.swift Tests/MemodicsCoreTests/LookupPipelineTests.swift
git commit -m "feat(core): pipeline stores cefr and ranks vocabulary for display"
```

---

### Task 9: `EnglishLevelEstimator`

**Files:**
- Create: `Sources/MemodicsCore/Services/EnglishLevelEstimator.swift`
- Test: `Tests/MemodicsCoreTests/EnglishLevelEstimatorTests.swift` (create)

- [ ] **Step 1: Write the failing test**

Create `Tests/MemodicsCoreTests/EnglishLevelEstimatorTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter EnglishLevelEstimatorTests`
Expected: FAIL — "cannot find 'EnglishLevelEstimator' in scope".

- [ ] **Step 3: Implement the estimator**

Create `Sources/MemodicsCore/Services/EnglishLevelEstimator.swift`:

```swift
import Foundation

/// Mastery-based overall English-level estimate. SPEC §16 (design doc
/// 2026-09-12). CEFR mastery is cumulative: your level is the highest band
/// where you have mastered (marked "understood") enough words AND every lower
/// band also clears its threshold.
public struct EnglishLevelEstimate: Equatable, Sendable {
    public enum Confidence: String, Sendable, Equatable { case low, medium, high }
    /// nil = not enough data yet.
    public let level: CEFRLevel?
    /// Understood counts per band (passthrough of the estimator input).
    public let distribution: [CEFRLevel: Int]
    public let confidence: Confidence
}

public enum EnglishLevelEstimator {
    /// Understood-word count required to "clear" each band. Higher bands taper
    /// because fewer distinct high-level words are encountered in practice.
    /// Single source of truth — tune here.
    static let thresholds: [CEFRLevel: Int] = [
        .a1: 20, .a2: 40, .b1: 60, .b2: 80, .c1: 60, .c2: 40,
    ]

    public static func estimate(understoodByLevel: [CEFRLevel: Int]) -> EnglishLevelEstimate {
        var level: CEFRLevel?
        for band in CEFRLevel.allCases {
            let count = understoodByLevel[band] ?? 0
            let threshold = thresholds[band] ?? .max
            if count >= threshold {
                level = band
            } else {
                break   // monotonic: a gap caps the level here
            }
        }
        let total = understoodByLevel.values.reduce(0, +)
        let confidence: EnglishLevelEstimate.Confidence =
            total < 50 ? .low : (total < 200 ? .medium : .high)
        return EnglishLevelEstimate(level: level, distribution: understoodByLevel,
                                    confidence: confidence)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter EnglishLevelEstimatorTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MemodicsCore/Services/EnglishLevelEstimator.swift Tests/MemodicsCoreTests/EnglishLevelEstimatorTests.swift
git commit -m "feat(core): mastery-based EnglishLevelEstimator"
```

---

### Task 10: Update the extraction prompt (testable)

**Files:**
- Modify: `Sources/MemodicsCore/Translation/LLMTranslationProvider.swift`
- Test: `Tests/MemodicsCoreTests/TranslationParsingTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `Tests/MemodicsCoreTests/TranslationParsingTests.swift`:

```swift
    func testSystemPromptRequestsQualityRulesAndCEFR() {
        let prompt = LLMTranslationProvider.makeSystemPrompt(targetLanguage: "Vietnamese", knownLemmas: [])
        XCTAssertTrue(prompt.contains("conjunction"), "prompt should allow conjunction type")
        XCTAssertTrue(prompt.contains("cefr"), "prompt should request a cefr field")
        XCTAssertTrue(prompt.lowercased().contains("proper noun"), "prompt should exclude proper nouns")
        XCTAssertTrue(prompt.contains("A1"), "prompt should list CEFR bands")
    }

    func testSystemPromptListsKnownLemmas() {
        let prompt = LLMTranslationProvider.makeSystemPrompt(targetLanguage: "Vietnamese", knownLemmas: ["cat", "dog"])
        XCTAssertTrue(prompt.contains("cat, dog"))
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TranslationParsingTests`
Expected: FAIL — "type 'LLMTranslationProvider' has no member 'makeSystemPrompt'".

- [ ] **Step 3: Extract a static prompt builder and update its content**

In `Sources/MemodicsCore/Translation/LLMTranslationProvider.swift`, replace the private instance method `systemPrompt(knownLemmas:)` with a call to a new `static` function, and add that function. First, in `buildRequest`, change the message line to:

```swift
                ["role": "system", "content": Self.makeSystemPrompt(
                    targetLanguage: configuration.targetLanguage, knownLemmas: known)],
```

Then delete the old `private func systemPrompt(...)` and add:

```swift
    /// Builds the system prompt. `static` + `internal` so it is unit-testable
    /// without a live endpoint.
    static func makeSystemPrompt(targetLanguage: String, knownLemmas: [String]) -> String {
        let knownClause = knownLemmas.isEmpty
            ? ""
            : " Do NOT include these already-known lemmas in the vocabulary array: \(knownLemmas.joined(separator: ", "))."
        return """
        You are a reading assistant for an English learner whose target language is \(targetLanguage).
        Translate the user's English text into \(targetLanguage), then identify vocabulary worth learning.
        Prefer genuine dictionary entries. DO NOT include proper nouns, personal/place/brand names, \
        pure numbers, code identifiers, file paths, or URLs, and skip trivially common words the learner \
        already knows.
        DO include conjunctions and discourse connectives worth learning (e.g. "nevertheless", "whereas", \
        "albeit") using type "conjunction".
        Treat phrasal verbs, idioms, and meaningful multi-word expressions as single units — do not split them.
        Use the surrounding context to choose the correct contextual meaning and CEFR level of each item.
        Respond with a single JSON object ONLY, matching exactly:
        {"translation": string, "vocabulary": [{"surfaceForm": string, "lemma": string, "meaning": string (in \(targetLanguage)), "type": one of "word"|"phrase"|"phrasal_verb"|"idiom"|"collocation"|"conjunction", "cefr": one of "A1"|"A2"|"B1"|"B2"|"C1"|"C2", "partOfSpeech": string}]}
        The lemma must be the canonical dictionary form so inflected forms map together.\(knownClause)
        """
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter TranslationParsingTests`
Expected: PASS.

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/MemodicsCore/Translation/LLMTranslationProvider.swift Tests/MemodicsCoreTests/TranslationParsingTests.swift
git commit -m "feat(core): extraction prompt requests dictionary-quality vocab + CEFR"
```

---

### Task 11: Popup CEFR badge (thin UI, build-verified)

**Files:**
- Modify: `Sources/Memodics/UI/PopupView.swift`

- [ ] **Step 1: Add the badge**

In `Sources/Memodics/UI/PopupView.swift`, inside `vocabularyRow(_:)`, in the inner `HStack(spacing: 6)` that shows the lemma and count, add a CEFR badge after the count. Replace that inner `HStack` with:

```swift
                HStack(spacing: 6) {
                    Text(entry.item.lemma).fontWeight(.medium)
                    Text("× \(entry.item.lookupCount)").font(.caption).foregroundStyle(.secondary)
                    if let cefr = entry.item.cefr {
                        Text(cefr.rawValue.uppercased())
                            .font(.caption2).fontWeight(.semibold)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds clean.

- [ ] **Step 3: Launch-verify**

Run: `swift run Memodics`, look up text in another app via ⌥⌘L, confirm the popup shows a CEFR badge (e.g. `B2`) next to leveled words and no badge for unleveled ones. Quit.

- [ ] **Step 4: Commit**

```bash
git add Sources/Memodics/UI/PopupView.swift
git commit -m "feat(app): show CEFR badge next to popup vocabulary items"
```

---

### Task 12: Dashboard "Your English level" card + distribution chart

**Files:**
- Modify: `Sources/Memodics/UI/DashboardView.swift`

Context: `DashboardView` observes a `DashboardViewModel` (in the same file) that already holds a `VocabularyService` (via the environment) and reloads items. The card reads the estimate/distribution the view model computes from `vocabularyCountsByCEFR()`.

- [ ] **Step 1: Add estimate state to the view model**

In `Sources/Memodics/UI/DashboardView.swift`, in `DashboardViewModel`, add published state and populate it inside the existing `reload()` (mirror how `reload()` already queries the service — use the same stored service reference and `try?` error handling the file already uses):

```swift
    @Published var levelEstimate: EnglishLevelEstimate?
    @Published var cefrCounts: [CEFRLevel: (understood: Int, learning: Int)] = [:]
```

At the end of `reload()`, add:

```swift
        let counts = (try? vocabulary.vocabularyCountsByCEFR()) ?? [:]
        cefrCounts = counts
        let understood = counts.mapValues(\.understood)
        levelEstimate = EnglishLevelEstimator.estimate(understoodByLevel: understood)
```

> Use the view model's existing service property name in place of `vocabulary` if it differs (the file already calls the service in `reload()` — match that reference).

- [ ] **Step 2: Add the card view**

In `DashboardView`, add a computed `levelCard` view and render it at the top of the `detail`/sidebar column. Add this method to `DashboardView`:

```swift
    @ViewBuilder
    private var levelCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your English level").font(.headline)
            if let est = model.levelEstimate, let level = est.level {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(level.rawValue.uppercased()).font(.system(size: 34, weight: .bold))
                    Text("confidence: \(est.confidence.rawValue)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Keep looking up words to estimate your level.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            cefrChart
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
        .padding(12)
    }

    @ViewBuilder
    private var cefrChart: some View {
        let maxCount = max(1, model.cefrCounts.values.map { $0.understood + $0.learning }.max() ?? 1)
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(CEFRLevel.allCases, id: \.self) { band in
                let c = model.cefrCounts[band] ?? (understood: 0, learning: 0)
                VStack(spacing: 2) {
                    ZStack(alignment: .bottom) {
                        Capsule().fill(Color.secondary.opacity(0.15))
                            .frame(width: 18, height: 60)
                        VStack(spacing: 0) {
                            Capsule().fill(Color.orange.opacity(0.7))
                                .frame(width: 18, height: 60 * CGFloat(c.learning) / CGFloat(maxCount))
                            Capsule().fill(Color.green.opacity(0.8))
                                .frame(width: 18, height: 60 * CGFloat(c.understood) / CGFloat(maxCount))
                        }
                    }
                    Text(band.rawValue.uppercased()).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
```

- [ ] **Step 3: Mount the card**

In `DashboardView.body`, put the card above the sidebar list. Change the `sidebar` `VStack(spacing: 0) { ... }` so `levelCard` is the first child (before the `Picker`):

```swift
        VStack(spacing: 0) {
            levelCard
            Picker("", selection: $model.statusFilter) {
```

- [ ] **Step 4: Build**

Run: `swift build`
Expected: builds clean.

- [ ] **Step 5: Launch-verify**

Run: `swift run Memodics`, open the Vocabulary Dashboard, confirm the "Your English level" card renders with an estimate (or the "keep looking up words" placeholder) and an A1–C2 bar chart (green = understood, orange = learning). Quit.

- [ ] **Step 6: Commit**

```bash
git add Sources/Memodics/UI/DashboardView.swift
git commit -m "feat(app): dashboard English-level card with CEFR distribution chart"
```

---

### Task 13: Bump version to 0.2.0

**Files:**
- Modify: `Sources/MemodicsCore/MemodicsCore.swift`
- Modify: `Resources/Info.plist`

- [ ] **Step 1: Bump the library version**

In `Sources/MemodicsCore/MemodicsCore.swift`, change:

```swift
    public static let version = "0.1.0"
```

to:

```swift
    public static let version = "0.2.0"
```

- [ ] **Step 2: Bump the bundle version**

In `Resources/Info.plist`, change `CFBundleShortVersionString` from `0.1.0` to `0.2.0`, and `CFBundleVersion` from `1` to `2`:

```xml
    <key>CFBundleShortVersionString</key>
    <string>0.2.0</string>
    <key>CFBundleVersion</key>
    <string>2</string>
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: builds clean.

- [ ] **Step 4: Commit**

```bash
git add Sources/MemodicsCore/MemodicsCore.swift Resources/Info.plist
git commit -m "chore: bump version to 0.2.0"
```

---

### Task 14: Final full-suite check

- [ ] **Step 1: Run everything**

Run: `swift test`
Expected: full suite passes (previous 59 tests + new ones).

- [ ] **Step 2: Build the release app to confirm the app target compiles**

Run: `swift build -c release`
Expected: builds clean.

---

## Self-Review notes

- **Spec coverage:** §1 model+schema → Tasks 1,3,5,6; §2 prompt/parser/ranking → Tasks 2,4,8,10; §3 estimator+query → Tasks 7,9; §4 UI → Tasks 11,12; §5 tests are embedded in each task. All spec sections map to tasks.
- **Type consistency:** `CEFRLevel(loose:)`, `VocabularyType.displayRank`, `Array.rankedForDisplay()`, `upsert(...,cefr:)`, `vocabularyCountsByCEFR()`, `EnglishLevelEstimator.estimate(understoodByLevel:)`, `EnglishLevelEstimate(level:distribution:confidence:)` are used identically wherever referenced.
- **Ordering keeps the suite green:** optional fields have `nil` defaults so intermediate tasks compile; the `columns`/`mapRow` change (Task 7) lands together with the query that reads the new column.

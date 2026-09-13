# Vocabulary Quality + CEFR Levelling — Design

**Date:** 2026-09-12
**Status:** Approved (pending spec review)
**Relates to:** SPEC §9 (analysis output), §16 (Vocabulary model), §13 (highlight
buckets — unchanged), §21 (cache hierarchy — unchanged), README dashboard.

## Motivation

After several days of real use, two gaps emerged:

1. **Extraction quality.** The extracted vocabulary mixes genuinely learnable
   dictionary entries with noise (proper nouns, names, numbers, code
   identifiers), while some worthwhile function words (conjunctions / discourse
   connectives) are skipped. The user wants dictionary headwords prioritised,
   multi-word units preserved, and useful connectives captured.
2. **No sense of progress.** There is no per-word difficulty signal and no way to
   see one's own English level. The user wants each item tagged with a CEFR
   level (A1–C2) and a **mastery-based** overall estimate that grows as words are
   marked "understood."

Both features touch the same seam — extraction prompt → `AnalyzedVocabulary` →
`VocabularyItem` → schema → dashboard — so they are designed and built together.

## Approach

Extend the existing pipeline in place; do not add a new subsystem.

- **CEFR comes from the AI**, not a bundled word-list. The model already has full
  sentence context and can level multi-word units (phrasal verbs, idioms,
  collocations) that a static headword list cannot.
- **Estimation logic lives in `MemodicsCore`** as pure, deterministic,
  test-first code — offline, no network, independently testable (SPEC §26).

Rejected alternatives: a separate "assessment module" (over-engineered for MVP
scale); a bundled CEFR word-list instead of the AI (offline + free, but cannot
level multi-word units or use context, and adds a shipped data file).

## Non-goals

- No spaced repetition, quizzes, or gamification (SPEC §25 exclusions stand).
- The highlight-intensity buckets (SPEC §13) are unchanged; CEFR does not affect
  highlighting.
- No re-analysis of already-known lemmas purely to backfill CEFR — backfill
  happens naturally the next time a lemma is looked up.

## 1. Data model & schema (Core)

### `CEFRLevel`

New enum in `Models.swift`:

```swift
public enum CEFRLevel: String, Codable, Sendable, Comparable, CaseIterable {
    case a1, a2, b1, b2, c1, c2
    // Comparable by CaseIterable ordinal: a1 < a2 < … < c2.
    // Tolerant parse: accept "A1"/"a1"; unknown → nil (handled at call sites).
}
```

- `Comparable` implemented via `allCases` index so band ordering is explicit.
- A tolerant factory (e.g. `CEFRLevel(loose:)`) lowercases input and returns
  `nil` for anything unrecognised.

### `VocabularyType`

Add one case:

```swift
case conjunction   // conjunctions / discourse connectives (e.g. "nevertheless")
```

Raw value `"conjunction"`. All existing cases unchanged.

### `AnalyzedVocabulary` and `VocabularyItem`

Add `public var cefr: CEFRLevel?` to both. `nil` means "level unknown" (older
rows, or the model omitted it). Initialisers gain the parameter with a
`nil` default so existing call sites compile unchanged where practical.

### Schema v2 migration

```sql
ALTER TABLE vocabulary ADD COLUMN cefr TEXT;   -- nullable
```

- Bump `Database.currentSchemaVersion` to `2` and add a `v2` migration block.
- Existing rows keep `cefr = NULL`; they are backfilled the next time the lemma
  is looked up (the model returns a CEFR and `upsert` fills it — see §3).
- Migration must be idempotent across reopen (existing test pattern).

## 2. Extraction quality (prompt + parser)

### System prompt (`LLMTranslationProvider.systemPrompt`)

Add explicit rules, keeping the existing multi-word-unit and known-lemma
clauses:

- **Exclude** from the vocabulary array: proper nouns, personal / place / brand
  names, pure numbers, code identifiers, file paths, and URLs; also skip
  trivially common words the learner already knows.
- **Include** conjunctions and discourse connectives that are worth learning
  (e.g. "nevertheless", "whereas", "albeit") using `type: "conjunction"`.
- Continue treating phrasal verbs, idioms, and meaningful multi-word expressions
  as single units.
- Extend the required JSON object so each vocabulary entry also carries
  `"cefr": one of "A1"|"A2"|"B1"|"B2"|"C1"|"C2"` (the CEFR level of that item in
  this context) and the `type` enum now includes `"conjunction"`.

### Parser (`TranslationResponseParser`)

- `VocabDTO` gains `cefr: String?`.
- Map it through `CEFRLevel(loose:)`; unknown / missing → `nil`. Parsing stays
  fully tolerant — a missing `cefr` never fails a lookup.

### Ranking (Core, deterministic)

- Add `VocabularyType.displayRank: Int` ordering: single dictionary headword
  (`word`) first, then multi-word units (`phrase`, `phrasalVerb`, `idiom`,
  `collocation`), then `conjunction` last.
- The lookup outcome sorts its vocabulary by `displayRank` using a **stable**
  sort, so provider order breaks ties. Sorting happens in Core so it is
  unit-tested; the popup renders the already-ordered list.

## 3. Overall level — mastery-based (Core, TDD)

### `EnglishLevelEstimator`

Pure value-in / value-out type in `Services/`.

**Input:** counts of **understood** vocabulary per CEFR band. Items with
`status == .learning` and items with `cefr == nil` are ignored for the estimate
(they still appear in the chart — see §4).

**Output:**

```swift
struct EnglishLevelEstimate {
    let level: CEFRLevel?                    // nil = not enough data yet
    let distribution: [CEFRLevel: Int]       // understood counts per band
    let confidence: Confidence               // low | medium | high
}
```

**Rule — cumulative & monotonic.** CEFR mastery is cumulative: being B1 implies
command of A1/A2/B1 vocabulary. So:

> The estimated level is the **highest band B** such that the understood count
> at B meets `threshold(B)` **and every lower band also meets its threshold**.
> If even A1 is below threshold, `level == nil` ("not enough data yet").

**Default thresholds** (tunable; documented here as the single source of truth):

| Band | Threshold |
|------|-----------|
| A1   | 20 |
| A2   | 40 |
| B1   | 60 |
| B2   | 80 |
| C1   | 60 |
| C2   | 40 |

(Higher bands taper because fewer distinct high-level words are encountered in
practice.) Thresholds are defined as a constant table on the estimator so they
can be tuned in one place.

**Confidence** scales with total understood count (e.g. `< 50` → low,
`< 200` → medium, else high). Exact cutoffs finalised in implementation; shown
to the user as a short qualifier, never as false precision.

### `VocabularyService` query

Add a grouped-count query returning understood **and** learning counts per CEFR
band:

```swift
func vocabularyCountsByCEFR() throws -> [CEFRLevel: (understood: Int, learning: Int)]
```

- `NULL`-cefr rows are excluded (they cannot be placed on a band).
- Understood counts feed the estimator; both feed the dashboard chart.

## 4. UI (thin app layer)

- **Popup** (`PopupController`): a compact CEFR badge (e.g. `B2`) beside each
  vocabulary item. Items with `nil` cefr show no badge.
- **Dashboard** (`DashboardView`): a new "Your English level" card at the top —
  the estimated level (or "Keep looking up words to estimate your level") plus a
  one-line confidence qualifier, above a stacked A1–C2 bar chart showing
  understood vs still-learning counts per band. The chart makes the gap between
  *mastered* and *encountered* visible without extra text.

The app layer stays thin: it renders the estimate/distribution produced by Core;
no estimation logic lives in SwiftUI.

## 5. Testing (Core, written first — TDD)

- `CEFRLevel`: ordering (`a1 < … < c2`), tolerant parse (`"A1"`, `"a1"`, junk → nil).
- Parser: reads `cefr`; reads `type: "conjunction"`; tolerates missing `cefr`
  (→ nil) without failing the lookup.
- Ranking: `word` before multi-word before `conjunction`; stable within a rank.
- `EnglishLevelEstimator`: below-A1 → nil; monotonic gating (a gap at a lower
  band caps the level even if a higher band is over threshold); exact-threshold
  boundaries; distribution passthrough; confidence tiers.
- `VocabularyService.upsert`: stores `cefr` on insert; fills `cefr` when a
  previously-`nil` row is re-analysed; does not clobber an existing non-nil
  `cefr` with `nil`.
- `vocabularyCountsByCEFR`: correct grouping; excludes `NULL`-cefr rows;
  separates understood vs learning.
- Migration: v2 is idempotent across reopen; pre-existing rows read back with
  `cefr == nil`.

The AppKit/SwiftUI additions (popup badge, dashboard card/chart) are verified by
building + launching, per the existing convention.

## Rollout / ordering

1. Model + schema v2 migration (+ tests).
2. Prompt + parser + ranking (+ tests).
3. `EnglishLevelEstimator` + `VocabularyService` query (+ tests).
4. Popup badge + dashboard card/chart (build + launch verification).

Each step keeps the suite green before the next.

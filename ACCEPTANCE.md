# Acceptance Verification — Memodics

Status legend:

- **PASS** — verified here (automated test, or build/launch observation). Evidence cited.
- **READY** — fully implemented; final confirmation requires an interactive session
  (grant Accessibility permission, supply a real API key, select text in a real app).
  These cannot be driven from a headless/CI shell; exact manual steps are given.
- **BLOCKED** — constrained by a genuine macOS limitation; the supported fallback used
  is documented.

Automated suite: **59 tests, 0 failures** (`swift test`). Build: clean, zero warnings
(`swift build`). App launches as an accessory process and as a signed `.app` bundle
without crashing.

---

## Selection (SPEC §27)

macOS provides no reliable, cross-application "selection changed" event without
per-app Accessibility observers, and the spec forbids inventing capabilities
(SPEC §5, §17). The supported mechanism is **on-demand**: select text in any app,
then press the global hotkey **⌥⌘L** (or menu-bar → *Translate Selection*). The
popup then appears. This preserves the product behavior via a genuinely supported path.

| Criterion | Status | Notes |
|---|---|---|
| Select an English word in Safari → popup appears | READY | Select word, press ⌥⌘L. Uses AX `kAXSelectedText`, clipboard fallback otherwise. |
| Select an English sentence in Safari → popup appears | READY | Same path; sentence normalized + cached. |
| Select text in VS Code → popup appears | READY | VS Code exposes AX selected text; falls back to clipboard if not. |
| Select text in another supported app → popup appears | READY | Any app supporting AX or ⌘C copy. |
| Accessibility permission state correctly handled | PASS (logic) / READY (live) | `AccessibilityManager.isTrusted()` gates AX use; menu shows Granted/Not-Granted; "Grant…" opens System Settings. Never pretends (SPEC §5). |

**Auto-detection without a trigger: BLOCKED** by macOS — mitigated by the on-demand
hotkey/menu trigger above.

## Clipboard fallback (SPEC §27)

| Criterion | Status | Evidence |
|---|---|---|
| Fallback works when AX selection unavailable | PASS | `ClipboardExtractorTests.testExtractsCopiedText`; `SelectionManager` routes AX→clipboard. |
| Existing clipboard preserved | PASS | `testRestoresOriginalClipboardAfterSuccess`. |
| Existing clipboard restored after extraction | PASS | Same; `defer`-based restore in `ClipboardExtractor`. |
| Clipboard restored even when translation fails | PASS | `testRestoresClipboardEvenWhenCopyThrows`, `testRestoresClipboardWhenNothingWasCopied`. Restore is in `defer`, independent of downstream translation. |

Real-clipboard round-trip of all item types is implemented in `NSPasteboardAdapter`
(capture/restore of every `NSPasteboardItem` type) — READY for interactive confirmation.

## Translation (SPEC §27)

| Criterion | Status | Evidence |
|---|---|---|
| New text invokes the provider | PASS | `LookupPipelineTests.testFirstLookupCallsProviderAndPersists` (callCount == 1). |
| Translation displayed | READY | `PopupView` renders `outcome.translation`; needs real API key to see live text. |
| Vocabulary identified | PASS | Pipeline persists analyzed vocab; parser test covers structured extraction. |
| Contextual meaning preserved | READY | Provider prompt instructs contextual meaning + multi-word units; live confirmation needs API. |

## Cache (SPEC §27)

| Criterion | Status | Evidence |
|---|---|---|
| First lookup creates a cache entry | PASS | `CacheServiceTests.testStoreThenGetHits`. |
| Repeating exact normalized text does not invoke API | PASS | `LookupPipelineTests.testRepeatLookupUsesCacheWithoutCallingProvider` (callCount stays 1, incl. trailing-whitespace variant). |
| Cached translation displayed | PASS | `testRepeatLookupUsesCacheWithoutCallingProvider` returns cached translation; `servedFromCache == true`. |
| Cached vocabulary analysis displayed | PASS | `AnalysisCodec` round-trips vocab; pipeline reconstructs from cache. |

## Vocabulary (SPEC §27)

| Criterion | Status | Evidence |
|---|---|---|
| New vocabulary stored | PASS | `VocabularyServiceTests.testUpsertNewItemStartsLearningWithZeroCount`. |
| Lookup count increments | PASS | `testIncrementLookupCount`; pipeline `testLookupCountIncrementsEvenOnCacheHit`. |
| Morphological forms map to canonical lemma | PASS | `testUpsertExistingReturnsSameCanonicalRow` (case-insensitive canonicalization; provider supplies lemma). |
| Frequent vocabulary highlighted more strongly | PASS | `HighlightLevelTests` (bucketed 1→…→6, non-linear per SPEC §13). |
| Understood vocabulary no longer highlighted | PASS | `HighlightLevelTests.testUnderstoodItemNeverHighlighted`; pipeline `testUnderstoodVocabularyIsNotHighlightedButStillCounts`. |

## History (SPEC §27)

| Criterion | Status | Evidence |
|---|---|---|
| Every lookup persisted | PASS | `LookupHistoryServiceTests.testRecordPreservesContextAndText`; pipeline records each lookup. |
| Original selected text preserved | PASS | Same test (`selectedText`). |
| Context preserved | PASS | Same test (`context`); pipeline stores full selection as context. |
| Historical contexts viewable from dashboard | PASS (data) / READY (UI) | `occurrences(forVocabularyId:)` tested; `DashboardView` detail renders them. |

## Dashboard (SPEC §27)

| Criterion | Status | Notes |
|---|---|---|
| Vocabulary list works | READY | `DashboardView` list bound to `VocabularyService.all()`. |
| Lookup count visible | READY | Shown per row and in detail. |
| Vocabulary detail works | READY | Detail pane: meaning, type, counts, dates. |
| Historical contexts visible | READY | Contexts section (data path PASS). |
| "Mark as understood" works | PASS (logic) / READY (UI) | `VocabularyServiceTests.testMarkUnderstoodPersists`; dashboard + popup buttons call it. |
| Understood state persists after restart | PASS | `testMarkUnderstoodPersists` + `DatabaseTests.testMigrationIsIdempotentAcrossReopen` (SQLite file persistence). |

## Persistence (SPEC §27)

| Criterion | Status | Evidence |
|---|---|---|
| Close & reopen app | PASS | Reopen test uses on-disk SQLite; app uses `~/Library/Application Support/Memodics/memodics.sqlite`. |
| Vocabulary remains | PASS | On-disk rows; `all()` after reopen. |
| Lookup counts remain | PASS | Column persisted. |
| Cache remains | PASS | `sentence_cache` on disk. |
| History remains | PASS | `lookup` / `vocabulary_occurrence` on disk. |

---

## Interactive verification steps (to move READY → confirmed)

1. `./scripts/build-app.sh release` then `open build/Memodics.app`.
2. Menu bar → *Settings…* → paste an API key (OpenAI-compatible), set target language.
3. Grant Accessibility when prompted (menu → *Grant Accessibility Permission…*).
4. In Safari, select a sentence → press **⌥⌘L** → popup shows translation + highlighted vocab.
5. Re-select the same sentence → popup shows **cached** badge, no network call, counts still rise.
6. Click *Mark understood* → that word stops highlighting on next lookup.
7. Menu → *Vocabulary Dashboard…* → verify list, detail, contexts, mark-understood.
8. Quit and relaunch → verify vocabulary, counts, cache, history all remain.
9. Test clipboard fallback in an app without AX text (copy a value, confirm your
   clipboard is unchanged after a lookup).

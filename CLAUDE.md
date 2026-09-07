# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project state

The MVP is implemented as a Swift Package. `SPEC.md` remains the authoritative
product specification and source of truth; `ACCEPTANCE.md` maps each SPEC §27
criterion to its verification status. `README.md` has user/build docs.

## Commands

```bash
swift build                              # build library + executable
swift test                               # full suite (currently 59 tests)
swift test --filter LookupPipelineTests  # one test class
swift run Memodics                        # run the menu-bar app (dev)
./scripts/build-app.sh release           # assemble signed build/Memodics.app
```

The package uses Swift 5 language mode (`Package.swift`) to avoid strict-concurrency
churn; SQLite is the system `sqlite3` (linked in `MemodicsCore`), no external deps.

## Layout

- `Sources/MemodicsCore/` — AppKit-free, fully unit-tested logic: `Text/`
  (normalizer, cache key, qualifier), `Database/` (SQLite wrapper + `Schema`
  migrations), `Models/`, `Services/` (cache, vocabulary, history, `HighlightLevel`,
  `LookupPipeline`), `Translation/` (provider protocol, parser, mock + LLM provider),
  `Platform/` (`PasteboardProviding` + `ClipboardExtractor`).
- `Sources/Memodics/` — thin macOS layer (AppKit/SwiftUI): accessibility, clipboard
  adapter, selection, hotkey, menu bar, popup, dashboard/settings, `AppDelegate`.
- `Tests/MemodicsCoreTests/` — the test suite.

Data path: `~/Library/Application Support/Memodics/memodics.sqlite`.

## Working conventions here

- **TDD for `MemodicsCore`**: every core behavior has a test written first. Keep it
  that way — put testable logic in Core behind protocols, not in the app target.
- **The AppKit layer is deliberately thin** and verified by building + launching
  (it can't be unit-tested headlessly). Don't move business logic into it.
- Selection is **on-demand** (global hotkey ⌥⌘L / menu item), not auto-detected —
  a documented macOS limitation (see README "Why a hotkey"). Don't "fix" this by
  faking a selection-changed observer.
- Original phased order (for reference): `SPEC.md` §28.

## What the product is

A native **macOS menu-bar background app** that helps users learn English while reading. It detects English text selected in *other* apps, translates it, extracts learnable vocabulary, remembers every lookup locally, and progressively highlights vocabulary more strongly the more often it's looked up — until the user marks it "understood," after which it stops highlighting. It is a personal reading-memory system, local-only, no server/account.

## Tech stack (per spec)

- **Swift + SwiftUI** preferred; **AppKit** where required (Accessibility API, menu bar, floating panels, clipboard, focus/activation, global events). **No Electron.**
- **SQLite** for local persistence.
- macOS only, native.

There is no build tooling yet. When scaffolding, this will become an Xcode/SwiftPM project — establish the build/test/run commands here once they exist.

## Non-negotiable constraints (SPEC §2, §22)

These are hard rules. Violating them is a correctness failure, not a style choice:

- **Clipboard must never be permanently modified.** The clipboard-fallback path (SPEC §6) must save → copy → read → **restore original contents exactly**, using error-safe cleanup so restoration happens even when extraction/translation/parsing throws.
- **Minimize translation API calls.** Always resolve through the cache hierarchy first (SPEC §21): exact sentence cache → vocabulary cache → external API only when necessary. Never call the API for an already-translated normalized sentence.
- **Cached content works offline** — repeated lookups display cached translation + analysis and still increment lookup counts without any network call.
- **Local-only, private.** No accounts, no cloud sync, no telemetry, no uploading reading history. Only the currently-processed text may be sent to the configured provider.
- **Never fake macOS capabilities.** If Accessibility permission is missing, detect it, surface status in the menu bar, and offer to open System Settings — do not pretend the API works.
- **Understood vocabulary is never deleted** — it stays in the DB with its history and count, just stops being highlighted.
- See SPEC §25 for the MVP exclusion list (no spaced repetition, gamification, browser extension, etc.).

## Core architecture

The heart of the app is the **lookup pipeline** (SPEC §8), triggered whenever text is selected in another app:

```
Selected text → Normalize → Sentence cache check → Vocabulary DB check
  → decide if external analysis needed → (API call only if necessary)
  → store result → update vocabulary history → render popup
```

Recommended module boundaries (SPEC §26) — do **not** collapse this into one SwiftUI view:

- **SelectionManager** orchestrates detection, delegating to **AccessibilityManager** (primary) and **ClipboardFallback** (fallback).
- **TranslationProvider** is a protocol (SPEC §8) so the provider is swappable and mockable; **TranslationService** drives it and returns structured `TranslationResult` (translation + vocabulary items with surfaceForm/lemma/meaning/partOfSpeech, SPEC §9).
- **CacheService**, **VocabularyService**, **LookupHistoryService** sit over an independently-testable **Database** layer.
- **PopupController**, **DashboardView**, **MenuBarController**, **SettingsView** are the UI surfaces.

Two design mandates: the **Database layer must be independently testable**, and the **TranslationProvider must be mockable**.

## Data model (SPEC §15–18)

SQLite tables, conceptually:

- **SentenceCache** — `textHash` (SHA-256 of normalized text) is the deterministic cache key; stores `normalizedText`, `translation`, `analysisJSON`, timestamps. Normalization (SPEC §15) trims whitespace, collapses repeated whitespace, and normalizes Unicode so trivially-different selections map to one entry.
- **Vocabulary** — canonical `lemma`, `type` (word/phrase/phrasal_verb/idiom/collocation), `meaning`, `translation`, `lookupCount`, `status` (`learning` | `understood`), timestamps. Surface forms (withdrew/withdrawn) map to one lemma; the provider supplies the lemma — do not attempt full morphology in the MVP.
- **Lookup** — every lookup is persisted with `selectedText`, `normalizedText`, `sourceApplication`, `context`, `translation`. Store the full sentence/context, never just the word.
- **VocabularyOccurrence** — join between a vocabulary item and each lookup (`surfaceForm`, `context`), powering the dashboard's real historical examples.

## Key behavioral details

- **Highlight intensity is bucketed/logarithmic, never linear** (SPEC §13): 1→L1, 2–3→L2, 4–7→L3, 8–15→L4, 16–31→L5, 32+→L6. `understood` items get no highlight.
- **Vocabulary units may be multi-word** — phrasal verbs, idioms, collocations ("phase out", "take into account") must be treated as single units, not split into words.
- **Errors must never crash the background app** (SPEC §24) — an individual failed lookup is recovered from; the app keeps running.
- **Acceptance criteria** (SPEC §27) and **Definition of Done** (SPEC §29) require testing against *real* macOS behavior in real apps (Safari, VS Code), not only mocked APIs.

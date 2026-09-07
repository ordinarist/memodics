# macOS English Reading Assistant — Product Specification

## 1. Product Definition

A native macOS background application that helps users learn English naturally while reading.

The application detects English text selected in other macOS applications, translates it, identifies vocabulary worth learning, remembers every lookup, and progressively stops highlighting vocabulary the user has marked as understood.

The application is a personal reading-memory system, not merely a translation utility.

---

# 2. Non-Negotiable Product Principles

1. The application runs as a background/menu-bar application.
2. It does not require a server or user account.
3. User data is stored locally.
4. SQLite is the local database.
5. Accessibility API is the primary mechanism for detecting selected text.
6. Clipboard-based extraction is the fallback mechanism.
7. The application must never permanently modify the user's clipboard.
8. Translation API calls must be minimized through local caching.
9. Previously translated content must be available without another API call.
10. Vocabulary history must persist across application restarts.
11. A vocabulary item marked as "understood" must no longer be highlighted.
12. Lookup count must be tracked.
13. Higher lookup frequency produces stronger visual highlighting.
14. The application must preserve the original selected text and its context.
15. The MVP is single-user and local-only.
16. Do not add authentication, cloud synchronization, social features, or a backend to the MVP.
17. Do not simulate or invent functionality that macOS does not actually support.
18. Never silently alter the user's original text or clipboard contents.

---

# 3. Target Platform

- macOS only.
- Native application.
- Swift + SwiftUI preferred.
- AppKit may be used wherever required for:
  - Accessibility API
  - menu bar integration
  - floating windows/panels
  - clipboard handling
  - application activation/focus
  - global event handling

Do not use Electron for the MVP.

---

# 4. Application Lifecycle

The application should behave like a background utility.

After launch:

- The application remains available from the menu bar.
- It does not need a normal persistent main window.
- It should optionally support "Launch at Login" if this can be implemented cleanly.
- The application must continue functioning while the user works in other applications.

The user should be able to:

- enable/disable translation detection;
- open the vocabulary dashboard;
- open settings;
- quit the application.

---

# 5. Detecting Selected Text

## Primary mechanism

Use macOS Accessibility APIs.

When the user selects text in another application, attempt to obtain the selected text from the focused UI element.

The implementation must correctly handle Accessibility permission.

If permission is unavailable:

- detect this state;
- show an understandable status in the menu-bar application;
- provide a way to open the relevant macOS Accessibility settings.

Do not pretend that Accessibility API works when permission has not been granted.

---

# 6. Clipboard Fallback

Accessibility API is not guaranteed to work with every application.

When selected text cannot be obtained through Accessibility API, support clipboard extraction.

Fallback flow:

1. Preserve the current clipboard contents.
2. Trigger copy of the user's current selection.
3. Read the clipboard.
4. Determine whether the clipboard contains usable text.
5. Restore the original clipboard contents exactly.
6. Continue processing the extracted text.

The user's clipboard must be restored even if:

- extraction fails;
- translation fails;
- parsing fails;
- an exception/error occurs.

Clipboard restoration must use appropriate error-safe cleanup.

The application must not leave translated text or selected text in the clipboard unintentionally.

---

# 7. Text Qualification

The application should primarily process English text.

Ignore selections that are clearly:

- empty;
- whitespace-only;
- extremely short punctuation-only selections;
- binary/non-text clipboard contents.

The MVP should support:

- a single word;
- multiple words;
- phrases;
- complete sentences;
- multiple sentences;
- paragraphs.

Do not impose an unnecessarily small character limit.

A reasonable maximum may be introduced to protect API cost, but it must be explicit and configurable in code.

---

# 8. Translation Pipeline

Every lookup follows this conceptual pipeline:

Selected Text
→ Normalize
→ Check Sentence Cache
→ Check Vocabulary Database
→ Determine whether external translation/analysis is necessary
→ Call translation/analysis API only when necessary
→ Store result
→ Update vocabulary history
→ Render popup

The exact API provider must be isolated behind a protocol/interface.

Do not hard-code the application architecture around a single provider.

Example abstraction:

```swift
protocol TranslationProvider {
    func analyze(
        text: String,
        knownVocabulary: [VocabularyItem]
    ) async throws -> TranslationResult
}
```

The implementation may initially use one provider.

---

# 9. Translation Result

The translation provider should return structured data rather than an unstructured text blob.

Conceptually:

```json
{
  "translation": "The translated text",
  "vocabulary": [
    {
      "surfaceForm": "withdrew",
      "lemma": "withdraw",
      "meaning": "rút lại",
      "partOfSpeech": "verb"
    }
  ]
}
```

The exact schema may be improved during implementation, but the semantic information must exist.

The system should distinguish:

- original selected text;
- translation;
- vocabulary items;
- vocabulary meanings;
- vocabulary surface forms.

---

# 10. Vocabulary Identification

Vocabulary analysis should identify words and phrases that are potentially useful to an English learner.

It should support:

- individual words;
- phrasal verbs;
- idioms;
- meaningful multi-word expressions;
- collocations when clearly useful.

Examples:

```text
phase out
take into account
be subject to
carry out
```

must be treated as possible vocabulary units rather than blindly splitting every expression into individual words.

Context matters.

Example:

```text
issue
```

may mean different things depending on context.

The translation/analysis layer should determine the contextual meaning.

---

# 11. Vocabulary States

MVP vocabulary state:

```text
learning
understood
```

New vocabulary is initially:

```text
learning
```

When the user marks a vocabulary item as understood:

```text
understood
```

Once understood:

- it remains in the database;
- its history remains available;
- its lookup count remains available;
- it must no longer be highlighted in future popups.

Do not delete understood vocabulary.

---

# 12. Lookup Count

Every time a vocabulary item is encountered through the application's lookup mechanism:

```text
lookupCount += 1
```

The count should be associated with the canonical vocabulary item/lemma where possible.

Surface forms should map to the same vocabulary item.

Example:

```text
withdraw
withdrew
withdrawn
```

should normally map to:

```text
withdraw
```

The implementation should not attempt perfect linguistic morphology in the MVP. Use a sensible canonicalization strategy and allow the model/provider to supply the lemma.

---

# 13. Highlighting

Vocabulary that is still in `learning` state should be highlighted.

The visual intensity should increase with lookup count.

Do NOT use a linear relationship where:

```text
20 lookups = 20× stronger than 1 lookup
```

Use a bounded/logarithmic or bucketed scale.

Suggested levels:

```text
1 lookup       → level 1
2–3            → level 2
4–7            → level 3
8–15           → level 4
16–31          → level 5
32+            → level 6
```

The exact visual colors are implementation details.

Requirements:

- newly encountered vocabulary should be visually distinct;
- frequently encountered vocabulary should become progressively stronger;
- understood vocabulary should have no vocabulary highlight.

---

# 14. Translation Popup

After successful text extraction and translation/cache retrieval, display a small floating popup near the selected text when practical.

The popup should contain:

1. Original selected text.
2. Translation.
3. Vocabulary analysis.
4. Highlighted vocabulary.
5. Lookup counts for relevant vocabulary.
6. Ability to mark vocabulary as understood.

Example:

```text
The company withdrew its offer after negotiations failed.

The company rút lại đề nghị sau khi cuộc đàm phán thất bại.

withdraw × 7
negotiation × 2
```

Vocabulary should be highlighted inside the original English text where practical.

The popup should be lightweight and should not steal keyboard focus unnecessarily.

The user must be able to continue reading after dismissing it.

---

# 15. Sentence Cache

The application must cache translation results locally.

A normalized selected text should produce a deterministic cache key, such as a SHA-256 hash.

Normalization should at minimum:

- trim leading/trailing whitespace;
- normalize repeated whitespace;
- normalize Unicode where appropriate.

Example:

```text
"The company withdrew its offer."
```

and:

```text
"The company withdrew its offer.   "
```

should resolve to the same cache entry.

Cache schema conceptually:

```text
SentenceCache
--------------
id
textHash
normalizedText
translation
analysisJSON
createdAt
lastUsedAt
```

When an identical sentence is selected again:

```text
DB lookup
→ cache hit
→ no translation API call
```

The cached translation and vocabulary analysis should be reused.

---

# 16. Vocabulary Database

Conceptual schema:

```text
Vocabulary
----------
id
lemma
type
meaning
translation
lookupCount
status
firstSeenAt
lastSeenAt
```

Possible `type` values:

```text
word
phrase
phrasal_verb
idiom
collocation
```

The schema may be improved if implementation requires it.

---

# 17. Lookup History

Every lookup must be persisted.

Conceptual schema:

```text
Lookup
------
id
selectedText
normalizedText
sourceApplication
context
translation
createdAt
```

A lookup should preserve enough information to reconstruct what the user actually encountered.

Do not store only the vocabulary word.

The sentence/context is essential.

---

# 18. Vocabulary Occurrences

A vocabulary item can occur in many lookups.

Conceptual schema:

```text
VocabularyOccurrence
--------------------
id
vocabularyId
lookupId
surfaceForm
context
createdAt
```

This allows the dashboard to display real historical examples.

---

# 19. Dashboard

The dashboard must provide at least:

## Vocabulary list

Display:

- vocabulary item;
- meaning;
- lookup count;
- current status;
- first/last seen information where useful.

Example:

```text
ubiquitous       17    learning
nevertheless     11    learning
phase out         8    learning
facilitate        5    understood
```

## Vocabulary detail

When selecting a vocabulary item:

Display:

- canonical word/phrase;
- meaning;
- lookup count;
- status;
- historical contexts/sentences;
- date/time of occurrences;
- button to mark as understood.

Example:

```text
ubiquitous

Meaning:
existing everywhere

Lookups:
17

Contexts:

"Smartphones have become ubiquitous..."

"The technology is now ubiquitous..."

"Ubiquitous computing..."

[Mark as understood]
```

---

# 20. Cached History Must Work Offline

If a sentence has already been translated:

- selecting it again must not require an API connection;
- the cached translation should be displayed;
- cached vocabulary analysis should be displayed;
- lookup counts should still update locally.

The application should therefore remain useful for previously encountered material even when the translation provider is unavailable.

---

# 21. Cost Control

Minimize external API usage.

Required strategy:

```text
Exact sentence cache
        ↓
Vocabulary cache
        ↓
Only then external API
```

Never call the translation API merely because the same sentence has already been translated.

The API provider should receive known vocabulary information where useful so that already-understood vocabulary does not need to be repeatedly analyzed.

---

# 22. Privacy

All lookup history is local by default.

The application must not upload the user's entire reading history.

Only the currently processed text/context necessary for translation/analysis may be sent to the configured translation provider.

Do not add telemetry in the MVP.

---

# 23. Settings

MVP settings should be minimal.

At minimum:

- Enable/disable translation detection.
- Translation provider/API configuration.
- Maximum selected-text size if implemented.
- Launch at login if practical.

Do not build a large settings system.

---

# 24. Error Handling

The application must gracefully handle:

- Accessibility permission denied;
- Accessibility API unavailable;
- clipboard extraction failure;
- clipboard restoration failure;
- translation API failure;
- malformed API response;
- database failure;
- popup rendering failure;
- unsupported application.

Errors should not crash the background application.

The application should continue running after an individual lookup fails.

---

# 25. MVP Exclusions

Do NOT implement:

- user accounts;
- cloud sync;
- mobile application;
- browser extension;
- social features;
- shared vocabulary;
- multiplayer;
- spaced repetition;
- gamification;
- payment/subscription;
- web dashboard;
- remote database;
- complicated AI agents.

These may be future products but are outside the MVP.

---

# 26. Technical Quality Requirements

The code should be modular.

Recommended components:

```text
AccessibilityManager
ClipboardFallback
SelectionManager
TranslationProvider
TranslationService
CacheService
VocabularyService
LookupHistoryService
Database
PopupController
DashboardView
MenuBarController
SettingsView
```

Do not put all logic into one SwiftUI view.

Use protocols for external dependencies where practical.

The database layer must be independently testable.

The translation provider must be mockable.

---

# 27. Acceptance Criteria

The MVP is considered functional only when all of the following work:

### Selection

- [ ] Select an English word in Safari.
- [ ] Popup appears.
- [ ] Select an English sentence in Safari.
- [ ] Popup appears.
- [ ] Select text in VS Code.
- [ ] Popup appears.
- [ ] Select text in another supported application.
- [ ] Popup appears.
- [ ] Accessibility permission state is correctly handled.

### Clipboard fallback

- [ ] Fallback works when Accessibility selection is unavailable.
- [ ] Existing clipboard contents are preserved.
- [ ] Existing clipboard contents are restored after extraction.
- [ ] Clipboard is restored even when translation fails.

### Translation

- [ ] New text invokes the translation provider.
- [ ] Translation is displayed.
- [ ] Vocabulary is identified.
- [ ] Contextual meaning is preserved.

### Cache

- [ ] First lookup creates a cache entry.
- [ ] Repeating the exact same normalized text does not invoke the API.
- [ ] Cached translation is displayed.
- [ ] Cached vocabulary analysis is displayed.

### Vocabulary

- [ ] New vocabulary is stored.
- [ ] Lookup count increments.
- [ ] Morphological forms can map to a canonical lemma where supplied.
- [ ] Frequently encountered vocabulary receives stronger highlighting.
- [ ] Understood vocabulary is no longer highlighted.

### History

- [ ] Every lookup is persisted.
- [ ] Original selected text is preserved.
- [ ] Context is preserved.
- [ ] Historical contexts can be viewed from the dashboard.

### Dashboard

- [ ] Vocabulary list works.
- [ ] Lookup count is visible.
- [ ] Vocabulary detail works.
- [ ] Historical contexts are visible.
- [ ] "Mark as understood" works.
- [ ] Understood state persists after restarting the application.

### Persistence

- [ ] Close and reopen the application.
- [ ] Vocabulary remains.
- [ ] Lookup counts remain.
- [ ] Cache remains.
- [ ] History remains.

---

# 28. Implementation Priority

Implement in this order:

1. Native macOS application shell.
2. Menu-bar application.
3. Accessibility permission detection.
4. Accessibility selected-text extraction.
5. Clipboard fallback.
6. SQLite persistence.
7. Translation provider abstraction.
8. Translation API integration.
9. Sentence cache.
10. Vocabulary extraction/storage.
11. Lookup count.
12. Popup.
13. Highlighting.
14. Dashboard.
15. Mark-as-understood.
16. Error handling.
17. Automated tests.
18. Real macOS integration testing.
19. Polish only after all acceptance criteria pass.

Do not build the dashboard before the core lookup pipeline works.

---

# 29. Definition of Done

The application is not considered done merely because it compiles.

Done means:

```text
Build
→ Launch
→ Grant Accessibility permission
→ Select text in real applications
→ Extract text
→ Translate
→ Cache
→ Persist vocabulary
→ Display popup
→ Highlight vocabulary
→ Repeat lookup
→ Verify cache hit
→ Verify lookup count
→ Mark vocabulary understood
→ Restart app
→ Verify persistence
→ Test clipboard fallback
```

The implementation must be tested against actual macOS behavior, not only mocked APIs.
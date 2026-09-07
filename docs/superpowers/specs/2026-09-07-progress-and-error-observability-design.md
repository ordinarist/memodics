# Progress & Error Observability — Design

**Date:** 2026-09-07
**Status:** Approved (design), pending implementation plan

## Problem

Triggering a lookup (⌥⌘L hotkey or the "Translate Selection" menu item) sometimes
produces only a "tick" sound and shows nothing. The user has no way to tell what
happened.

Root cause (traced in `Sources/Memodics/App/AppDelegate.swift`):
`triggerLookup()` calls `NSSound.beep()` with **no visible feedback** when either
detection is disabled or `selectionManager.captureCurrentSelection()` returns `nil`
(Accessibility returned nothing AND the clipboard fallback found nothing
processable). Real translation errors do pop an `NSAlert`, but capture failures are
silent. Diagnostic output today is only scattered `NSLog` calls — there is no
persistent log to trace later.

## Goals

1. **Progress visibility** — the menu-bar icon changes while a lookup is in flight.
2. **Visible errors/status** — failures and previously-silent beep cases surface as
   native macOS notification banners.
3. **Traceable log file** — errors (and lookup lifecycle) are written to a log file
   on disk that the user can inspect later.

## Non-goals

- No spinner animation on the menu-bar icon (a static SF Symbol swap is enough).
- No change to the lookup pipeline / caching behavior.
- No telemetry or network logging — the log is local-only, consistent with the
  privacy constraints in `SPEC.md` §2/§22.

## Components

### 1. `FileLogger` (MemodicsCore — testable, AppKit-free)

New service in `Sources/MemodicsCore/Services/`, behind a `Logging` protocol so it is
mockable and the app can be tested without touching disk.

```swift
enum LogLevel: Int { case debug, info, warning, error }

protocol Logging {
    func log(_ level: LogLevel, _ message: String)
}
```

`FileLogger: Logging`:
- Writes one line per entry: `[<ISO8601 timestamp>] [<LEVEL>] <message>`.
- Appends to a file at a configurable path (injected, so tests use a temp path).
- Level filtering: entries below a configured minimum level are dropped.
- **Rotation:** before appending, if the file exceeds ~2 MB, move it to
  `<path>.1` (overwriting any previous `.1`) and start fresh. Single rollover.
- Append-safety: opens/creates the file and appends; never throws out to callers
  (logging failures must not affect app behavior).

Convenience helpers `logger.info(_:)`, `logger.warning(_:)`, `logger.error(_:)`
may wrap `log(_:_:)`.

**Default production path:** `~/Library/Logs/Memodics/memodics.log`
(standard macOS location, separate from the SQLite DB under Application Support).

### 2. `Notifying` + `UserNotifier` (app layer — thin, AppKit)

New protocol + implementation in `Sources/Memodics/App/` (or `UI/`).

```swift
protocol Notifying {
    func notify(title: String, body: String)
}
```

`UserNotifier: Notifying` wraps `UNUserNotificationCenter`:
- Requests authorization once at launch.
- Posts a banner per `notify(...)` call.
- **Fallback:** when the notification center is unavailable (e.g. running via
  `swift run`, which is not a bundled `.app`), fall back to `NSLog`; for hard
  errors it may additionally use the existing `NSAlert` path so nothing is lost.

Kept behind a protocol so `AppDelegate` routing can be unit-tested with a mock.

### 3. `MenuBarController.setBusy(_:)` (app layer)

- `setBusy(true)` swaps the status-item image to a distinct "busy" SF Symbol
  (e.g. `book` / `hourglass`).
- `setBusy(false)` restores the idle `book.closed` template icon.
- Idempotent and main-actor bound (already `@MainActor`).

### 4. `AppDelegate` wiring

`triggerLookup()` and the async `Task` become the single orchestration point:

```
trigger
  → logger.info("lookup start (source app)")
  → menuBar.setBusy(true)
  ├─ detection disabled  → notify("Detection is off", …) + logger.warning → setBusy(false)
  ├─ provider not set    → notify("Provider not configured", …) + logger.warning → setBusy(false) → open Settings
  ├─ capture == nil      → notify("No text selected", …) + logger.warning → setBusy(false)
  ├─ pipeline success    → popup.show(outcome) + logger.info("N vocab items") → setBusy(false)
  └─ pipeline throws      → notify("Translation failed", detail) + logger.error(error) → setBusy(false)
```

Every current `NSSound.beep()` in `triggerLookup()` is replaced by a
`notify(...)` + log. `presentError(...)` for the "database unavailable" and
"provider not configured" cases also routes through `notify` (and remains as an
`NSAlert` fallback only when notifications are unavailable). Existing `NSLog`
diagnostic calls in `AppDelegate`, `SelectionManager`, and other error paths are
migrated to the injected `Logging` instance.

The `FileLogger` and `UserNotifier` are constructed in
`applicationDidFinishLaunching` and injected where needed (assembled alongside the
existing services / `AppEnvironment`).

## Data flow (per lookup)

```
⌥⌘L / menu → AppDelegate.triggerLookup
  → log INFO "lookup start" → menuBar.setBusy(true)
    ├─ no selection → notify + log WARN → setBusy(false)
    ├─ success      → popup + log INFO → setBusy(false)
    └─ error        → notify + log ERROR(error) → setBusy(false)
```

## Testing

- **`FileLogger` — full TDD** in `Tests/MemodicsCoreTests/`:
  - line format (timestamp/level/message),
  - level filtering,
  - rotation at the size threshold (creates `.1`, truncates primary),
  - append across multiple calls,
  - logging never throws to the caller.
- **`Notifying` / `MenuBarController.setBusy` / `UserNotifier`** — the thin AppKit
  layer, verified by building and launching per the repo convention
  (`CLAUDE.md` → "The AppKit layer is deliberately thin"). Because `Notifying` and
  `Logging` are protocols, `AppDelegate`'s routing logic can be exercised with mocks
  if an app-level test is added.

## Decisions (defaults chosen)

- Log path: `~/Library/Logs/Memodics/memodics.log`.
- Rotation: single rollover at ~2 MB → `memodics.log.1`.
- Error surface: **native notification banner** (not a menu-bar badge), per user
  choice.
- **All** previously-silent beep cases become visible notifications, per user choice.

## Constraints honored

- Local-only, no network logging (SPEC §2/§22).
- Errors never crash the background app (SPEC §24) — logging and notification
  failures are swallowed.
- Business logic (`FileLogger`) lives in `MemodicsCore` behind a protocol; the
  AppKit layer stays thin.

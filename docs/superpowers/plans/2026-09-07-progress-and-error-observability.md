# Progress & Error Observability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make lookups observable — a busy menu-bar icon while translating, native notification banners for every error and previously-silent beep case, and a trace log file on disk.

**Architecture:** A testable `FileLogger` (behind a `Logging` protocol) lands in `MemodicsCore`. A thin `UserNotifier` (behind a `Notifying` protocol) wraps `UNUserNotificationCenter` in the app layer with an `NSLog` fallback when unbundled. `MenuBarController` gains a `setBusy(_:)` icon swap. `AppDelegate.triggerLookup()` becomes the single orchestration point routing start/success/failure through the logger, notifier, and busy state — replacing scattered `NSSound.beep()` / `NSLog` calls.

**Tech Stack:** Swift 5, XCTest, AppKit, UserNotifications, `MemodicsCore` (SwiftPM).

---

## File Structure

- Create `Sources/MemodicsCore/Services/Logging.swift` — `LogLevel`, `Logging` protocol, convenience helpers.
- Create `Sources/MemodicsCore/Services/FileLogger.swift` — file-backed `Logging` with format + rotation.
- Create `Tests/MemodicsCoreTests/FileLoggerTests.swift` — full TDD for `FileLogger`.
- Create `Sources/Memodics/App/UserNotifier.swift` — `Notifying` protocol + `UserNotifier`.
- Modify `Sources/Memodics/App/MenuBarController.swift` — add `setBusy(_:)`.
- Modify `Sources/Memodics/App/AppDelegate.swift` — construct logger/notifier, rewire `triggerLookup()`, migrate `NSLog`.

---

## Task 1: `LogLevel` + `Logging` protocol (MemodicsCore)

**Files:**
- Create: `Sources/MemodicsCore/Services/Logging.swift`
- Test: covered indirectly; exercised by `FileLoggerTests` in Task 2.

- [ ] **Step 1: Create the protocol and level type**

```swift
// Sources/MemodicsCore/Services/Logging.swift
import Foundation

/// Severity of a log entry. Ordered so callers can filter by minimum level.
public enum LogLevel: Int, Comparable {
    case debug = 0, info, warning, error

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Fixed-width-ish label used in log lines.
    public var label: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARN"
        case .error: return "ERROR"
        }
    }
}

/// A sink for diagnostic log entries. Mockable so the app never needs real disk
/// I/O in tests. Implementations must never throw or crash the caller (SPEC §24).
public protocol Logging {
    func log(_ level: LogLevel, _ message: String)
}

public extension Logging {
    func debug(_ message: String) { log(.debug, message) }
    func info(_ message: String) { log(.info, message) }
    func warning(_ message: String) { log(.warning, message) }
    func error(_ message: String) { log(.error, message) }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: builds successfully (no references yet).

- [ ] **Step 3: Commit**

```bash
git add Sources/MemodicsCore/Services/Logging.swift
git commit -m "feat(core): add Logging protocol and LogLevel"
```

---

## Task 2: `FileLogger` (MemodicsCore, TDD)

**Files:**
- Create: `Sources/MemodicsCore/Services/FileLogger.swift`
- Test: `Tests/MemodicsCoreTests/FileLoggerTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/MemodicsCoreTests/FileLoggerTests.swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter FileLoggerTests`
Expected: FAIL — "cannot find 'FileLogger' in scope".

- [ ] **Step 3: Implement `FileLogger`**

```swift
// Sources/MemodicsCore/Services/FileLogger.swift
import Foundation

/// Appends leveled, timestamped log lines to a file on disk, with a single
/// size-based rollover. All work is serialized on a private queue and every
/// failure is swallowed — logging must never affect app behavior (SPEC §24).
public final class FileLogger: Logging {

    private let fileURL: URL
    private let rolledURL: URL
    private let minimumLevel: LogLevel
    private let maxBytes: Int
    private let queue = DispatchQueue(label: "com.memodics.filelogger")
    private let dateProvider: () -> Date

    public init(fileURL: URL,
                minimumLevel: LogLevel = .info,
                maxBytes: Int = 2 * 1024 * 1024,
                dateProvider: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL
        self.rolledURL = URL(fileURLWithPath: fileURL.path + ".1")
        self.minimumLevel = minimumLevel
        self.maxBytes = maxBytes
        self.dateProvider = dateProvider
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
    }

    public func log(_ level: LogLevel, _ message: String) {
        guard level >= minimumLevel else { return }
        let line = "[\(timestamp())] [\(level.label)] \(message)\n"
        queue.sync {
            rotateIfNeeded()
            append(line)
        }
    }

    // MARK: - Private

    private lazy var formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private func timestamp() -> String {
        formatter.string(from: dateProvider())
    }

    private func rotateIfNeeded() {
        let fm = FileManager.default
        guard let size = try? fm.attributesOfItem(atPath: fileURL.path)[.size] as? Int,
              size >= maxBytes else { return }
        try? fm.removeItem(at: rolledURL)
        try? fm.moveItem(at: fileURL, to: rolledURL)
    }

    private func append(_ line: String) {
        let fm = FileManager.default
        guard let data = line.data(using: .utf8) else { return }
        // Ensure the directory exists (nested paths, first write).
        try? fm.createDirectory(at: fileURL.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        if fm.fileExists(atPath: fileURL.path),
           let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter FileLoggerTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MemodicsCore/Services/FileLogger.swift Tests/MemodicsCoreTests/FileLoggerTests.swift
git commit -m "feat(core): add FileLogger with rotation (TDD)"
```

---

## Task 3: `Notifying` + `UserNotifier` (app layer)

**Files:**
- Create: `Sources/Memodics/App/UserNotifier.swift`

This is thin AppKit/UserNotifications glue — verified by building (Task 6), not unit-tested (per `CLAUDE.md`: the AppKit layer is deliberately thin).

- [ ] **Step 1: Create the notifier**

```swift
// Sources/Memodics/App/UserNotifier.swift
import AppKit
import UserNotifications

/// Presents short user-facing status/error messages. Mockable so AppDelegate
/// routing can be tested without the real notification center.
protocol Notifying {
    func notify(title: String, body: String)
}

/// Posts native macOS banners via UNUserNotificationCenter. When the process is
/// not a bundled `.app` (e.g. `swift run`), the notification center is unusable,
/// so it falls back to NSLog. Never throws to the caller (SPEC §24).
final class UserNotifier: Notifying {

    /// UNUserNotificationCenter.current() traps unless the process is a proper
    /// app bundle. Detect that up front and route around it when unbundled.
    private let isBundledApp = Bundle.main.bundleURL.pathExtension == "app"

    init() {
        guard isBundledApp else { return }
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notify(title: String, body: String) {
        guard isBundledApp else {
            NSLog("Memodics notify: \(title) — \(body)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: "\(title)-\(body.hashValue)",
            content: content,
            trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { NSLog("Memodics notify failed: \(error)") }
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: builds successfully.

- [ ] **Step 3: Commit**

```bash
git add Sources/Memodics/App/UserNotifier.swift
git commit -m "feat(app): add Notifying protocol and UserNotifier"
```

---

## Task 4: `MenuBarController.setBusy(_:)` (app layer)

**Files:**
- Modify: `Sources/Memodics/App/MenuBarController.swift`

- [ ] **Step 1: Add the busy-state method**

Add this method to `MenuBarController` (e.g. right after `init`, before `menuNeedsUpdate`):

```swift
    /// Swap the status-item icon to reflect an in-flight lookup. `book.closed`
    /// is the idle icon (matching init); `book` (open) signals "translating".
    func setBusy(_ busy: Bool) {
        guard let button = statusItem.button else { return }
        let symbol = busy ? "book" : "book.closed"
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Memodics")
        button.image?.isTemplate = true
    }
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: builds successfully.

- [ ] **Step 3: Commit**

```bash
git add Sources/Memodics/App/MenuBarController.swift
git commit -m "feat(app): add busy-state icon swap to MenuBarController"
```

---

## Task 5: Wire logging, notifications, and busy state into `AppDelegate`

**Files:**
- Modify: `Sources/Memodics/App/AppDelegate.swift`

- [ ] **Step 1: Add logger and notifier stored properties**

In `AppDelegate`, add these next to the existing `settings` / `accessibility`
properties (top of the class):

```swift
    private let logger: Logging = FileLogger(
        fileURL: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Memodics/memodics.log"))
    private let notifier: Notifying = UserNotifier()
```

- [ ] **Step 2: Replace `triggerLookup()` entirely**

Replace the whole existing `triggerLookup()` method with:

```swift
    private func triggerLookup() {
        logger.info("Lookup triggered")

        guard settings.detectionEnabled else {
            notifier.notify(title: "Detection is off",
                            body: "Enable Detection from the Memodics menu to translate.")
            logger.warning("Lookup skipped: detection disabled")
            return
        }
        guard let environment else {
            notifier.notify(title: "Not ready",
                            body: "The local database is unavailable.")
            logger.error("Lookup skipped: database unavailable")
            return
        }
        guard settings.isProviderConfigured else {
            notifier.notify(title: "Translation provider not configured",
                            body: "Add your API key in Settings to enable translation.")
            logger.warning("Lookup skipped: provider not configured")
            settingsWindow.show()
            return
        }

        guard let selection = selectionManager.captureCurrentSelection() else {
            notifier.notify(title: "No text selected",
                            body: "Select English text in another app, then try again.")
            logger.warning("Lookup skipped: no processable selection captured")
            return
        }

        menuBar.setBusy(true)
        logger.info("Lookup start (source: \(selection.sourceApplication ?? "unknown"))")
        Task { @MainActor in
            defer { self.menuBar.setBusy(false) }
            do {
                let outcome = try await environment.pipeline.lookup(
                    rawText: selection.text,
                    sourceApplication: selection.sourceApplication)
                self.popup.show(outcome: outcome)
                self.logger.info("Lookup success")
            } catch {
                self.notifier.notify(title: "Translation failed", body: "\(error)")
                self.logger.error("Lookup failed: \(error)")
            }
        }
    }
```

- [ ] **Step 3: Log the database-open failure at launch**

In `applicationDidFinishLaunching`, in the `catch` where the database fails to
open, add a log line alongside the existing `presentError`:

```swift
        } catch {
            logger.error("Database open failed: \(error)")
            presentError("Could not open the local database", detail: "\(error)")
        }
```

- [ ] **Step 4: Migrate the launch-at-login NSLog to the logger**

Replace the `NSLog("Memodics: launch-at-login update failed: \(error)")` line in
`applyLaunchAtLogin` with:

```swift
            logger.error("Launch-at-login update failed: \(error)")
```

- [ ] **Step 5: Build to verify it compiles**

Run: `swift build`
Expected: builds successfully.

- [ ] **Step 6: Run the full test suite (no regressions)**

Run: `swift test`
Expected: PASS — existing 59 tests plus the 5 new `FileLoggerTests` = 64.

- [ ] **Step 7: Commit**

```bash
git add Sources/Memodics/App/AppDelegate.swift
git commit -m "feat(app): route lookup flow through logger, notifier, busy state"
```

---

## Task 6: Manual build-and-launch verification

**Files:** none (verification only).

`Notifying`, `UserNotifier`, and the busy icon are the thin AppKit layer and can't
be unit-tested headlessly — verify against real behavior per `CLAUDE.md`.

- [ ] **Step 1: Assemble the app bundle** (notifications require a real `.app`)

Run: `./scripts/build-app.sh release`
Expected: `build/Memodics.app` is produced.

- [ ] **Step 2: Launch and observe**

Run: `open build/Memodics.app`

Verify:
- Trigger ⌥⌘L with **no selection** → a "No text selected" banner appears (not just a beep).
- Select English text in Safari, trigger ⌥⌘L → the menu-bar icon changes to the busy symbol while translating, then reverts; the popup appears.
- With detection toggled off → triggering shows "Detection is off".

- [ ] **Step 3: Confirm the log file is written**

Run: `cat ~/Library/Logs/Memodics/memodics.log`
Expected: timestamped `[INFO]/[WARN]/[ERROR]` lines matching the actions above.

- [ ] **Step 4: Update ACCEPTANCE/README if applicable**

If `ACCEPTANCE.md` or `README.md` reference the beep-only behavior or the log
location, update them. Commit any doc changes:

```bash
git add -A
git commit -m "docs: note progress icon, notifications, and log file"
```

---

## Self-Review Notes

- **Spec coverage:** menu-bar busy icon (Task 4 + 5), native banners for errors and
  all previously-silent beep cases (Task 5), file trace log at
  `~/Library/Logs/Memodics/memodics.log` with rotation (Tasks 1–2, wired in 5).
- **`swift run` fallback:** `UserNotifier.isBundledApp` guards the notification
  center; manual verification uses the `.app` bundle (Task 6).
- **Type consistency:** `Logging.log(_:_:)`, `FileLogger(fileURL:minimumLevel:maxBytes:dateProvider:)`,
  `Notifying.notify(title:body:)`, and `MenuBarController.setBusy(_:)` are used
  identically wherever referenced.

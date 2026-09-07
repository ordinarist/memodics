<p align="center">
  <img src="Icon.png" alt="Memodics" width="128" height="128">
</p>

<h1 align="center">Memodics</h1>

<p align="center">A native macOS menu-bar assistant that helps you learn English while you read.</p>

---

Select English text in **any** app, invoke Memodics, and it translates the text,
identifies vocabulary worth learning, remembers every lookup **locally**, and
highlights words more strongly the more often you look them up — until you mark
them *understood*, at which point they stop being highlighted.

It's a personal, **local-only** reading-memory system: no account, no server, no
telemetry. Your reading history never leaves your Mac; only the text you're
actively looking up is sent to the translation provider you configure.

## Features

- 🔎 **Translate any selection** — a word, a sentence, or a paragraph, from any app.
- 🧠 **Remembers everything** — every lookup is stored with its full context.
- 🎯 **Adaptive highlighting** — vocabulary gets visually stronger the more you
  encounter it (bucketed, not linear); *understood* words stop highlighting.
- 🗂 **Vocabulary dashboard** — searchable, filterable, with real historical
  contexts for each word.
- 💸 **Cost-aware** — an exact-sentence cache means re-reading the same text
  never calls the API again (and still works offline).
- 🔒 **Private by design** — history in local SQLite; API key in the macOS Keychain.

## Requirements

- macOS 14 (Sonoma) or later
- An OpenAI-compatible chat-completions endpoint + API key (configured in-app)

## Installation

### Option A — Download the release

1. Download `Memodics.zip` from the [latest release](https://github.com/ordinarist/memodics/releases/latest).
2. Unzip and move **Memodics.app** to `/Applications`.
3. The build is signed ad-hoc (not notarized), so on first launch macOS Gatekeeper
   will warn. Either **right-click the app → Open → Open**, or clear the quarantine
   flag once from Terminal:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Memodics.app
   ```
4. Launch it — a 📖 icon appears in your menu bar.

### Option B — Build from source

```bash
git clone https://github.com/ordinarist/memodics.git
cd memodics
./scripts/build-app.sh release
open build/Memodics.app
```

Or run directly for development: `swift run Memodics`.

## First-run setup

1. Menu bar → **Settings…** → paste your API key, pick a **target language**
   (default: Vietnamese), optionally set the model/endpoint.
2. Grant **Accessibility** permission when prompted (menu → *Grant Accessibility
   Permission…* → enable Memodics in System Settings ▸ Privacy & Security ▸
   Accessibility). This lets Memodics read the text you select in other apps.

## Usage

1. Select English text in any app (Safari, VS Code, Preview, …).
2. Press **⌥⌘L** (or menu bar → *Translate Selection*).
3. A popup shows the translation, with vocabulary highlighted in both the original
   and the translation. Mark words *understood* to stop highlighting them.
4. Open the **Vocabulary Dashboard** to browse everything you've looked up.

### Why a hotkey instead of automatic detection?

macOS provides no reliable, battery-friendly, cross-application "selection changed"
event without attaching per-app Accessibility observers (and many apps emit
nothing). Rather than fake a capability the OS doesn't support, Memodics uses an
**on-demand** trigger (global hotkey + menu item) that reads the *current*
selection — preserving the intended behavior through a supported mechanism.

## How it works

Selection is captured via the Accessibility API (with a clipboard fallback that
always restores your clipboard exactly). The lookup pipeline is cost-controlled:

```
normalize → sentence-cache check → (API only on a miss) → store cache
          → persist lookup → update vocabulary counts → render popup
```

Data lives in `~/Library/Application Support/Memodics/memodics.sqlite`.

The codebase is split into a pure, unit-tested core (`MemodicsCore`) and a thin
AppKit/SwiftUI layer (`Memodics`). See [`SPEC.md`](SPEC.md) for the full product
specification and [`ACCEPTANCE.md`](ACCEPTANCE.md) for verification status.

## Development

```bash
swift build     # build
swift test      # run the test suite
```

## Privacy & security

All lookup history is stored locally. Only the currently-processed selection is
sent to your configured translation provider. The API key is stored in the macOS
**Keychain** (encrypted, access-controlled), never in plaintext. No telemetry, no
cloud sync, no accounts.

## License

Copyright © The Ordinarist Company, Ltd. All rights reserved.

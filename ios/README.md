# Evenly for iOS

A native SwiftUI app for Evenly. It runs in one of two modes, chosen in Settings:

- **This iPhone** (default for new installs): groups are saved on the phone itself. No Mac, server or network needed, so it works offline and anywhere. Groups can't be shared in this mode. The data lives in Application Support, so it is included in iCloud and computer backups.
- **Evenly server**: groups live on an Evenly server, so web and iPhone users can share one group by link.

Both modes use the same rules. The on-device store (`LocalBackend.swift`, `Ledger.swift`) is a Swift port of the server's validation, rounding and settle-up algorithm, and a parity test runs one scenario on both and requires identical results. Server groups already opened on the phone can be copied onto it from Settings.

## Features

- Create groups, or join one by pasting an invite link (`http://host:4173/g/<id>` or `evenly://g/<id>`)
- Add and edit expenses with all four split modes and a live preview that uses the same rounding as the server
- "Which one are you?" personal summary with one-tap "Settle"
- Balances with diverging bars, suggested payments, day-grouped activity with search and filters
- Offline on-device mode with no server, as well as server mode
- Live sync in server mode: polls every 12 seconds with ETags, refreshes when the app returns to the foreground, and pauses while you edit
- Group settings: rename, currency, add, rename or remove people, delete the group
- CSV export through the share sheet
- Light and dark mode, Dynamic Type friendly layouts, VoiceOver labels, haptics on save

## Requirements

- Xcode 16 or newer (the project uses synchronized folder groups)
- iOS 17 or newer
- An Evenly server only if you use server mode (see the main README)

## Run it

```bash
npm start                     # from the repository root, in one terminal
open ios/Evenly.xcodeproj     # then press Run in Xcode
```

In the default "This iPhone" mode nothing else is needed. For server mode, the simulator reaches the server at `http://127.0.0.1:4173`. To use the app on a real iPhone, start the server with `HOST=0.0.0.0 npm start` and enter your computer's address (for example `http://192.168.1.20:4173`) in the app's settings.

## Tests

```bash
xcodebuild test -project ios/Evenly.xcodeproj -scheme Evenly \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Unit tests cover money parsing and formatting, split previews, invite link parsing, JSON decoding, the on-device store (splits, validation, persistence across restarts, CSV) and storage-mode switching. `LocalBackendTests.testParityWithRunningServer` runs the same scenario on the on-device store and a real server and requires identical balances, transfers and shares. `APITests.testEndToEndAgainstRunningServer` drives a real server through a full create, spend, settle and delete cycle. It is skipped when no server is running; set `EVENLY_TEST_SERVER` to point it elsewhere.

## Layout

```
Evenly/
  EvenlyApp.swift          app entry, deep links
  Models/                  API models, money math, split preview, invite links
  Models/Ledger.swift      Swift port of the server's split and settle-up logic
  Services/                backend protocol, on-device store, API client, app state, per-group store
  Design/                  colour tokens, typography, shared components
  Views/                   home, create, join, group, expense, payment, settings
EvenlyTests/               XCTest suites
scripts/make-icon.swift    renders the app icon
```

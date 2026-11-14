# Evenly for iOS

A native SwiftUI client for the Evenly server. It talks to the same HTTP API as the web app, so web and iPhone users can share one group.

## Features

- Create groups, or join one by pasting an invite link (`http://host:4173/g/<id>` or `evenly://g/<id>`)
- Add and edit expenses with all four split modes and a live preview that uses the same rounding as the server
- "Which one are you?" personal summary with one-tap "Settle"
- Balances with diverging bars, suggested payments, day-grouped activity with search and filters
- Live sync: polls every 12 seconds with ETags, refreshes when the app returns to the foreground, and pauses while you edit
- Group settings: rename, currency, add, rename or remove people, delete the group
- CSV export through the share sheet
- Light and dark mode, Dynamic Type friendly layouts, VoiceOver labels, haptics on save

## Requirements

- Xcode 16 or newer (the project uses synchronized folder groups)
- iOS 17 or newer
- A running Evenly server (see the main README)

## Run it

```bash
npm start                     # from the repository root, in one terminal
open ios/Evenly.xcodeproj     # then press Run in Xcode
```

The simulator reaches the server at `http://127.0.0.1:4173`, which is the default. To use the app on a real iPhone, start the server with `HOST=0.0.0.0 npm start` and enter your computer's address (for example `http://192.168.1.20:4173`) in the app's settings.

## Tests

```bash
xcodebuild test -project ios/Evenly.xcodeproj -scheme Evenly \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Unit tests cover money parsing and formatting, split previews, invite link parsing and JSON decoding. `APITests.testEndToEndAgainstRunningServer` drives a real server through a full create, spend, settle and delete cycle. It is skipped when no server is running; set `EVENLY_TEST_SERVER` to point it elsewhere.

## Layout

```
Evenly/
  EvenlyApp.swift          app entry, deep links
  Models/                  API models, money math, split preview, invite links
  Services/                API client, app state, per-group store with polling
  Design/                  colour tokens, typography, shared components
  Views/                   home, create, join, group, expense, payment, settings
EvenlyTests/               XCTest suites
scripts/make-icon.swift    renders the app icon
```

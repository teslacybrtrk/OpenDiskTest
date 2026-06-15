# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

OpenDiskTest is a macOS native desktop application (SwiftUI, macOS 14.5+) that benchmarks disk performance through sequential and random read/write operations, visualizing results with charts.

## Build & Run

This is an Xcode project — open it in Xcode or use `xcodebuild`:

```bash
# Open in Xcode
open OpenDiskTest.xcodeproj

# Build from command line (requires full Xcode installation)
xcodebuild -project OpenDiskTest.xcodeproj -scheme OpenDiskTest -configuration Debug build
xcodebuild -project OpenDiskTest.xcodeproj -scheme OpenDiskTest -configuration Release build
```

To produce a distributable unsigned adhoc zip locally (similar to CI):

```bash
xcodebuild -project OpenDiskTest.xcodeproj -scheme OpenDiskTest -configuration Release \
  -derivedDataPath build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
codesign --force --deep --sign - build/Build/Products/Release/OpenDiskTest.app
ditto -c -k --keepParent build/Build/Products/Release/OpenDiskTest.app OpenDiskTest.zip
```

**Important:** When making code changes, always commit, push, create a PR, and merge it to trigger a build. This is the workflow for validating changes since the CI pipeline builds on merge. Do this whenever you reach a point where changes are ready to test.

The GitHub Actions workflow now triggers on both `push` to main (full release) **and** `pull_request` (build + test only, no release publish). PRs provide early validation.

## Tests

```bash
# Run all tests
xcodebuild -project OpenDiskTest.xcodeproj -scheme OpenDiskTest test

# Run a single test method
xcodebuild -project OpenDiskTest.xcodeproj -scheme OpenDiskTest test -only-testing:OpenDiskTestTests/OpenDiskTestTests/testExample
```

No linting tools are configured in this project.

## Architecture

**Pattern:** MVVM.

**Core files:**

1. `OpenDiskTestApp.swift` — `@main` entry point; creates `DiskSpeedTestViewModel` as a `@StateObject` and injects it into `ContentView`. Also wires `UpdateChecker` and the "Activity Log" window + menu command.

2. `DiskSpeedTestViewModel.swift` — All business logic + persistence. `ObservableObject` with `@Published` for `fileSize`, `iterations`, `isRunning`, `results`, `logs`, `testDirectory` (URL?, nil = temp dir). Disk I/O on background `DispatchQueue.global(qos: .userInitiated)`. Test file lives in either NSTemporaryDirectory or a user-chosen (bookmarked) directory. `TestResult` computes min/avg/max + maintains sortedSpeeds for the chart. Settings persisted via UserDefaults (size, iterations, bookmark data). `canStartTests` + guard for validation. Stop checks inside random I/O loops.

3. `ContentView.swift` — View layer + many small subviews (`TestCard`, `SpeedDistributionChart`, `IntegratedLogView`, `InputField`, `ControlButton`, `StatCell`). Location picker uses SwiftUI `.fileImporter` + folder button + reset. Run button is disabled for invalid params. Dark theme + per-test accent colors. Update banner safely opens the GitHub releases page (no more in-app destructive swap).

**Threading model:** All disk I/O on `DispatchQueue.global(qos: .userInitiated)`; UI updates + @Published via `DispatchQueue.main.async`. Stop flag checked between iterations (and inside random chunk loops for better responsiveness).

**Persistence & Directory selection:** UserDefaults for scalars + `bookmarkData(options: .withSecurityScope)` for custom test dirs (robust even if app is later sandboxed). Security-scoped resource access is started/stopped appropriately.

**Sandbox & Security:** The app is **not sandboxed** (ENABLE_APP_SANDBOX = NO). This enables flexible test directory selection (any user-writable volume or folder) without extra entitlements or powerbox prompts. Only outgoing network access (`com.apple.security.network.client`) is declared for the GitHub update checker. All I/O goes to either the system temp dir or an explicitly user-chosen directory.

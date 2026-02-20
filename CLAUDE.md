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

**Important:** When making code changes, always commit, push, create a PR, and merge it to trigger a build. This is the workflow for validating changes since the CI pipeline builds on merge. Do this whenever you reach a point where changes are ready to test.

## Tests

```bash
# Run all tests
xcodebuild -project OpenDiskTest.xcodeproj -scheme OpenDiskTest test

# Run a single test method
xcodebuild -project OpenDiskTest.xcodeproj -scheme OpenDiskTest test -only-testing:OpenDiskTestTests/OpenDiskTestTests/testExample
```

No linting tools are configured in this project.

## Architecture

**Pattern:** MVVM with Combine for reactivity.

**Three-file core:**

1. `OpenDiskTestApp.swift` — `@main` entry point; creates `DiskSpeedTestViewModel` as a `@StateObject` and injects it into `ContentView`.

2. `DiskSpeedTestViewModel.swift` — All business logic. An `ObservableObject` with `@Published` properties (`fileSize`, `iterations`, `isRunning`, `results`, `logs`). Runs disk I/O on a background `DispatchQueue` and dispatches UI updates back to the main thread. The four test methods (`sequentialWrite`, `sequentialRead`, `randomWrite`, `randomRead`) write/read a temp file in `FileManager.default.temporaryDirectory`, measuring MB/s for each iteration. Results are stored in `TestResult` structs (which auto-compute min/avg/max from a speeds array).

3. `ContentView.swift` — Pure view layer; reads from the ViewModel's published properties. Contains subviews: `TestCard`, `SpeedDistributionChart` (uses Apple Charts framework), `IntegratedLogView`, `InputField`, `ControlButton`, and `StatCell`. Defines a dark theme with hardcoded hex colors and per-test-type accent colors.

**Threading model:** All disk I/O runs on `DispatchQueue.global(qos: .userInitiated)`; all `@Published` mutations happen via `DispatchQueue.main.async`.

**Sandbox:** The app runs sandboxed (`com.apple.security.app-sandbox = true`) with read-only user-selected file access. Temp directory writes are allowed implicitly.

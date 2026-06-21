# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

OpenDiskTest is a macOS native desktop application (SwiftUI, macOS 14.5+) that benchmarks disk performance through sequential and random read/write operations, visualizing results with charts.

Beyond the core benchmark it offers: cache-bypass (`F_NOCACHE`) for true device speed, configurable I/O block size (4K/64K/1M), configurable queue depth (multithreaded random I/O, QD1–32), IOPS and latency (avg + p99) for random tests, a drive info panel (model, SSD/HDD, connection, filesystem, capacity), a sustained-write test with a live throughput-over-time graph, integrity verification (pattern write/read-back), a free-space safety guard, one-click presets, a persisted run history, PNG/clipboard export of results, background-completion notifications, a light/dark/system appearance toggle, and a one-click in-app self-updater.

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
xcodebuild -project OpenDiskTest.xcodeproj -scheme OpenDiskTest test -only-testing:OpenDiskTestTests/OpenDiskTestTests/testTestResultComputesMinAvgMaxAndSorted
```

No linting tools are configured in this project.

## Architecture

**Pattern:** MVVM.

**Core files:**

1. `OpenDiskTestApp.swift` — `@main` entry point; creates `DiskSpeedTestViewModel` as a `@StateObject` and injects it into `ContentView`. Also wires `UpdateChecker` and registers three auxiliary `Window` scenes: "Activity Log" (id `log`), "Benchmark History" (id `history`), and "Sustained Write" (id `sustained`), opened via toolbar buttons / `openWindow`.

2. `DiskSpeedTestViewModel.swift` — All business logic + persistence. `ObservableObject` with `@Published` for `fileSize`, `iterations`, `blockSizeKB`, `bypassCache`, `queueDepth`, `isRunning`, `results`, `logs`, `testDirectory` (URL?, nil = temp dir), `driveInfo`, `history`, the sustained-write state (`sustainedRunning`/`sustainedSamples`/`sustainedDuration`/`sustainedStatus`), and the verify state (`verifying`/`verifyProgress`/`verifyResult`/`verifyPassed`). Disk I/O on background `DispatchQueue.global(qos: .userInitiated)`. Test file lives in either NSTemporaryDirectory or a user-chosen (bookmarked) directory. Also defines the value types `Measurement` (MB/s + IOPS + per-op latencies), `TestResult` (min/avg/max + `iopsSamples`/`avgIOPS` + `latencyMs`/`avgLatency`/`p99Latency` + sortedSpeeds), `SustainedSample`, `DriveInfo`, `BenchmarkPreset`, and `BenchmarkRun`. Settings persisted via UserDefaults (size, iterations, block size, queue depth, cache flag, sustained duration, bookmark data, history JSON). `canStartTests` + guard for validation. Stop checks inside the I/O loops. (See **Benchmark engine**, **Drive info**, **Presets & history**, **Sustained write**, **Integrity & free space** below.)

3. `ContentView.swift` — View layer + many small subviews (`TestCard`, `LiveBadge`, `SpeedDistributionChart`, `HistoryView`/`HistoryRow`, `SustainedView`, `LogWindowView`, `IntegratedLogView`, `InputField`, `ControlButton`, `StatCell`). Layout: a slim **app bar** (logo + version/update badge | appearance picker + a secondary-tools cluster: Verify, Sustained, History, Log), a grouped **configuration card** (File Size, Iterations, Block Size, Queue Depth, cache toggle as labeled cells + presets row + the primary Run/Stop button), and a **drive + target card** (drive info + the `.fileImporter` location chooser). Results header has **Copy Results** (clipboard) and **Export PNG** (`ImageRenderer` → Downloads) buttons; random `TestCard`s show IOPS + latency (avg/p99). The `Theme` enum exposes appearance-aware **dynamic** neutral colors (`background`/`card`/`cardInner`/`border`/`secondaryText`/`primaryText`) plus fixed per-test accent colors. Update + verify banners render under the app bar. The update banner shows the available release name + "Update & Relaunch" (notes in tooltip), with live download/install status driven by `UpdateChecker`.

4. `UpdateChecker.swift` — `@MainActor ObservableObject` that drives the in-app updater (see **Updates** below). Compares the build-time `BuildInfo.commitSHA` against the SHA parsed from the `latest` GitHub release title, downloads + installs in place, and routes events into the Activity Log via an injected `logHandler` closure (wired in `OpenDiskTestApp`).

**Threading model:** All disk I/O on `DispatchQueue.global(qos: .userInitiated)`; UI updates + @Published via `DispatchQueue.main.async`. Stop flag checked between iterations (and inside random chunk loops for better responsiveness).

**Persistence & Directory selection:** UserDefaults for scalars + `bookmarkData(options: .withSecurityScope)` for custom test dirs (robust even if app is later sandboxed). Security-scoped resource access is started/stopped appropriately.

**Benchmark engine:** The operations run on `FileHandle`. When `bypassCache` is on (default), `fcntl(fd, F_NOCACHE, 1)` disables the OS cache so results reflect the device, not RAM, and writes are `fsync`'d. `blockSizeBytes` (from `blockSizeKB` ∈ {4, 64, 1024}) is the streaming chunk for sequential and the unit for random; random offsets are **block-aligned** for correct `F_NOCACHE` behavior. Sequential tests stream single-threaded. **Random** tests run via `randomWorkload(url:write:fileSize:)` across `queueDepth` (∈ {1,2,4,8,16,32}) concurrent workers (`DispatchQueue.concurrentPerform`), each with its own `FileHandle` seeking independently — exposing the parallelism NVMe SSDs need; each op is individually timed for **latency** (avg + p99). Each operation returns a `Measurement` (MB/s + optional IOPS + per-op latencies); random tests populate `iopsSamples`/`avgIOPS` and `latencyMs`. A run is appended to `history` only on **natural completion** (a user Stop is not recorded).

**Drive info:** `DriveInfo.load(for:)` runs off-main and gathers volume name/capacity/free (`URLResourceValues`), filesystem + BSD device (`statfs`), connection + model (**DiskArbitration** `DADiskCopyDescription`), and SSD-vs-HDD (**IOKit** "Medium Type"). `IOKit`/`DiskArbitration` auto-link via `import`. Refreshed on launch and whenever the test location changes.

**Presets & history:** `BenchmarkPreset.all` (Quick/Default/Thorough/4K IOPS/NVMe) sets size/iterations/block/**queue depth** in one tap. Completed runs are encoded to JSON in UserDefaults (last 50) and shown in the History window (per-test avg MB/s, IOPS, p99 latency). `BenchmarkRun` has a custom `init(from:)` so history saved before `queueDepth` existed still decodes (defaults to 1).

**Sustained write:** `startSustainedWrite()` writes 1 MB blocks continuously to a bounded ring-buffer file (sized to free space, 256 MB–4 GB) for `sustainedDuration` seconds, sampling throughput ~2×/sec into `sustainedSamples`. Because total bytes far exceed any SSD's SLC write cache, the `SustainedView` live line chart reveals the cache cliff and thermal throttling; `sustainedSummary` flags throttling when the low dips below 70% of peak. Honors cache-bypass; posts a completion notification when backgrounded; temp file removed afterward.

**Integrity & free space:** `verifyIntegrity()` writes a known pattern across a `fileSize`-MB file, reads it back block-by-block and compares (catching bad sectors / corruption), surfacing a progress + pass/fail banner. `availableBytes(at:)` (via `volumeAvailableCapacityForImportantUsage`) backs a **free-space guard** that aborts `runTests`/verify rather than writing more than ~90% of free space.

**Appearance:** `@AppStorage("appearanceMode")` (system/light/dark) drives the whole app via `NSApp.appearance`; `Theme`'s neutral colors are dynamic `NSColor`s that resolve to the effective appearance, so call sites need no changes. Text on fixed colored surfaces (gradient buttons, update banner, control buttons) stays literal white.

**Notifications:** On background completion the VM posts a local `UNUserNotification` (authorization requested at launch). No special entitlement needed since the app is not sandboxed.

**Sandbox & Security:** The app is **not sandboxed** (ENABLE_APP_SANDBOX = NO). This enables flexible test directory selection (any user-writable volume or folder) without extra entitlements or powerbox prompts. Only outgoing network access (`com.apple.security.network.client`) is declared for the GitHub update checker. All I/O goes to either the system temp dir or an explicitly user-chosen directory.

**Updates:** The app is unsigned / not notarized, but still does a true **one-click in-place self-update** (no drag, no Gatekeeper prompt). Because the app is not sandboxed and downloads + extracts the update itself, the new bundle is never quarantined (browser downloads are what normally trigger the Gatekeeper "unsafe" warning). Flow in `UpdateChecker.performUpdate()`:

1. On launch (and a ⌘U "Check for Updates…" menu item), `checkForUpdate()` hits `releases/latest`, regex-parses the short SHA from the release title (`Latest Build (abc1234)`), and compares it to `BuildInfo.commitSHA`. The rolling `latest` release model means any difference = a newer build.
2. `performUpdate()` downloads the zip, extracts via `ditto`, strips quarantine defensively (`xattr -dr com.apple.quarantine`), then — if the running bundle is in a writable location and not App-Translocated — spawns a detached `/bin/sh` helper that waits for the app to quit, swaps the bundle in place, clears quarantine, and relaunches. The app then calls `NSApp.terminate`.
3. **Fallback:** if the bundle is read-only or App-Translocated, it reverts to the older flow — drop a ready-to-use `OpenDiskTest (new).app` in Downloads and reveal it in Finder for a manual drag.

`BuildInfo.swift` (the `commitSHA`) is **generated at build time** by a Run Script phase (`git rev-parse HEAD`) and is gitignored — so SourceKit/static analysis will report `BuildInfo` as "not in scope" until a build generates it; this is expected, not a real error.

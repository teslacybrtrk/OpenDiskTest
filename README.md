# OpenDiskTest

A simple, native macOS app for benchmarking disk speed. Measures sequential and random read/write performance and visualizes the results with live charts.

Requires macOS 14.5 or later.

## Download

**[Download the latest build](https://github.com/teslacybrtrk/OpenDiskTest/releases/latest/download/OpenDiskTest.zip)**

### Opening the app for the first time

We don't pay for an Apple Developer ID or notarization, so macOS Gatekeeper blocks the app on first launch (common on Sonoma, Sequoia, and later).

**One-time steps (try launching first, then allow in settings):**

- Unzip `OpenDiskTest.zip`
- Drag `OpenDiskTest.app` into your `/Applications` folder (recommended)
- Double-click the app to launch it
- When the warning appears ("cannot be opened" / developer cannot be verified), click **OK** / **Done**
- Open **System Settings** ( menu → System Settings)
- Click **Privacy & Security** in the sidebar
- Scroll all the way down to the **Security** section
- Next to the OpenDiskTest message, click **Open Anyway**
- In the confirmation dialog, click **Open**

You only need to do this once. After that, double-clicking the app opens it normally.

## Features

- **Sequential write/read** — measures sustained throughput with large files
- **Random write/read** — measures IOPS-style performance with 4KB blocks (also reports effective throughput)
- Choose custom test directory or volume (persisted via macOS security-scoped bookmarks) or stick with the system temp dir
- Configurable file size (0.1–4096 MB) and iteration count (1–1000), with live validation
- Settings (size, iterations, last test location) are persisted across launches
- Live speed distribution charts per test
- Min / Avg / Max statistics
- Built-in activity log (separate window + "Log" button)
- Update checker (banner + menu item) that links to GitHub releases (manual download recommended for safety)

## Building from source

Open `OpenDiskTest.xcodeproj` in Xcode, or build from the command line:

```bash
xcodebuild -project OpenDiskTest.xcodeproj -scheme OpenDiskTest -configuration Release build
```

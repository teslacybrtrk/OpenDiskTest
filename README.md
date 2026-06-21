# OpenDiskTest Suite

A native macOS suite of disk & system utilities, presented on a dashboard of tools. Started as a disk benchmark and now also includes a storage analyzer, duplicate finder, live system monitor, network speed test, and disk cleanup.

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

## Tools

The app opens to a **dashboard** of tool cards (with live mini-stats); click one to open it, and use the back button to return home. Appearance (System/Light/Dark) and the in-app updater live on the dashboard.

- **Disk Speed Test** — sequential & random read/write throughput, IOPS, latency (avg/p99), configurable block size and queue depth, cache bypass, sustained-write test, integrity verify, presets, history, and PNG/clipboard export.
- **Space Analyzer** — recursively scans a folder (Home by default; whole-disk opt-in) and renders an interactive **squarified treemap**; click to drill in, reveal in Finder.
- **Duplicate Finder** — finds identical files (size → partial-hash → SHA256) and your largest files; hardlink-aware reclaimable totals; move to Trash.
- **System Monitor** — live per-core/aggregate CPU, memory breakdown + swap, battery health (cycles/condition/health %), and thermal state, with sparklines.
- **Network Speed** — download/upload/latency measured against Cloudflare with a live throughput graph.
- **Disk Cleanup** — reclaim space from caches, logs, Xcode DerivedData/archives, and the Trash; nothing pre-selected, everything moves to Trash (except emptying the Trash, which is clearly flagged).

The app is **not sandboxed**, so file scans cover any user-readable location; some areas (Desktop/Documents/other volumes) may require granting **Full Disk Access** in System Settings for complete coverage.

## Building from source

Open `OpenDiskTest.xcodeproj` in Xcode, or build from the command line:

```bash
xcodebuild -project OpenDiskTest.xcodeproj -scheme OpenDiskTest -configuration Release build
```

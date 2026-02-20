# OpenDiskTest

A simple, native macOS app for benchmarking disk speed. Measures sequential and random read/write performance and visualizes the results with live charts.

Requires macOS 14.5 or later.

## Download

**[Download the latest build](https://github.com/teslacybrtrk/OpenDiskTest/releases/latest/download/OpenDiskTest.zip)**

### Opening the app

We don't pay Apple $99/year for a Developer ID certificate, so macOS will show a warning the first time you open the app. Here's how to get past it:

1. Unzip `OpenDiskTest.zip`
2. Move `OpenDiskTest.app` to your Applications folder (or wherever you like)
3. **Right-click** (or Control-click) the app and select **Open**
4. If you see an **Open** button in the dialog, click it — you're done

If macOS blocks it without an Open button:

1. Open **System Settings → Privacy & Security**
2. Scroll down to the security section — you'll see a message about OpenDiskTest being blocked
3. Click **Open Anyway**, then confirm

You only need to do this once. After that, the app opens normally.

## Features

- **Sequential write/read** — measures sustained throughput with large files
- **Random write/read** — measures IOPS-style performance with 4KB blocks
- Configurable file size and iteration count
- Live speed distribution charts per test
- Min / Avg / Max statistics
- Built-in activity log

## Building from source

Open `OpenDiskTest.xcodeproj` in Xcode, or build from the command line:

```bash
xcodebuild -project OpenDiskTest.xcodeproj -scheme OpenDiskTest -configuration Release build
```

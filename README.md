# Mac Cleaner

A small macOS app (SwiftUI) to keep an eye on disk space and free it up.

- **Overview**: used / purgeable / free space, what can be safely reclaimed, and the largest folders and files.
- **Clean Up**: caches, logs, Trash, Xcode, Homebrew, npm, Docker, system caches, local Time Machine snapshots, DNS cache… Each row shows its size and the equivalent Terminal command.
- **Explorer**: browse folders sorted by size (double-click to open, ⌘↑ to go up, ⌫ to move to the Trash, drag and drop to the Finder).
- **Large Files**: every file larger than 50 MB, filterable by type.
- **Menu bar**: available space at a glance, plus a quick clean.

## Building

```sh
./build.sh            # → build/Mac Cleaner.app
./build.sh --install  # also copies it into /Applications
```

Only requires the Command Line Tools (Swift 5.10+) and macOS 14+.

For complete sizes (Trash, Mail…), give Mac Cleaner **Full Disk Access** in System Settings › Privacy & Security.

Shortcuts: ⌘1–4 sections · ⌘R refresh · ⌘↩ clean up · ⌘O choose a folder.

<div align="center">

<img src="docs/icon.png" width="96" alt="">

# Mac Cleaner

**See what fills your disk. Free it up in one click.**

A small native Mac app: how much space is left, what can be safely removed, and where the big folders and files are. Every cleanup shows the Terminal command it runs.

![macOS 14+](https://img.shields.io/badge/macOS_14+-1a1a1a?style=flat-square&logo=apple&logoColor=white)
![SwiftUI](https://img.shields.io/badge/SwiftUI-1a1a1a?style=flat-square&logo=swift&logoColor=white)
![Built from source](https://img.shields.io/badge/built_from_source-2fc941?style=flat-square)

</div>

<br>

## Install

> [!IMPORTANT]
> You need a **Mac with macOS 14 (Sonoma) or later**, Apple's **Command Line Tools**, and access to this private repository (the [GitHub CLI](https://cli.github.com) logged in with `gh auth login`).

**1. Open the Terminal app.** Press <kbd>⌘</kbd> <kbd>Space</kbd>, type `Terminal`, press <kbd>Return</kbd>.

**2. Copy this line, paste it in the Terminal, press <kbd>Return</kbd>.**

```bash
gh repo clone Tomtomytom/mac-cleaner ~/mac-cleaner && ~/mac-cleaner/build.sh --install
```

It takes about a minute. When it is done, **Mac Cleaner** is in your **Applications** folder.

> [!TIP]
> If the Terminal says the Command Line Tools are missing, run `xcode-select --install`, click **Install** in the window that opens, then paste the line again.

**3. Recommended: give it Full Disk Access.** Open **System Settings → Privacy & Security → Full Disk Access**, click **+** and pick **Mac Cleaner**. Without it, some sizes (Trash, Mail…) can't be read.

## Use

- **Overview**: used, purgeable and free space, what can be safely reclaimed, and the largest folders and files.
- **Clean Up**: tick what to remove, click **Clean Up** (<kbd>⌘</kbd><kbd>Return</kbd>). Each row shows its size and the equivalent Terminal command. The safe ones are ticked for you.
- **Explorer**: browse a folder, your home or the whole disk, sorted by size. Double-click to open, <kbd>⌘</kbd><kbd>↑</kbd> to go up, <kbd>⌫</kbd> to move to the Trash, drag to the Finder.
- **Large Files**: every file larger than 50 MB, filtered by type.
- **Menu bar**: the free space at a glance, and a **Quick Clean** of the safe items.

## What it can clean

| | |
|---|---|
| **Your files** | App caches, app logs, Trash, opened Mail attachments, iPhone / iPad updates and backups |
| **Developer** | Xcode DerivedData, Device Support and Archives, simulator caches and unavailable simulators, Homebrew, npm, pnpm, Gradle, Cargo, Go modules, Docker |
| **System** (asks for your admin password) | System caches, system logs, local Time Machine snapshots |
| **Maintenance** | Flush the DNS cache, reset Quick Look, free up RAM |

## Shortcuts

| Action | Shortcut |
|---|---|
| Overview, Clean Up, Explorer, Large Files | <kbd>⌘</kbd><kbd>1</kbd>…<kbd>⌘</kbd><kbd>4</kbd> |
| Refresh | <kbd>⌘</kbd><kbd>R</kbd> |
| Clean up the selection | <kbd>⌘</kbd><kbd>Return</kbd> |
| Choose a folder to explore | <kbd>⌘</kbd><kbd>O</kbd> |
| Go up a folder | <kbd>⌘</kbd><kbd>↑</kbd> |

## Updates

Paste this line in the Terminal:

```bash
cd ~/mac-cleaner && git pull && ./build.sh --install
```

## Something wrong?

| Problem | What to do |
|---|---|
| Some sizes show 0 or are missing | Give Mac Cleaner **Full Disk Access** (step 3), then quit and reopen it. |
| The build fails | Run `softwareupdate --list` and install the latest Command Line Tools, then paste the install line again. |
| `Permission denied` when copying to Applications | Your account isn't an administrator: copy `~/mac-cleaner/build/Mac Cleaner.app` into `~/Applications` instead. |
| Anything else | [Open an issue](https://github.com/Tomtomytom/mac-cleaner/issues). |

<br>

<details>
<summary><b>What the install does</b></summary>

<br>

It clones this repository into `~/mac-cleaner`, then [`build.sh`](build.sh) compiles the app with `swift build` (no Xcode needed), wraps it into `build/Mac Cleaner.app`, signs it ad hoc and, with `--install`, copies it to `/Applications`. The app is built on your Mac, so there is nothing to unblock in Gatekeeper.

To uninstall: delete `Mac Cleaner.app` from Applications and the `~/mac-cleaner` folder.

</details>

<details>
<summary><b>For developers</b></summary>

<br>

```bash
./build.sh              # builds build/Mac Cleaner.app
./build.sh --install    # and copies it into /Applications
swift run               # run without the app bundle
```

```
build.sh                  Build with SwiftPM (no Xcode project)
Resources/                Info.plist and app icon
scripts/make_icon.swift   Draws the app icon
Sources/MacCleaner/
  App.swift               App entry, window and menu bar item
  DiskStore.swift         Volume space (used, purgeable, free)
  Cleaner.swift           Cleanup targets, sizes and actions
  Explorer.swift          Folder scan sorted by size
  Utilities.swift         Shell commands, byte formatting
  Views/                  Overview, Clean Up, Explorer, Large Files
```

</details>

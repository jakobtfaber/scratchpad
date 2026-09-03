# Scratchpad

A native, open-source macOS desktop scratchpad that behaves like a physical pad of paper glued directly onto your wallpaper beneath your monitors and paperwork.

Unlike floating notes or sticky notes that hover over your IDE or browser, Scratchpad lives at the absolute bottom of the window stack, stays anchored across virtual desktop Spaces, and is instantly editable on a single click.

## Features

- **True Desktop Layering**: Positioned permanently at layer `-1`, strictly beneath standard application windows (Zen, Antigravity, Ghostty, Chrome, Finder). Normal windows cover it completely when moved or maximized over it.
- **Mission Control & Spaces Stability**: Configured with `.stationary`, `.canJoinAllSpaces`, and `.fullScreenAuxiliary`. It stays glued to the desktop surface during Exposé window scatter and follows across all virtual desktops without top-layer flicker.
- **Instant Single-Click Typing**: Overrides `acceptsFirstMouse` on `NSTextView`—click once anywhere on the pad and start typing immediately without requiring a preliminary activation click.
- **Native Editing Shortcuts**: Full support for `Cmd-A` (Select All), `Cmd-C` (Copy), `Cmd-V` (Paste), `Cmd-X` (Cut), `Cmd-Z` (Undo), and `Cmd-Shift-Z` (Redo).
- **Bidirectional Plaintext Sync (`~/.desktop_notes.txt`)**: Auto-saves with a 0.75s debounce timer. Live file monitoring automatically detects external edits (from Neovim, Vim, terminal scripts) and updates in place.
- **Multi-Monitor Awareness**: Automatically fits and positions on active displays (including external ultrawide setups) and persists window geometry across restarts via `UserDefaults`.
- **Dedicated Drag Header**: Grab the top `SCRATCHPAD` bar to move the pad anywhere on the wallpaper without accidentally selecting text.
- **Menu Bar Companion**: Minimalist `note.text` icon in the system menu bar to quickly show/focus, send to back, switch displays, reveal notes in Finder, or quit.

## Quick Start

### Building the App Bundle

```bash
# Build Scratchpad.app
make app

# Launch Scratchpad.app
make run

# Stop running instance
make stop

# Check status
make status
```

### Installation

Install to `~/Applications`:
```bash
make install
```

Auto-start on login via LaunchAgent:
```bash
make install-login
make uninstall-login
```

## Project Structure

```
├── main.swift         # Native Swift / AppKit implementation
├── Info.plist         # macOS Application bundle metadata (LSUIElement = true)
├── AppIcon.icns       # Native 1024x1024 Retina application icon
├── Makefile           # Build, package, install, and LaunchAgent automation
├── test_suite.swift   # Automated verification smoke test suite
└── README.md          # Project documentation
```

## Storage

All notes are stored as plain UTF-8 text at:
```
~/.desktop_notes.txt
```
You can edit this file in your terminal or pipe text into it at any time:
```bash
echo "Quick task" >> ~/.desktop_notes.txt
```
Scratchpad will update on your desktop in real-time.

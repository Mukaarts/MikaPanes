# Mika+ Panes

A native macOS menu bar utility (Swift + SwiftPM) combining lightweight,
hotkey-driven window tiling with a fast, keyboard-driven Finder overlay. No Dock
icon (`LSUIElement`). Minimum macOS 14.

## Modules

- **Window Manager** — tile the focused window via global hotkeys (halves,
  quarters, maximize, center, move to next/previous display). Multi-monitor aware;
  uses the Accessibility API.
- **Finder overlay** — a floating, non-activating panel opened by hotkey. Two
  addressing modes:
  1. *Own browser*: keyboard file-tree navigation from a root (home by default),
     with live fuzzy search in the current directory.
  2. *Finder selection*: act on the frontmost Finder window's current selection.
  Actions: Reveal, Quick Look, Move to Trash, Copy/Move.

## Default hotkeys

| Action                | Shortcut            |
|-----------------------|---------------------|
| Halves                | `⌃⌥ + ← / → / ↑ / ↓` |
| Quarters              | `⌃⌥ + U / I / J / K` |
| Maximize              | `⌃⌥↩`               |
| Center                | `⌃⌥C`               |
| Move to next display  | `⌃⌥⌘→`              |
| Move to prev display  | `⌃⌥⌘←`              |
| Open Finder overlay   | `⌃⌥Space`           |

### Overlay keys

`↑/↓` move · `↩` open/descend · `⌫` delete query char / go up · type = fuzzy
search · `Space` Quick Look · `⌘R` reveal · `⌘⌫` trash · `⌘C` copy here ·
`⌘M` move here · `⇥` toggle source (own browser ↔ Finder selection) · `Esc` close.

## Build & run

```sh
./Scripts/bundle.sh            # build -> ./build/MikaPanes.app
./Scripts/bundle.sh --install  # also install -> /Applications/MikaPanes.app
open build/MikaPanes.app
```

The app must be a signed `.app` bundle (not a bare SwiftPM binary) for the
Accessibility and Apple Events permissions to work. `bundle.sh` assembles the
bundle from `Resources/Info.plist` + `Resources/MikaPanes.entitlements` and
ad-hoc signs it.

## Permissions

- **Accessibility** (required) — to move/resize windows. The app prompts on first
  run and the menu bar item shows live status; the onboarding window deep-links to
  System Settings.
- **Full Disk Access** (optional) — lets the overlay act on protected locations.
- **Automation** (Finder) — prompted the first time you read the Finder selection.

> Ad-hoc signatures change on every rebuild, so macOS may re-prompt for
> Accessibility after a rebuild. Installing to `/Applications` is a bit more stable.

## Tests

```sh
./Scripts/test.sh
```

Unit tests cover the pure logic: `FuzzyMatcher` scoring, the AX↔Cocoa coordinate
flip in `ScreenGeometry`, and `TilePreset` frame geometry. The wrapper points the
toolchain at the Command Line Tools' bundled Swift Testing framework; with full
Xcode installed, plain `swift test` also works.

## Layout

```
Sources/MikaPanes/
  App/        — entry point, AppDelegate, status item, onboarding
  Services/   — HotKeyManager (Carbon), PermissionsService, SettingsStore
  WindowManager/ — AXWindowService, ScreenGeometry, TilePreset, WindowTiler
  Overlay/    — OverlayPanel/Controller, SwiftUI view, FileBrowserModel,
                FuzzyMatcher, Finder selection, file actions, Quick Look
```

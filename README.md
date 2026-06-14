# Mika+ Panes

A native macOS file browser app (Swift + SwiftPM) with a Dock icon and a
Finder-like window: a favorites sidebar, a file list with live fuzzy search, and
a live QuickLook preview pane. Keyboard-first, with mouse support. Minimum macOS 14.

## Window

```
┌──────────────┬─────────────────────┬──────────────────┐
│ Favorites    │ 📁 Documents        │   ┌───────────┐  │
│ ⌂ Home    ⌘1 │ 📁 Projects      ▶  │   │ QuickLook │  │
│ 🖥 Desktop ⌘2 │ 📄 notes.md  ◀──────│   │  preview  │  │
│ 📄 Documents⌘3│ 📄 todo.txt         │   └───────────┘  │
│ ⬇ Downloads ⌘4│                     │  notes.md        │
│              │  [live fuzzy search]│  Kind · Size ·…  │
└──────────────┴─────────────────────┴──────────────────┘
```

- **Sidebar** — favorites (Home, Desktop, Documents, Downloads, + configured
  root). Click or `⌘1`…`⌘9` to jump.
- **List** — type to fuzzy-filter the current directory. `↑/↓` move, `↩` open file /
  descend into folder, `⌫` delete a search character or go to the parent folder,
  `Esc` clears the search. Single-click selects, double-click opens.
- **Preview** — inline QuickLook render of the highlighted item plus its name,
  kind, size and modified date.

## File actions

| Action          | Shortcut | Menu      |
|-----------------|----------|-----------|
| Reveal in Finder| `⌘R`     | File      |
| Quick Look      | `Space` / `⌘Y` | File |
| Move to Trash   | `⌘⌫`     | File      |
| Copy            | `⌘C`     | Edit      |
| Cut             | `⌘X`     | Edit      |
| Paste (into current folder) | `⌘V` | Edit |
| Enclosing folder| `⌘↑`     | Go        |
| Home            | `⇧⌘H`    | Go        |

Copy/Cut place an item on an internal clipboard; Paste copies (or moves, for Cut)
it into the folder currently shown. `FileManager.moveItem` handles cross-volume
moves as copy-then-delete.

## Build & run

```sh
./Scripts/bundle.sh            # build -> ./build/MikaPanes.app
./Scripts/bundle.sh --install  # also install -> /Applications/MikaPanes.app
open build/MikaPanes.app
```

`bundle.sh` assembles a `.app` from `Resources/Info.plist` and ad-hoc signs it.
The app is not sandboxed (so it can browse arbitrary locations) and needs no
special permissions for normal browsing.

## Tests

```sh
./Scripts/test.sh
```

Unit tests cover the `FuzzyMatcher` scoring logic. The wrapper points the
toolchain at the Command Line Tools' bundled Swift Testing framework; with full
Xcode installed, plain `swift test` also works.

## Layout

```
Sources/MikaPanes/
  App/        — entry point, AppDelegate, BrowserWindowController (window + menu)
  Services/   — SettingsStore (browser root)
  Overlay/    — BrowserView (SwiftUI), FileBrowserModel, FuzzyMatcher,
                FileActionsService, QuickLookController
```

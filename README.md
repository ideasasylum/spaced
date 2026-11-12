# Spaced

A macOS reader that shows a markdown document one piece at a time, for getting through long documents and agent output without losing your place.

## Build

Needs only the Xcode Command Line Tools.

```sh
make test      # core tests
make app       # builds build/Spaced.app
make run       # builds and opens it
make install   # copies to /Applications and links `spaced` into /usr/local/bin
```

## Keys

| Key | Action |
| --- | --- |
| Space / → | next |
| Shift+Space / ← | previous |
| ↑ / ↓ | widen / narrow focus: sentence, block, section |
| Esc | toggle whole document |
| Return | note on the current piece (⌘Return saves, Esc cancels) |
| ⌘[ / ⌘] | previous / next section |
| ⌥↑ / ⌥↓ | more / less dimming |
| ⇧⌘R | review notes |
| ⇧⌘C | copy notes as markdown |
| ⌃⌘S | toggle sidebar |
| ⌘+ / ⌘− / ⌘0 | text size |

Open documents with ⌘O, ⌘V, drag and drop, or the CLI. Tabs are kept until you close them, including across crashes and restarts.

## CLI

```sh
spaced plan.md
cat output.md | spaced --ask "Is the migration safe?"
spaced --wait plan.md    # blocks until you press "Send Notes & Close", then prints your notes
```

Notes come back as a blockquote of the text followed by your response.

## Ideas

- Progress bar, time-left estimate, sections ticked off in the sidebar.
- Coloured accents for headings.
- Syntax highlighting for code blocks.
- Text-to-speech for the current piece, with optional auto-advance.
- Parking lot for unrelated thoughts, shown at the end.
- Bionic-style emphasis toggle.
- Xcode project wrapping the same package, for signing and distribution.

## Layout

- `Sources/SpacedCore`: parsing, navigation, sessions, export. No UI.
- `Sources/SpacedUI`: AppKit shell and SwiftUI views.
- `Sources/SpacedApp`, `Sources/SpacedCLI`: the two executables.

The Command Line Tools don't ship SwiftUI's macro plugin, so `@State` can't be used in views until the project moves to Xcode; view state lives in `SessionModel` instead.

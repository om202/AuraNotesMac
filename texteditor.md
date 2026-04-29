# Editor Plan — Custom Markdown Editor (Path B)

A native, Bear-class markdown editor built on `NSTextView` + a custom syntax highlighter, wrapped in `NSViewRepresentable` so the rest of the SwiftUI app stays pure SwiftUI.

**Goal:** the user types `**bold**` and the word *appears bold* live, with the asterisks dimmed but visible. Headings render larger. Code is monospace. Lists indent. No round-trip issues, no cursor jitter, no rich-text storage — just plain markdown on disk that *looks* rich while editing.

---

## Decision

**Path B: `NSTextView` wrapped in `NSViewRepresentable`.**

Path A (SwiftUI `TextEditor` with `AttributedString` binding) was rejected because re-attributing the binding on every keystroke disrupts cursor and selection. macOS 26's `AttributedString` binding is improved but still fighty for live syntax styling — you'd ship something that works ~90% of the time and feels janky the rest. That's not the bar.

Bear, Typora, iA Writer, Obsidian (live mode) all use the AppKit/UIKit text engine for the same reason. `NSViewRepresentable` is the SwiftUI-blessed way to embed it; this is *not* a betrayal of the "native SwiftUI" goal. The app shell (sidebar, list, navigation, AI memory layer) stays pure SwiftUI — only the editor surface drops down to AppKit.

### Honest comparison (kept for the record)

|  | Path A: `TextEditor` + `AttributedString` | Path B: `NSTextView` in `NSViewRepresentable` |
|---|---|---|
| Native? | Pure SwiftUI | Native AppKit (TextEdit/Mail/Bear engine) |
| Bear-quality live styling? | No — cursor disruption on re-attribution | Yes |
| Glue code | ~150 LOC | ~400–600 LOC |
| Bold/italic shortcuts | ⌘B wraps in `**` (easy) | Same, plus visual styling |
| Inline images | Limited / janky | Real (`NSTextAttachment`) |
| Live-styled lists / headings | Cursor jumps when re-styling | Smooth |
| Time to build | Half a day | 2–3 focused days |

---

## v1 scope (what we build first)

1. `NSTextView` wrapped in `NSViewRepresentable`, exposing `text: Binding<String>` of markdown source.
2. Custom syntax highlighter running on `textDidChange`. Regex-based for v1 (fast, ~95% correct on personal-style markdown).
3. Style rules:
   - `**bold**` / `__bold__` → real bold; markers dimmed
   - `*italic*` / `_italic_` → real italic; markers dimmed
   - `~~strike~~` → strikethrough; markers dimmed
   - `` `code` `` → monospace; markers dimmed
   - `# heading` / `## heading` / `### heading` → progressively larger font; hash dimmed
   - `- item` / `* item` / `1. item` → bullet/number styled, marker indented
   - `> quote` → italic, indented, color tint
   - `[link](url)` → blue + underline; the URL portion hidden unless cursor enters the link
4. Format menu / keyboard shortcuts:
   - ⌘B → wrap selection in `**`
   - ⌘I → wrap selection in `*`
   - ⌘` → wrap selection in `` ` ``
   - ⌘K → prompt for URL, wrap selection in `[…](url)`
5. Free from `NSTextView`: undo/redo, find (⌘F), spell check, autocorrect, smart quotes, dictation, drag-drop text, services menu, accessibility.
6. Storage: `entry.text` stays as a `String` of plain markdown. No schema migration. AI memory layer reads it directly.

---

## Deferred (v2 of the editor and later)

- Inline images via `NSTextAttachment` + paste/drag handlers + `attachments/` directory + `![](attachments/<hash>.<ext>)` insertion at cursor
- Tables — probably never; not journal-shaped
- Code block syntax highlighting (Splash library) for fenced blocks
- Optional split view for fully-rendered preview (`MarkdownUI`)
- Upgrade highlighter from regex to `swift-markdown` parser when correctness matters more than speed
- Custom checkbox lists (`- [ ]` / `- [x]`)

---

## File structure

```
SmartJournalApp/
  Editor/
    MarkdownEditor.swift          // NSViewRepresentable wrapper        ~80 LOC
    MarkdownTextView.swift        // NSTextView subclass, key handling  ~120 LOC
    MarkdownHighlighter.swift     // regex-based syntax highlighter     ~200 LOC
    MarkdownCommand.swift         // ⌘B / ⌘I / ⌘` / ⌘K helpers          ~60 LOC
```

`EntryEditor` (existing) replaces its `TextEditor(text: $entry.text)` with `MarkdownEditor(text: $entry.text)`. Nothing else in the app changes.

---

## Build order with commit gates

Each step is a working, shippable state. Commit after each. We can stop at any gate if the cost grows beyond the value.

1. **Empty wrapper.** `MarkdownEditor` `NSViewRepresentable` wraps `NSTextView`, binds to `entry.text`. No styling yet — equivalent to current `TextEditor` plus better undo/find. *Commit and verify build.*
2. **Basic highlighter.** Regex rules for headings, bold, italic only. Markers dim, styled text appears styled. *Commit and try it.*
3. **Full highlighter.** Add lists, code, blockquotes, links, strikethrough. *Commit.*
4. **Format commands.** ⌘B / ⌘I / ⌘` / ⌘K wrap the current selection. Wire into the Format menu via `.commands`. *Commit.*
5. **Replace `TextEditor`.** Swap the editor in `EntryEditor`. *Commit — editor v1 done.*

Worst case: we ship at step 2 and have a passable editor with bold/italic/headings styled live. Best case: full Bear-style v1 by step 5.

---

## Why this doesn't compromise the "native SwiftUI" goal

- `NSViewRepresentable` is SwiftUI's official mechanism for using AppKit views.
- `NSTextView` is the *most* native rich-text editor on macOS — TextEdit, Mail, Notes (older versions), Pages, and Bear all use it.
- The entire app shell stays SwiftUI: sidebar list, navigation, toolbar, dialogs, AI memory views.
- The only AppKit surface is the editing canvas itself, which is exactly the right place to use it.

---

## Open questions to resolve during build

- **Heading font sizes:** match SF Pro display sizes for `# / ## / ###`, or use SwiftUI `.font(.title)`/`.title2`/`.title3` equivalents via `NSFont.preferredFont(forTextStyle:)`?
- **Marker dimming color:** use `NSColor.tertiaryLabelColor` (auto adapts to dark mode) — likely yes.
- **Cursor-aware styling:** when cursor enters a `**bold**` range, fully reveal both pairs of asterisks; when it leaves, dim them. Bear does this. Adds polish but is its own ~50 LOC of selection observation.
- **Link rendering:** show `[text](url)` as just the styled `text` with the URL hidden until cursor enters? Bear does this. Good UX, more state to manage.
- **List continuation:** pressing return on `- item` should auto-insert `- ` on the next line. Standard markdown editor behavior. Worth doing in v1.

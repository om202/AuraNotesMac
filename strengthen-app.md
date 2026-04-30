# Strengthen Aura Notes — Editor Hardening Plan

Goal: make the **existing** editor features rock-solid. No new features. AI/dictation out of scope.

Each phase focuses on **one idea**. After each phase: build, hand off for manual testing, wait for sign-off before moving on.

---

## Phase 1 — Paste pipeline (smart, source-aware)

**Idea:** stop running every paste through plaintext + Markdown re-parse. Honor what the source app put on the pasteboard.

**What changes**
- Override `paste(_:)` in `JournalTextView` to peek at pasteboard types and pick the richest representation:
  1. RTFD/RTF → import attributed string, normalize.
  2. HTML → import via `NSAttributedString(data:options:[.documentType: .html])`, normalize.
  3. Plain text → run a conservative MD sniff (regex). If it smells like Markdown, parse via `MarkdownConverter`. Otherwise insert as plain text with current typing attributes.
  4. Image data → insert as attachment (wire up the already-enabled `importsGraphics`).
- Build a **normalization pass** for imported attributed strings:
  - Re-map all fonts to `EditorFont.currentFamily` at editor sizes; preserve only symbolic traits (bold/italic/monospace).
  - Strip foreign foreground/background colors; let `rehydrateAppearanceAwareColors` own the palette.
  - Keep links, lists, checkboxes; map heading-sized runs to editor heading levels by size threshold.
  - Drop tables (until TextKit 2 tables are fixed).
- Keep `pasteAsPlainText(_:)` (⌘⇧⌥V) as the escape hatch — true plain, **no MD parse**.
- Update `copy(_:)` to write three flavors: custom MD UTI, plain visible string, and RTF. External apps get clean plain text; round-trip back into Aura uses the MD side-channel.

**Files**
- `AuraNotes/Editor/JournalTextView.swift` (paste/copy/cut)
- `AuraNotes/Editor/MarkdownConverter.swift` (sniff helper)
- new small file or section: attributed-string normalizer

**Test plan (manual)**
- Paste from Safari → links/bold preserved, fonts normalized.
- Paste from Notes/Pages → headings/lists preserved.
- Paste plain regex like `*.txt` → stays plain, no italics.
- Paste a real Markdown README → renders.
- ⌘⇧⌥V on rich source → drops to plain.
- Copy from Aura, paste into TextEdit → clean plain text (not `**foo**`).
- Copy from Aura, paste back into Aura → identical formatting.

---

## Phase 2 — Autosave debounce + persist-on-disappear

**Idea:** stop serializing the entire RTF document on every keystroke, and never lose the last keystroke when switching entries.

**What changes**
- In `RichTextEditor.Coordinator.textDidChange`, debounce the RTF serialization + binding write by ~300ms (trailing). Keep `entry.updatedAt` updates aligned with the debounced flush.
- Add an explicit flush:
  - When the editor's view is torn down (coordinator deinit / `dismantleNSView`).
  - When the bound entry id is about to change (detect in `updateNSView`).
- Cache `previewTitle` on `Entry` keyed by `updatedAt` so sidebar rendering doesn't re-walk full text on every keystroke.

**Files**
- `AuraNotes/Editor/RichTextEditor.swift`
- `AuraNotes/Entry.swift`
- `AuraNotes/ContentView.swift` (only if a flush hook is needed at the view layer)

**Test plan**
- Type fast in a long entry → no stutter; sidebar title updates within ~half a second.
- Type, immediately click a different entry → last typed characters are present when you come back.
- Force-quit shortly after typing → relaunch, content is there (within debounce window expectations).

---

## Phase 3 — Heading / font-family / scale preserve inline traits

**Idea:** applying a heading, changing font family, or scaling size must **not** wipe bold/italic/monospace runs inside the affected text.

**What changes**
- Rewrite `setHeadingLevel` (`RichTextCommand.swift`) to enumerate `.font` runs in the paragraph, and for each run produce a new font that:
  - Uses the heading size + weight,
  - **Preserves** the run's existing symbolic traits (italic, monospace).
- Same per-run mapping in `applyFamily` (`EditorFont.swift`) and `scaleFonts` (`RichTextCommand.swift`).
- For `scaleFonts`: track a per-run "base size" (associated attribute) so repeated ⌘− then ⌘+ round-trips back to the original instead of permanently clamping at 8pt.
- Body level (level 0) uses the same per-run preservation so ⌘0 doesn't strip emphasis.

**Files**
- `AuraNotes/Editor/RichTextCommand.swift`
- `AuraNotes/Editor/EditorFont.swift`

**Test plan**
- Type "the **quick** brown fox", select line, ⌘1 → heading with **quick** still bold.
- Same line, ⌘0 → body with **quick** still bold.
- ⌘− several times until clamped, then ⌘+ same number of times → original size restored.
- Change font family on mixed bold/italic text → traits preserved, family swapped.

---

## Phase 4 — Numbered list renumbering

**Idea:** numbered lists must stay sequential through Return, delete, and toggle-on operations.

**What changes**
- Add `renumberRun(at:)` helper that, given a paragraph, walks consecutive numbered paragraphs above and below and rewrites markers `1.`, `2.`, … in order.
- Call it from:
  - `handleListContinuation` after inserting a new numbered item (`RichTextEditor.swift`).
  - Backspace / delete paths that join numbered paragraphs.
  - `applyLinePrefix` toggle-on for numbered list across selection.
- Handle the `99999. ` auto-format case: respect the typed starting number for the first item, then renumber from there.

**Files**
- `AuraNotes/Editor/RichTextCommand.swift`
- `AuraNotes/Editor/RichTextEditor.swift`

**Test plan**
- Create `1./2./3.`, delete item 2 → becomes `1./2.`.
- Insert item between 2 and 3 → becomes `1./2./3./4.`.
- Type `5. ` then Return Return → list starts at 5, second item is 6.
- Toggle numbered on 5 selected lines → 1..5.

---

## Phase 5 — Empty-state reset + heading exit on Return

**Idea:** when content goes empty or the user presses Return on a heading, return cleanly to body defaults — mirroring how list exit already works.

**What changes**
- After deletes, if the document becomes empty (or a paragraph becomes empty and is the only paragraph), reset `typingAttributes` and the active paragraph style to body defaults.
- In `handleListContinuation` (or its sibling), add heading-exit: Return at the end of a heading line creates a body paragraph (drop the heading font/color from `typingAttributes`).

**Files**
- `AuraNotes/Editor/RichTextEditor.swift`

**Test plan**
- Type a heading, Return → next line types as body.
- Type into a list, select all, delete → next character starts a clean body paragraph (no phantom hanging indent).
- Same for a fully-deleted heading.

---

## Phase 6 — Backspace-at-list-start + Tab/Shift-Tab indent

**Idea:** match user expectations from Notes/Bear for list editing.

**What changes**
- Backspace at the start of a list item content (just after the marker / hanging indent) → outdent one level if nested, otherwise convert to a body paragraph (same effect as Return-on-empty).
- Tab on a list line → indent one level (deepen `headIndent`/`firstLineHeadIndent`, optionally swap marker style for visual hierarchy).
- Shift-Tab → outdent one level, mirror of above.
- Tab outside a list still inserts a tab character (current behavior).

**Files**
- `AuraNotes/Editor/RichTextEditor.swift` (`doCommandBy`)
- `AuraNotes/Editor/RichTextCommand.swift` (indent helpers)

**Test plan**
- On a bullet item with cursor at start, Backspace → exits list.
- Tab on a bullet → indents; Shift-Tab → outdents.
- Tab in body text → still a tab.
- Numbered lists indent and renumber correctly per level (deferring nested numbering complexity if needed; minimum: indent without breaking numbering).

---

## Phase 7 — Toggle correctness across mixed selections

**Idea:** ⌘B / ⌘I / code / link toggles behave predictably across heterogeneous runs.

**What changes**
- `toggleTrait`: redefine "all have trait" as "every glyph in selection already has the trait". If true → remove from all. If false → add to all. Two-press inconsistency goes away.
- `toggleCode`: stop overwriting `.foregroundColor` on `.link` runs; use a sentinel/role-based color application that respects link runs.
- Toolbar link insertion: don't write `.foregroundColor = body` on the new `.link` run; let `linkTextAttributes` handle visual color.
- `applyLinePrefix` selection preservation: after toggle, restore selection over the affected paragraph range so the user can immediately apply another command.
- Fix `shouldChangeText(in:replacementString:)` calls to pass the actual replacement string for correct undo coalescing.

**Files**
- `AuraNotes/Editor/RichTextCommand.swift`

**Test plan**
- Select across heading + body, ⌘B once → both bold; ⌘B again → both not bold.
- Toggle code over a range containing a link → link styling intact after toggle on/off.
- Insert link via toolbar → link colored correctly on first paint, no flicker after entry switch.
- Toggle bullets on 5 lines, then ⌘B → all 5 lines bolded (selection preserved).
- Undo after a toggle → single step, not split across multiple undos.

---

## Phase 8 — Settings & assists timing + minor polish

**Idea:** small papercuts that erode trust.

**What changes**
- Apply user assists (smart quotes, dashes, data detection) during `makeNSView` initial setup, not async after `bridge` is set — no first-frame flash with wrong settings.
- Suppress inline auto-format triggers (`- `, `# `, etc.) when the cursor is inside an inline code run.
- Click-to-toggle checkbox: widen the hit region (test against the line rect's leading prefix area, not exact `paraStart` glyph index). Allow toggling on todo lines that have leading whitespace.
- Hide or disable the "insert table" toolbar item until TextKit 2 tables are usable, to stop users hitting a broken feature.
- `updateNSView`: also reload when attributes diverge, not only `string`.

**Files**
- `AuraNotes/Editor/RichTextEditor.swift`
- `AuraNotes/Editor/JournalTextView.swift`
- `AuraNotes/Editor/EditorToolbar.swift`
- `AuraNotes/Editor/EditorBridge.swift`

**Test plan**
- Toggle off smart quotes in settings, relaunch → first keystroke uses straight quotes.
- Type `- ` inside backticks → no list conversion.
- Click anywhere along the ☐ glyph row → toggles reliably.
- Table toolbar item is gone (or visibly disabled).

---

## Working agreement

- One phase per branch (or one commit series), build clean before handoff.
- After each phase: I'll build, you test the phase's checklist, then sign off before we start the next.
- Anything we discover mid-phase that doesn't fit the phase's idea → captured here as a follow-up, not snuck in.

//
//  RichTextEditor.swift
//  AuraNotes
//

import SwiftUI
import AppKit
import StoreKit

struct RichTextEditor: NSViewRepresentable {
    @Binding var data: Data?
    @Binding var plainText: String
    var bridge: EditorBridge?
    @Environment(\.requestReview) private var requestReview

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true

        let contentSize = scrollView.contentSize
        let family = EditorFont.currentFamily
        let defaultFont = family.font(size: Theme.FontSize.body)

        // TextKit 2: required for the inline Writing Tools animation
        // (without it the system falls back to "limited" panel-style UX where
        // text vanishes and reappears instead of animating in place).
        let textView = JournalTextView(usingTextLayoutManager: true)
        textView.frame = .zero
        if let tc = textView.textContainer {
            tc.widthTracksTextView = true
            tc.lineFragmentPadding = 0
            tc.containerSize = NSSize(
                width: contentSize.width,
                height: CGFloat.greatestFiniteMagnitude
            )
        }
        textView.delegate = context.coordinator
        textView.allowsUndo = true
        textView.isRichText = true
        textView.importsGraphics = true
        textView.allowsImageEditing = true
        textView.usesFontPanel = true
        textView.usesRuler = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = true
        textView.isAutomaticDashSubstitutionEnabled = true
        textView.isAutomaticTextReplacementEnabled = true
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = true
        textView.smartInsertDeleteEnabled = true
        textView.isAutomaticLinkDetectionEnabled = true
        textView.font = defaultFont
        textView.typingAttributes = [
            .font: defaultFont,
            .foregroundColor: Theme.EditorColor.body
        ]
        textView.textColor = Theme.EditorColor.body
        textView.backgroundColor = bridge?.background.color ?? Theme.EditorColor.background
        textView.drawsBackground = true
        textView.insertionPointColor = Theme.EditorColor.body
        textView.linkTextAttributes = [
            .foregroundColor: Theme.EditorColor.link,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand
        ]
        textView.textContainerInset = NSSize(
            width: Theme.Space.xxl,
            height: Theme.Space.xxl
        )

        // Apple Intelligence: enable system Writing Tools on this text view.
        // The system will inject Writing Tools entries into the context menu
        // and (on macOS 15+) drive inline rewrites when invoked.
        //
        // We deliberately constrain the result options to .plainText so that
        // replacements inherit our body typing attributes (font family, body
        // size, body color) instead of the system's default rich-text styling.
        // .richText / .list / .table results otherwise come back with smaller,
        // greyer text than the surrounding body.
        if #available(macOS 15.0, *) {
            textView.writingToolsBehavior = .complete
            textView.allowedWritingToolsResultOptions = [.plainText]
        }
        // Inline predictions and the older text-completion pipeline are
        // toggled by EditorBridge.applyAssists alongside the rest of the
        // Writing Assists settings — no need to set them here.
        textView.installAIButton()
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(
            top: 0, left: 0, bottom: 96, right: 0
        )
        scrollView.scrollerInsets = NSEdgeInsets(
            top: 0, left: 0, bottom: 96, right: 0
        )
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = .width

        if let attr = Self.attributedString(from: data, fallbackPlain: plainText) {
            textView.textStorage?.setAttributedString(attr)
        }

        scrollView.documentView = textView
        bridge?.textView = textView
        context.coordinator.textView = textView

        DispatchQueue.main.async { [weak textView] in
            guard let textView, let window = textView.window else { return }
            window.makeFirstResponder(textView)
        }

        return scrollView
    }

    /// SwiftUI calls this when the representable is being removed (e.g. when
    /// the user switches entries via the `.id(persistentModelID)` reset).
    /// Flush any pending debounced persist so the last keystrokes aren't
    /// lost mid-flight.
    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.flushPendingPersist()
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tv = scrollView.documentView as? NSTextView,
              let storage = tv.textStorage else { return }

        // Only reload if the bound data changed externally (e.g. switching entries).
        // We compare on plain string + length to avoid round-tripping RTF on every keystroke.
        let incoming = Self.attributedString(from: data, fallbackPlain: plainText)
        if let incoming, incoming.string != storage.string {
            let selection = tv.selectedRanges
            storage.setAttributedString(incoming)
            let length = storage.length
            tv.selectedRanges = selection.compactMap { value in
                let r = value.rangeValue
                let loc = min(r.location, length)
                let len = min(r.length, length - loc)
                return NSValue(range: NSRange(location: loc, length: len))
            }
        }
    }

    static func attributedString(from data: Data?, fallbackPlain: String) -> NSAttributedString? {
        let family = EditorFont.currentFamily

        if let data, !data.isEmpty,
           let attr = NSAttributedString(rtf: data, documentAttributes: nil) {
            let normalized = NSMutableAttributedString(attributedString: attr)
            EditorFont.applyFamily(family, to: normalized)
            rehydrateAppearanceAwareColors(in: normalized)
            return normalized
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: family.font(size: Theme.FontSize.body),
            .foregroundColor: Theme.EditorColor.body
        ]
        return NSAttributedString(string: fallbackPlain, attributes: attrs)
    }

    /// RTF flattens dynamic NSColors to a fixed RGB at save time, so reloading
    /// in a different appearance keeps the old (now wrong) color. Replace every
    /// non-link `.foregroundColor` with the dynamic body color so the text
    /// follows light/dark again. Strip baked styling from link runs so
    /// `textView.linkTextAttributes` drives their color and underline.
    private static func rehydrateAppearanceAwareColors(in s: NSMutableAttributedString) {
        let full = NSRange(location: 0, length: s.length)
        guard full.length > 0 else { return }
        s.enumerateAttributes(in: full, options: []) { attrs, range, _ in
            if attrs[.link] != nil {
                s.removeAttribute(.foregroundColor, range: range)
                s.removeAttribute(.underlineStyle, range: range)
            } else if attrs[.foregroundColor] != nil {
                s.addAttribute(.foregroundColor,
                               value: Theme.EditorColor.body,
                               range: range)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        weak var textView: NSTextView?
        private var writingToolsActive = false
        private var pendingPersist: DispatchWorkItem?
        private var renumberInProgress = false
        private static let persistDebounce: TimeInterval = 0.3

        init(_ parent: RichTextEditor) { self.parent = parent }

        deinit {
            // Last-ditch flush for any teardown path that doesn't go through
            // dismantleNSView. Cancels the queued work item; the synchronous
            // persist below catches the in-memory state.
            pendingPersist?.cancel()
            if let tv = textView { persistImmediate(tv) }
        }

        // Apple Intelligence Writing Tools — pause RTF re-serialization while
        // a session is active so streaming rewrites don't thrash the binding.
        // The final text gets persisted on session end.
        @available(macOS 15.0, *)
        func textViewWritingToolsWillBegin(_ textView: NSTextView) {
            writingToolsActive = true
        }

        @available(macOS 15.0, *)
        func textViewWritingToolsDidEnd(_ textView: NSTextView) {
            writingToolsActive = false
            flushPendingPersist()
            ReviewPromptCoordinator.shared.recordWritingToolsAccepted(
                using: parent.requestReview
            )
        }

        func textView(_ textView: NSTextView,
                      doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                if handleListContinuation(in: textView) { return true }
                if handleHeadingExit(in: textView) { return true }
            case #selector(NSResponder.deleteBackward(_:)):
                if handleListBackspaceExit(in: textView) { return true }
            case #selector(NSResponder.insertTab(_:)):
                if handleListIndent(in: textView, outdent: false) { return true }
            case #selector(NSResponder.insertBacktab(_:)):
                if handleListIndent(in: textView, outdent: true) { return true }
            default:
                break
            }
            return false
        }

        /// Backspace at the very start of a list item's content (just past
        /// the marker prefix) exits the list — mirroring Return-on-empty.
        /// Matches Apple Notes / Bear conventions.
        private func handleListBackspaceExit(in tv: NSTextView) -> Bool {
            guard tv.selectedRange.length == 0,
                  let storage = tv.textStorage else { return false }
            let cursor = tv.selectedRange.location
            let nsString = storage.string as NSString
            let para = nsString.paragraphRange(
                for: NSRange(location: cursor, length: 0)
            )
            let raw = nsString.substring(with: para)
            let line = raw.hasSuffix("\n") ? String(raw.dropLast()) : raw
            guard let detected = RichTextCommand.detectList(in: line) else {
                return false
            }
            guard cursor == para.location + detected.prefixLength else {
                return false
            }

            let toDelete = NSRange(location: para.location,
                                   length: detected.prefixLength)
            guard tv.shouldChangeText(in: toDelete, replacementString: "") else {
                return true
            }
            storage.beginEditing()
            storage.replaceCharacters(in: toDelete, with: "")
            let newPara = (storage.string as NSString).paragraphRange(
                for: NSRange(location: para.location, length: 0)
            )
            if newPara.length > 0 {
                storage.addAttribute(
                    .paragraphStyle,
                    value: NSParagraphStyle.default,
                    range: newPara
                )
            }
            storage.endEditing()
            tv.didChangeText()

            var typing = tv.typingAttributes
            typing[.paragraphStyle] = NSParagraphStyle.default
            tv.typingAttributes = typing

            tv.setSelectedRange(NSRange(location: para.location, length: 0))
            return true
        }

        /// Tab / Shift-Tab on a list line shifts the paragraph one indent
        /// level in or out. Outside lists, returns false so the system's
        /// default Tab (inserts a tab character) still works.
        private func handleListIndent(in tv: NSTextView, outdent: Bool) -> Bool {
            guard tv.selectedRange.length == 0,
                  let storage = tv.textStorage else { return false }
            let cursor = tv.selectedRange.location
            let nsString = storage.string as NSString
            let para = nsString.paragraphRange(
                for: NSRange(location: cursor, length: 0)
            )
            let raw = nsString.substring(with: para)
            let line = raw.hasSuffix("\n") ? String(raw.dropLast()) : raw
            guard let detected = RichTextCommand.detectList(in: line) else {
                return false
            }

            let attrs = storage.attributes(at: para.location, effectiveRange: nil)
            let baseFont = (attrs[.font] as? NSFont)
                ?? NSFont.systemFont(ofSize: Theme.FontSize.body)
            let stop = baseFont.pointSize * 1.6

            let oldStyle = (attrs[.paragraphStyle] as? NSParagraphStyle)
                ?? NSParagraphStyle.default
            let currentLevel = Int(round(oldStyle.firstLineHeadIndent / stop))
            let newLevel = outdent
                ? max(0, currentLevel - 1)
                : min(8, currentLevel + 1)
            // No movement (e.g., Shift-Tab at level 0): swallow the key
            // anyway so the system doesn't insert a literal tab.
            if newLevel == currentLevel { return true }

            let style = NSMutableParagraphStyle()
            style.firstLineHeadIndent = CGFloat(newLevel) * stop
            style.headIndent = CGFloat(newLevel + 1) * stop
            style.tabStops = [
                NSTextTab(textAlignment: .left,
                          location: CGFloat(newLevel + 1) * stop,
                          options: [:])
            ]

            guard tv.shouldChangeText(in: para, replacementString: nil) else {
                return true
            }
            storage.beginEditing()
            storage.addAttribute(.paragraphStyle, value: style, range: para)

            // Bullet lists: swap the glyph to match the new level so the
            // hierarchy reads at a glance even when indent is squashed.
            if case .bullet = detected, para.length > 0 {
                let glyphRange = NSRange(location: para.location, length: 1)
                let glyphAttrs = storage.attributes(
                    at: glyphRange.location, effectiveRange: nil
                )
                let newGlyph = RichTextCommand.bulletGlyph(forLevel: newLevel)
                storage.replaceCharacters(
                    in: glyphRange,
                    with: NSAttributedString(string: newGlyph, attributes: glyphAttrs)
                )
            }
            storage.endEditing()
            tv.didChangeText()

            var typing = tv.typingAttributes
            typing[.paragraphStyle] = style
            tv.typingAttributes = typing
            return true
        }

        /// Return at the end of a heading paragraph drops the next line back
        /// to body typography. Without this, the new paragraph inherits the
        /// heading's typing attributes and the user keeps typing in title size.
        private func handleHeadingExit(in tv: NSTextView) -> Bool {
            guard tv.selectedRange.length == 0,
                  let storage = tv.textStorage else { return false }
            let typing = tv.typingAttributes
            guard let font = typing[.font] as? NSFont else { return false }

            // Anything noticeably larger than body is treated as a heading.
            // Body is 18, subheading 21 — a ≥ 2pt margin distinguishes
            // headings from scaled-up body without false positives.
            guard font.pointSize >= CGFloat(Theme.FontSize.body) + 2 else {
                return false
            }

            // Cursor must sit at the end of the line, not mid-heading.
            let cursor = tv.selectedRange.location
            let nsString = storage.string as NSString
            let para = nsString.paragraphRange(for: NSRange(location: cursor, length: 0))
            let lineEnd = para.location + para.length
            let contentEnd = (lineEnd > para.location
                              && nsString.character(at: lineEnd - 1) == 0x0A)
                ? lineEnd - 1 : lineEnd
            guard cursor == contentEnd else { return false }

            // Empty heading line: strip the heading style in place and let
            // the user keep typing on the same line as body.
            let bodyFont = EditorFont.currentFamily.font(size: Theme.FontSize.body)
            let bodyAttrs: [NSAttributedString.Key: Any] = [
                .font: bodyFont,
                .foregroundColor: Theme.EditorColor.body
            ]

            if cursor == para.location {
                if para.length > 0 {
                    storage.addAttributes(bodyAttrs, range: para)
                    tv.didChangeText()
                }
                tv.typingAttributes = bodyAttrs
                return true
            }

            // Non-empty heading line: insert a newline and start the next
            // paragraph in body typography.
            let newlineAttrs = bodyAttrs
            let insRange = NSRange(location: cursor, length: 0)
            guard tv.shouldChangeText(in: insRange, replacementString: "\n") else {
                return true
            }
            storage.replaceCharacters(
                in: insRange,
                with: NSAttributedString(string: "\n", attributes: newlineAttrs)
            )
            tv.didChangeText()
            tv.setSelectedRange(NSRange(location: cursor + 1, length: 0))
            tv.typingAttributes = bodyAttrs
            return true
        }

        private func handleListContinuation(in tv: NSTextView) -> Bool {
            guard tv.selectedRange.length == 0,
                  let storage = tv.textStorage else { return false }

            let nsString = storage.string as NSString
            let selLoc = tv.selectedRange.location
            let paraRange = nsString.paragraphRange(
                for: NSRange(location: selLoc, length: 0)
            )
            let paraText = nsString.substring(with: paraRange)
            let line = paraText.hasSuffix("\n")
                ? String(paraText.dropLast())
                : paraText

            guard let detected = RichTextCommand.detectList(in: line) else {
                return false
            }

            let prefixLen = detected.prefixLength
            let lineNS = line as NSString
            guard lineNS.length >= prefixLen else { return false }
            let after = lineNS.substring(from: prefixLen)

            let baseAttrs = tv.typingAttributes

            // Empty list item → exit the list by stripping its prefix and
            // any list-specific paragraph style.
            if after.trimmingCharacters(in: .whitespaces).isEmpty {
                let toDelete = NSRange(location: paraRange.location,
                                       length: prefixLen)
                guard tv.shouldChangeText(in: toDelete,
                                          replacementString: "") else {
                    return true
                }
                storage.beginEditing()
                storage.replaceCharacters(in: toDelete, with: "")
                let newPara = (storage.string as NSString)
                    .paragraphRange(for: NSRange(location: paraRange.location,
                                                 length: 0))
                if newPara.length > 0 {
                    storage.addAttribute(
                        .paragraphStyle,
                        value: NSParagraphStyle.default,
                        range: newPara
                    )
                }
                storage.endEditing()
                tv.didChangeText()

                var typing = baseAttrs
                typing[.paragraphStyle] = NSParagraphStyle.default
                tv.typingAttributes = typing

                tv.setSelectedRange(NSRange(location: paraRange.location,
                                            length: 0))
                return true
            }

            // Continue the list with the next prefix.
            let continuation = NSMutableAttributedString(
                string: "\n",
                attributes: baseAttrs
            )
            switch detected {
            case .bullet:
                // New line inherits the previous paragraph's indent level
                // via paragraph style; pick the matching glyph so nesting
                // depth stays visually consistent.
                let prevStyle = (baseAttrs[.paragraphStyle] as? NSParagraphStyle)
                    ?? NSParagraphStyle.default
                let baseFont = (baseAttrs[.font] as? NSFont)
                    ?? NSFont.systemFont(ofSize: Theme.FontSize.body)
                let stop = baseFont.pointSize * 1.6
                let level = stop > 0
                    ? Int(round(prevStyle.firstLineHeadIndent / stop))
                    : 0
                continuation.append(
                    RichTextCommand.bulletPrefix(forLevel: level, baseAttrs: baseAttrs)
                )
            case .numbered(let n, _):
                continuation.append(
                    RichTextCommand.numberedPrefix(
                        value: n + 1,
                        baseAttrs: baseAttrs
                    )
                )
            case .todo:
                continuation.append(
                    RichTextCommand.todoPrefix(baseAttrs: baseAttrs)
                )
            }

            let insRange = NSRange(location: selLoc, length: 0)
            guard tv.shouldChangeText(
                in: insRange,
                replacementString: continuation.string
            ) else { return true }
            storage.replaceCharacters(in: insRange, with: continuation)
            tv.didChangeText()

            let newLoc = selLoc + continuation.length
            tv.setSelectedRange(NSRange(location: newLoc, length: 0))

            // Keep typing-attribute font at base (the bullet glyph uses a
            // larger size that we don't want bleeding into typed text).
            tv.typingAttributes = baseAttrs

            // Numbered lists: ensure the new item's number is in sequence
            // with what came before. The textDidChange hook will also fire
            // a renumber pass, but doing it inline keeps the cursor's
            // visual context correct on the very first paint.
            if case .numbered = detected {
                RichTextCommand.renumberAroundLocation(in: tv, location: newLoc)
            }
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            if writingToolsActive { return }
            if !renumberInProgress {
                renumberInProgress = true
                tv.textStorage?.beginEditing()
                RichTextCommand.renumberAroundCursor(in: tv)
                tv.textStorage?.endEditing()
                renumberInProgress = false
            }
            resetTypingAttributesIfEmpty(tv)
            schedulePersist(for: tv)
        }

        /// When the document is fully empty, drop any lingering heading or
        /// list typing attributes so the next character starts as body. Also
        /// clears any stale paragraph style (hanging indent from a deleted
        /// list, etc.).
        private func resetTypingAttributesIfEmpty(_ tv: NSTextView) {
            guard let storage = tv.textStorage, storage.length == 0 else { return }
            let bodyFont = EditorFont.currentFamily.font(size: Theme.FontSize.body)
            tv.typingAttributes = [
                .font: bodyFont,
                .foregroundColor: Theme.EditorColor.body
            ]
        }

        /// Trailing-edge debounce: serializing a long document to RTF on every
        /// keystroke is wasteful and stutters on big entries. We coalesce writes
        /// into one flush ~300ms after the user stops typing.
        private func schedulePersist(for tv: NSTextView) {
            pendingPersist?.cancel()
            let work = DispatchWorkItem { [weak self, weak tv] in
                guard let self, let tv else { return }
                self.pendingPersist = nil
                self.persistImmediate(tv)
            }
            pendingPersist = work
            DispatchQueue.main.asyncAfter(
                deadline: .now() + Self.persistDebounce,
                execute: work
            )
        }

        /// Cancel any queued debounce and persist now. Called on view
        /// dismantle (entry switch) and at the end of Writing Tools.
        func flushPendingPersist() {
            pendingPersist?.cancel()
            pendingPersist = nil
            if let tv = textView { persistImmediate(tv) }
        }

        private func persistImmediate(_ tv: NSTextView) {
            let attr = tv.attributedString()
            let fullRange = NSRange(location: 0, length: attr.length)
            let rtf = (try? attr.data(
                from: fullRange,
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )) ?? Data()
            parent.data = rtf
            parent.plainText = attr.string
        }
    }
}

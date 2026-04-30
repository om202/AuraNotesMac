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

        DispatchQueue.main.async { [weak textView] in
            guard let textView, let window = textView.window else { return }
            window.makeFirstResponder(textView)
        }

        return scrollView
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
        private var writingToolsActive = false
        init(_ parent: RichTextEditor) { self.parent = parent }

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
            persist(textView)
            ReviewPromptCoordinator.shared.recordWritingToolsAccepted(
                using: parent.requestReview
            )
        }

        func textView(_ textView: NSTextView,
                      doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) {
                return handleListContinuation(in: textView)
            }
            return false
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
                continuation.append(
                    RichTextCommand.bulletPrefix(baseAttrs: baseAttrs)
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
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            if writingToolsActive { return }
            persist(tv)
        }

        private func persist(_ tv: NSTextView) {
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

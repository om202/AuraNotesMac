//
//  RichTextEditor.swift
//  SmartJournalApp
//

import SwiftUI
import AppKit

struct RichTextEditor: NSViewRepresentable {
    @Binding var data: Data?
    @Binding var plainText: String
    var bridge: EditorBridge?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true

        let contentSize = scrollView.contentSize
        let textContainer = NSTextContainer(
            size: NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        )
        textContainer.widthTracksTextView = true
        textContainer.lineFragmentPadding = 0

        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)

        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)

        let family = EditorFont.currentFamily
        let defaultFont = family.font(size: Theme.FontSize.body)

        let textView = JournalTextView(frame: .zero, textContainer: textContainer)
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
            .foregroundColor: NSColor.labelColor
        ]
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(
            width: Theme.Space.xxl,
            height: Theme.Space.xxl
        )
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
            textStorage.setAttributedString(attr)
        }

        scrollView.documentView = textView
        bridge?.textView = textView
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
            return normalized
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: family.font(size: Theme.FontSize.body),
            .foregroundColor: NSColor.labelColor
        ]
        return NSAttributedString(string: fallbackPlain, attributes: attrs)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        init(_ parent: RichTextEditor) { self.parent = parent }

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

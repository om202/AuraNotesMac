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
        textView.textContainerInset = .zero
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

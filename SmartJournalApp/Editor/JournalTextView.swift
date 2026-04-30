//
//  JournalTextView.swift
//  SmartJournalApp
//

import AppKit

enum EditorSpread: String, CaseIterable, Identifiable {
    case narrow, medium, wide, full

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .narrow: return "Narrow"
        case .medium: return "Medium"
        case .wide:   return "Wide"
        case .full:   return "Full Width"
        }
    }

    /// Maximum text column width in points. `nil` means use the full
    /// available scroll-view width.
    var maxWidth: CGFloat? {
        switch self {
        case .narrow: return 640
        case .medium: return 820
        case .wide:   return 1100
        case .full:   return nil
        }
    }
}

final class JournalTextView: NSTextView {
    static let unchecked: Character = "☐"
    static let checked:   Character = "☑"

    /// Reading-column width preference. Updating this re-centers the text
    /// inside the available scroll-view area on the next layout pass.
    var spread: EditorSpread = .full {
        didSet { updateHorizontalInsetsForSpread() }
    }

    /// Symmetric vertical inset preserved across spread changes.
    private let baseHorizontalInset: CGFloat = Theme.Space.xxl

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateHorizontalInsetsForSpread()
    }

    private func updateHorizontalInsetsForSpread() {
        let target: CGFloat = {
            guard let max = spread.maxWidth else { return baseHorizontalInset }
            let extra = (bounds.width - max) / 2
            return Swift.max(baseHorizontalInset, extra)
        }()
        if textContainerInset.width != target {
            textContainerInset = NSSize(
                width: target,
                height: textContainerInset.height
            )
        }
    }

    private static let toggleableMarkers: Set<UInt16> = [
        Character("☐").utf16.first!,
        Character("☑").utf16.first!
    ]
    private static let uncheckedMarkers: Set<UInt16> = [
        Character("☐").utf16.first!
    ]

    override func paste(_ sender: Any?) {
        pasteAsPlainText(sender)
    }

    override func copy(_ sender: Any?) {
        guard let storage = textStorage, selectedRange().length > 0 else {
            super.copy(sender); return
        }
        let selected = storage.attributedSubstring(from: selectedRange())
        let md = MarkdownSerializer.serialize(selected)
        let rtf = try? selected.data(
            from: NSRange(location: 0, length: selected.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(md, forType: .string)
        if let rtf { pb.setData(rtf, forType: .rtf) }
    }

    override func cut(_ sender: Any?) {
        copy(sender)
        let range = selectedRange()
        guard range.length > 0,
              shouldChangeText(in: range, replacementString: "") else { return }
        textStorage?.deleteCharacters(in: range)
        didChangeText()
    }

    override func pasteAsPlainText(_ sender: Any?) {
        guard let plain = NSPasteboard.general.string(forType: .string) else { return }
        let range = selectedRange()
        let converted = MarkdownConverter.convert(plain, baseAttrs: typingAttributes)
        guard shouldChangeText(in: range, replacementString: converted.string) else { return }
        textStorage?.replaceCharacters(in: range, with: converted)
        didChangeText()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let containerPoint = NSPoint(x: point.x - textContainerOrigin.x,
                                     y: point.y - textContainerOrigin.y)
        guard let lm = layoutManager, let tc = textContainer else {
            super.mouseDown(with: event); return
        }

        let glyphIndex = lm.glyphIndex(for: containerPoint, in: tc)
        let glyphRect  = lm.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: tc)

        guard glyphRect.contains(containerPoint) else {
            super.mouseDown(with: event); return
        }

        let charIndex = lm.characterIndexForGlyph(at: glyphIndex)
        let nsString  = string as NSString
        guard charIndex < nsString.length else {
            super.mouseDown(with: event); return
        }

        let scalar = nsString.character(at: charIndex)
        if Self.toggleableMarkers.contains(scalar) {
            // Only toggle when the character begins a paragraph (so it's a todo marker,
            // not an inline use of the glyph).
            let paraStart = nsString.paragraphRange(for: NSRange(location: charIndex, length: 0)).location
            if charIndex == paraStart {
                toggleTodoCharacter(at: charIndex)
                return
            }
        }

        super.mouseDown(with: event)
    }

    private func toggleTodoCharacter(at index: Int) {
        guard let storage = textStorage else { return }
        let range = NSRange(location: index, length: 1)
        let current = (storage.string as NSString).character(at: index)
        let replacement = Self.uncheckedMarkers.contains(current)
            ? String(Self.checked)
            : String(Self.unchecked)

        guard shouldChangeText(in: range, replacementString: replacement) else { return }
        let attrs = storage.attributes(at: index, effectiveRange: nil)
        storage.replaceCharacters(in: range, with: NSAttributedString(string: replacement, attributes: attrs))
        didChangeText()
    }
}

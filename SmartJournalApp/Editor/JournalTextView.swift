//
//  JournalTextView.swift
//  SmartJournalApp
//

import AppKit

final class JournalTextView: NSTextView {
    static let unchecked: Character = "☐"
    static let checked:   Character = "☑"

    private static let toggleableMarkers: Set<UInt16> = [
        Character("☐").utf16.first!,
        Character("☑").utf16.first!
    ]
    private static let uncheckedMarkers: Set<UInt16> = [
        Character("☐").utf16.first!
    ]

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

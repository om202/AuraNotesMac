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

    override func insertText(_ string: Any, replacementRange: NSRange) {
        if let s = string as? String, s == " ", applyAutoFormatOnSpace() {
            return
        }
        super.insertText(string, replacementRange: replacementRange)
        if let s = string as? String, let last = s.last, s.count == 1 {
            applyInlineAutoFormat(after: last)
        }
    }

    // MARK: Inline auto-format

    private func applyInlineAutoFormat(after typed: Character) {
        guard "*_~`)".contains(typed),
              let storage = textStorage else { return }
        let cursor = selectedRange().location
        guard cursor > 0 else { return }
        let nsString = storage.string as NSString
        let paraRange = nsString.paragraphRange(for: NSRange(location: cursor - 1, length: 0))
        let lineLen = cursor - paraRange.location
        guard lineLen >= 3 else { return }
        let chars = Array(nsString.substring(with: NSRange(location: paraRange.location, length: lineLen)))
        let lineStart = paraRange.location

        switch typed {
        case "*", "_":
            // Bold: ** … **
            if chars.count >= 5, chars[chars.count - 2] == typed,
               let open = findRun(chars, marker: typed, count: 2, before: chars.count - 2) {
                let inner = String(chars[(open + 2)..<(chars.count - 2)])
                if isValidInner(inner) {
                    transformInline(start: lineStart + open,
                                    length: chars.count - open,
                                    inner: inner,
                                    style: .bold)
                    return
                }
            }
            // Italic: * … *  (but not part of **)
            if chars.count >= 3, chars.count - 2 >= 0, chars[chars.count - 2] != typed,
               let open = findRun(chars, marker: typed, count: 1, before: chars.count - 1) {
                let inner = String(chars[(open + 1)..<(chars.count - 1)])
                if isValidInner(inner), !inner.contains(typed) {
                    transformInline(start: lineStart + open,
                                    length: chars.count - open,
                                    inner: inner,
                                    style: .italic)
                    return
                }
            }
        case "~":
            if chars.count >= 5, chars[chars.count - 2] == "~",
               let open = findRun(chars, marker: "~", count: 2, before: chars.count - 2) {
                let inner = String(chars[(open + 2)..<(chars.count - 2)])
                if isValidInner(inner) {
                    transformInline(start: lineStart + open,
                                    length: chars.count - open,
                                    inner: inner,
                                    style: .strike)
                }
            }
        case "`":
            if let open = findRun(chars, marker: "`", count: 1, before: chars.count - 1) {
                let inner = String(chars[(open + 1)..<(chars.count - 1)])
                if !inner.isEmpty, !inner.contains("`") {
                    transformInline(start: lineStart + open,
                                    length: chars.count - open,
                                    inner: inner,
                                    style: .code)
                }
            }
        case ")":
            tryInlineLink(in: chars, lineStart: lineStart)
        default: break
        }
    }

    private enum InlineStyle { case bold, italic, strike, code }

    private func transformInline(start: Int, length: Int, inner: String, style: InlineStyle) {
        guard let storage = textStorage else { return }
        let range = NSRange(location: start, length: length)
        guard shouldChangeText(in: range, replacementString: inner) else { return }

        var attrs = typingAttributes
        var resetTyping = typingAttributes

        switch style {
        case .bold, .italic:
            let f = (attrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            var traits = f.fontDescriptor.symbolicTraits
            traits.insert(style == .bold ? .bold : .italic)
            let new = NSFont(descriptor: f.fontDescriptor.withSymbolicTraits(traits), size: f.pointSize) ?? f
            attrs[.font] = new
            resetTyping[.font] = f
        case .strike:
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            resetTyping[.strikethroughStyle] = 0
        case .code:
            let f = (attrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            attrs[.font] = NSFont.monospacedSystemFont(ofSize: f.pointSize, weight: .regular)
            attrs[.foregroundColor] = Theme.EditorColor.code
            resetTyping[.font] = f
            resetTyping[.foregroundColor] = Theme.EditorColor.body
        }

        storage.replaceCharacters(in: range, with: NSAttributedString(string: inner, attributes: attrs))
        didChangeText()
        setSelectedRange(NSRange(location: start + (inner as NSString).length, length: 0))
        typingAttributes = resetTyping
    }

    private func tryInlineLink(in chars: [Character], lineStart: Int) {
        // Pattern ends with ")"; need "[label](url)"
        guard chars.last == ")", chars.count >= 5 else { return }
        var openParen: Int? = nil
        var i = chars.count - 2
        while i > 0 {
            if chars[i] == "(", chars[i - 1] == "]" { openParen = i; break }
            i -= 1
        }
        guard let openParen, openParen >= 2 else { return }
        let closeBracket = openParen - 1
        var openBracket: Int? = nil
        var j = closeBracket - 1
        while j >= 0 {
            if chars[j] == "[" { openBracket = j; break }
            j -= 1
        }
        guard let openBracket else { return }
        let label = String(chars[(openBracket + 1)..<closeBracket])
        let urlStr = String(chars[(openParen + 1)..<(chars.count - 1)])
        guard !label.isEmpty, !urlStr.isEmpty, let url = URL(string: urlStr) else { return }

        guard let storage = textStorage else { return }
        let range = NSRange(location: lineStart + openBracket,
                            length: chars.count - openBracket)
        guard shouldChangeText(in: range, replacementString: label) else { return }
        var attrs = typingAttributes
        attrs[.link] = url
        attrs[.foregroundColor] = Theme.EditorColor.body
        storage.replaceCharacters(in: range,
                                  with: NSAttributedString(string: label, attributes: attrs))
        didChangeText()
        setSelectedRange(NSRange(location: range.location + (label as NSString).length, length: 0))
        var reset = typingAttributes
        reset.removeValue(forKey: .link)
        reset[.foregroundColor] = Theme.EditorColor.body
        reset[.underlineStyle] = 0
        typingAttributes = reset
    }

    /// Returns the index of the leftmost run of `count` identical `marker`
    /// characters that ends before `before`, or nil.
    private func findRun(_ chars: [Character], marker: Character, count: Int, before end: Int) -> Int? {
        guard count >= 1 else { return nil }
        var i = end - count
        while i >= 0 {
            var ok = true
            for k in 0..<count where chars[i + k] != marker { ok = false; break }
            if ok {
                // Reject if a stray marker char abuts the run on either side
                // (so * doesn't match inside ** and vice versa).
                if i > 0, chars[i - 1] == marker { i -= 1; continue }
                if i + count < end, chars[i + count] == marker { i -= 1; continue }
                return i
            }
            i -= 1
        }
        return nil
    }

    private func isValidInner(_ s: String) -> Bool {
        !s.isEmpty && !(s.first?.isWhitespace ?? true) && !(s.last?.isWhitespace ?? true)
    }

    /// When the user presses space, check whether the current line up to
    /// the cursor matches a Markdown block trigger (`# `, `- `, `1. `, etc.)
    /// and, if so, strip the trigger and apply the corresponding command.
    private func applyAutoFormatOnSpace() -> Bool {
        guard selectedRange().length == 0,
              let storage = textStorage else { return false }
        let cursor = selectedRange().location
        let nsString = storage.string as NSString
        let paraRange = nsString.paragraphRange(for: NSRange(location: cursor, length: 0))

        // Cursor must sit at the end of the current line (before any \n).
        let lineEnd = paraRange.location + paraRange.length
        let contentEnd = (lineEnd > paraRange.location
                          && nsString.character(at: lineEnd - 1) == 0x0A) ? lineEnd - 1 : lineEnd
        guard cursor == contentEnd else { return false }

        let prefix = nsString.substring(with: NSRange(
            location: paraRange.location,
            length: cursor - paraRange.location
        ))
        guard let action = Self.autoFormatAction(for: prefix) else { return false }

        let deleteRange = NSRange(location: paraRange.location,
                                  length: cursor - paraRange.location)
        guard shouldChangeText(in: deleteRange, replacementString: "") else { return false }
        storage.replaceCharacters(in: deleteRange, with: "")
        didChangeText()
        action(self)
        return true
    }

    private static func autoFormatAction(for line: String) -> ((NSTextView) -> Void)? {
        switch line {
        case "#":               return { RichTextCommand.setHeadingLevel($0, level: 1) }
        case "##":              return { RichTextCommand.setHeadingLevel($0, level: 2) }
        case "###":             return { RichTextCommand.setHeadingLevel($0, level: 3) }
        case "*", "-", "+":     return { RichTextCommand.toggleBulletList($0) }
        case ">":               return { RichTextCommand.toggleQuote($0) }
        case "[]", "[ ]":       return { RichTextCommand.toggleTodoList($0) }
        default: break
        }
        if line.range(of: #"^\d+\.$"#, options: .regularExpression) != nil {
            return { RichTextCommand.toggleNumberedList($0) }
        }
        return nil
    }

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

//
//  MarkdownHighlighter.swift
//  SmartJournalApp
//

import AppKit

enum MarkdownStyle {
    static var bodySize: CGFloat { NSFont.systemFontSize }
    static var bodyFont: NSFont { .systemFont(ofSize: bodySize) }
    static var monoFont: NSFont { .monospacedSystemFont(ofSize: bodySize, weight: .regular) }

    static func headingFont(level: Int) -> NSFont {
        let size: CGFloat
        switch level {
        case 1: size = 28
        case 2: size = 22
        case 3: size = 18
        case 4: size = 16
        default: size = 15
        }
        return .systemFont(ofSize: size, weight: .bold)
    }

    static let markerColor = NSColor.tertiaryLabelColor
    static let quoteColor = NSColor.secondaryLabelColor
    static let codeColor = NSColor.systemPink
    static let linkColor = NSColor.linkColor
}

enum MarkdownHighlighter {
    static func highlight(_ storage: NSTextStorage) {
        let fullRange = NSRange(location: 0, length: storage.length)
        guard fullRange.length > 0 else {
            storage.beginEditing()
            storage.endEditing()
            return
        }

        storage.beginEditing()
        defer { storage.endEditing() }

        // Reset to defaults
        storage.setAttributes([
            .font: MarkdownStyle.bodyFont,
            .foregroundColor: NSColor.labelColor
        ], range: fullRange)
        storage.removeAttribute(.strikethroughStyle, range: fullRange)
        storage.removeAttribute(.underlineStyle, range: fullRange)
        storage.removeAttribute(.link, range: fullRange)

        let nsString = storage.string as NSString

        // Block-level rules per line
        nsString.enumerateSubstrings(in: fullRange, options: .byLines) { _, lineRange, _, _ in
            applyBlockRules(storage, nsString: nsString, lineRange: lineRange)
        }

        // Inline rules
        applyInlineRules(storage, nsString: nsString, fullRange: fullRange)
    }

    // MARK: Block rules

    private static let headingRegex = try! NSRegularExpression(pattern: "^(#{1,6})\\s+(.*)$")
    private static let blockquoteRegex = try! NSRegularExpression(pattern: "^(>+)\\s+(.*)$")
    private static let listRegex = try! NSRegularExpression(pattern: "^([ \\t]*)([-*+]|\\d+\\.)\\s+")

    private static func applyBlockRules(_ storage: NSTextStorage, nsString: NSString, lineRange: NSRange) {
        let line = nsString.substring(with: lineRange)
        let lineNS = line as NSString
        let lineFull = NSRange(location: 0, length: lineNS.length)

        if let m = headingRegex.firstMatch(in: line, range: lineFull) {
            let hashRange = m.range(at: 1)
            let level = hashRange.length
            let absolute = NSRange(location: lineRange.location, length: lineNS.length)
            storage.addAttribute(.font, value: MarkdownStyle.headingFont(level: level), range: absolute)
            let absoluteHash = NSRange(location: lineRange.location + hashRange.location,
                                       length: hashRange.length)
            storage.addAttribute(.foregroundColor, value: MarkdownStyle.markerColor, range: absoluteHash)
            return
        }

        if let m = blockquoteRegex.firstMatch(in: line, range: lineFull) {
            let absolute = NSRange(location: lineRange.location, length: lineNS.length)
            storage.addAttribute(.foregroundColor, value: MarkdownStyle.quoteColor, range: absolute)
            addTrait(.italic, to: storage, range: absolute)
            let markerRange = m.range(at: 1)
            let absoluteMarker = NSRange(location: lineRange.location + markerRange.location,
                                         length: markerRange.length)
            storage.addAttribute(.foregroundColor, value: MarkdownStyle.markerColor, range: absoluteMarker)
            return
        }

        if let m = listRegex.firstMatch(in: line, range: lineFull) {
            let markerRange = m.range(at: 2)
            let absoluteMarker = NSRange(location: lineRange.location + markerRange.location,
                                         length: markerRange.length)
            storage.addAttribute(.foregroundColor, value: MarkdownStyle.markerColor, range: absoluteMarker)
            return
        }
    }

    // MARK: Inline rules

    private static let boldRegex = try! NSRegularExpression(pattern: "(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\1")
    private static let italicRegex = try! NSRegularExpression(
        pattern: "(?<![\\*_\\w])([*_])(?!\\1)(?=\\S)([^\\*_\\n]+?)(?<=\\S)\\1(?![\\*_\\w])"
    )
    private static let strikeRegex = try! NSRegularExpression(pattern: "(~~)(?=\\S)(.+?)(?<=\\S)~~")
    private static let codeRegex = try! NSRegularExpression(pattern: "(`)([^`\\n]+?)`")
    private static let linkRegex = try! NSRegularExpression(pattern: "\\[([^\\]\\n]+)\\]\\(([^)\\n]+)\\)")

    private static func applyInlineRules(_ storage: NSTextStorage, nsString: NSString, fullRange: NSRange) {
        let text = nsString as String

        // Code first (so other markers inside backticks aren't styled)
        codeRegex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let m = match else { return }
            let inner = m.range(at: 2)
            let openTick = NSRange(location: m.range.location, length: 1)
            let closeTick = NSRange(location: m.range.location + m.range.length - 1, length: 1)
            storage.addAttribute(.font, value: MarkdownStyle.monoFont, range: inner)
            storage.addAttribute(.foregroundColor, value: MarkdownStyle.codeColor, range: inner)
            hideMarker(storage, range: openTick)
            hideMarker(storage, range: closeTick)
        }

        // Bold
        boldRegex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let m = match else { return }
            let openMarker = NSRange(location: m.range.location, length: 2)
            let closeMarker = NSRange(location: m.range.location + m.range.length - 2, length: 2)
            let inner = m.range(at: 2)
            addTrait(.bold, to: storage, range: inner)
            hideMarker(storage, range: openMarker)
            hideMarker(storage, range: closeMarker)
        }

        // Italic
        italicRegex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let m = match else { return }
            let openMarker = NSRange(location: m.range.location, length: 1)
            let closeMarker = NSRange(location: m.range.location + m.range.length - 1, length: 1)
            let inner = m.range(at: 2)
            addTrait(.italic, to: storage, range: inner)
            hideMarker(storage, range: openMarker)
            hideMarker(storage, range: closeMarker)
        }

        // Strikethrough
        strikeRegex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let m = match else { return }
            let openMarker = NSRange(location: m.range.location, length: 2)
            let closeMarker = NSRange(location: m.range.location + m.range.length - 2, length: 2)
            let inner = m.range(at: 2)
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: inner)
            hideMarker(storage, range: openMarker)
            hideMarker(storage, range: closeMarker)
        }

        // Links: [text](url)
        linkRegex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let m = match else { return }
            let textRange = m.range(at: 1)
            let openBracket = NSRange(location: m.range.location, length: 1)
            let closeBracket = NSRange(location: textRange.location + textRange.length, length: 1)
            let openParen = NSRange(location: closeBracket.location + 1, length: 1)
            let closeParen = NSRange(location: m.range.location + m.range.length - 1, length: 1)
            let urlAndParens = NSRange(location: openParen.location,
                                       length: closeParen.location + 1 - openParen.location)

            storage.addAttribute(.foregroundColor, value: MarkdownStyle.linkColor, range: textRange)
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: textRange)
            hideMarker(storage, range: openBracket)
            hideMarker(storage, range: closeBracket)
            hideMarker(storage, range: urlAndParens)
        }
    }

    private static func hideMarker(_ storage: NSTextStorage, range: NSRange) {
        storage.addAttribute(.foregroundColor, value: NSColor.clear, range: range)
        storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 0.01), range: range)
    }

    // MARK: Helpers

    private static func addTrait(_ trait: NSFontDescriptor.SymbolicTraits,
                                 to storage: NSTextStorage,
                                 range: NSRange) {
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let baseFont = (value as? NSFont) ?? MarkdownStyle.bodyFont
            var traits = baseFont.fontDescriptor.symbolicTraits
            traits.insert(trait)
            let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits)
            let newFont = NSFont(descriptor: descriptor, size: baseFont.pointSize) ?? baseFont
            storage.addAttribute(.font, value: newFont, range: subrange)
        }
    }
}

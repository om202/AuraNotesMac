//
//  RichTextCommand.swift
//  SmartJournalApp
//

import AppKit

enum RichTextCommand {
    // MARK: Inline traits

    static func toggleBold(_ tv: NSTextView) {
        toggleTrait(tv, trait: .bold)
    }

    static func toggleItalic(_ tv: NSTextView) {
        toggleTrait(tv, trait: .italic)
    }

    static func toggleUnderline(_ tv: NSTextView) {
        toggleAttribute(tv, key: .underlineStyle,
                        on: NSUnderlineStyle.single.rawValue, off: 0)
    }

    static func toggleStrikethrough(_ tv: NSTextView) {
        toggleAttribute(tv, key: .strikethroughStyle,
                        on: NSUnderlineStyle.single.rawValue, off: 0)
    }

    // MARK: Headings

    /// level 0 = body, 1 = title, 2 = heading, 3 = subheading.
    static func setHeadingLevel(_ tv: NSTextView, level: Int) {
        let (size, weight): (CGFloat, NSFont.Weight) = {
            switch level {
            case 1: return (Theme.FontSize.title, .bold)
            case 2: return (Theme.FontSize.heading, .bold)
            case 3: return (Theme.FontSize.subheading, .semibold)
            default: return (Theme.FontSize.body, .regular)
            }
        }()
        let newFont = EditorFont.currentFamily.font(size: size, weight: weight)

        let nsString = tv.string as NSString
        let paraRange = nsString.paragraphRange(for: tv.selectedRange)
        guard tv.shouldChangeText(in: paraRange, replacementString: nil) else { return }
        let storage = tv.textStorage!
        storage.beginEditing()
        storage.addAttribute(.font, value: newFont, range: paraRange)
        storage.endEditing()
        tv.didChangeText()

        // Update typing attributes so the next keystroke continues the style
        var typing = tv.typingAttributes
        typing[.font] = newFont
        tv.typingAttributes = typing
    }

    // MARK: Lists

    static func toggleBulletList(_ tv: NSTextView) {
        applyLinePrefix(tv, kind: .bullet)
    }

    static func toggleNumberedList(_ tv: NSTextView) {
        applyLinePrefix(tv, kind: .numbered)
    }

    static func toggleTodoList(_ tv: NSTextView) {
        applyLinePrefix(tv, kind: .todo)
    }

    private enum ListKind {
        case bullet, numbered, todo
        static let bulletRegex  = try! NSRegularExpression(pattern: #"^•\s"#)
        static let numberRegex  = try! NSRegularExpression(pattern: #"^\d+\.\s"#)
        static let todoRegex    = try! NSRegularExpression(pattern: #"^[☐☑]\s"#)

        func matches(_ s: String) -> Bool {
            let range = NSRange(s.startIndex..., in: s)
            switch self {
            case .bullet:   return Self.bulletRegex.firstMatch(in: s, range: range) != nil
            case .numbered: return Self.numberRegex.firstMatch(in: s, range: range) != nil
            case .todo:     return Self.todoRegex.firstMatch(in: s, range: range) != nil
            }
        }
        func prefix(itemNumber: Int) -> String {
            switch self {
            case .bullet:   return "• "
            case .numbered: return "\(itemNumber). "
            case .todo:     return "☐ "
            }
        }
    }

    /// Strip any existing list prefix at the start of `para`. Returns the length removed.
    @discardableResult
    private static func stripExistingListPrefix(_ para: NSMutableAttributedString) -> Int {
        let s = para.string
        let range = NSRange(s.startIndex..., in: s)
        for regex in [ListKind.bulletRegex, ListKind.numberRegex, ListKind.todoRegex] {
            if let m = regex.firstMatch(in: s, range: range), m.range.location == 0 {
                para.deleteCharacters(in: m.range); return m.range.length
            }
        }
        return 0
    }

    private static func applyLinePrefix(_ tv: NSTextView, kind: ListKind) {
        let storage = tv.textStorage!
        let nsString = storage.string as NSString
        let paraRange = nsString.paragraphRange(for: tv.selectedRange)
        guard tv.shouldChangeText(in: paraRange, replacementString: "") else { return }

        let original = storage.attributedSubstring(from: paraRange)
        let originalNS = original.string as NSString

        // Collect paragraph ranges within the affected region.
        var paragraphs: [NSRange] = []
        var i = 0
        while i < originalNS.length {
            let pr = originalNS.paragraphRange(for: NSRange(location: i, length: 0))
            paragraphs.append(pr)
            i = pr.location + pr.length
            if pr.length == 0 { break }
        }
        if paragraphs.isEmpty { paragraphs = [NSRange(location: 0, length: 0)] }

        // Toggle off only if every non-empty paragraph already starts with this kind of prefix.
        let nonEmpty = paragraphs.filter { $0.length > 0 }
        let allMatch = !nonEmpty.isEmpty && nonEmpty.allSatisfy { kind.matches(originalNS.substring(with: $0)) }

        let result = NSMutableAttributedString()
        var itemNumber = 1

        for pr in paragraphs {
            let para = (original.attributedSubstring(from: pr).mutableCopy() as! NSMutableAttributedString)
            stripExistingListPrefix(para)

            if !allMatch {
                let prefix = kind.prefix(itemNumber: itemNumber)
                let attrs = para.length > 0
                    ? para.attributes(at: 0, effectiveRange: nil)
                    : tv.typingAttributes
                para.insert(NSAttributedString(string: prefix, attributes: attrs), at: 0)
                itemNumber += 1
            }
            result.append(para)
        }

        storage.replaceCharacters(in: paraRange, with: result)
        tv.didChangeText()
    }

    // MARK: Quote

    private static let quotePrefix = "▎ "

    static func toggleQuote(_ tv: NSTextView) {
        let storage = tv.textStorage!
        let nsString = storage.string as NSString
        let paraRange = nsString.paragraphRange(for: tv.selectedRange)
        guard tv.shouldChangeText(in: paraRange, replacementString: "") else { return }

        let original = storage.attributedSubstring(from: paraRange)
        let originalNS = original.string as NSString

        var paragraphs: [NSRange] = []
        var i = 0
        while i < originalNS.length {
            let pr = originalNS.paragraphRange(for: NSRange(location: i, length: 0))
            paragraphs.append(pr)
            i = pr.location + pr.length
            if pr.length == 0 { break }
        }
        if paragraphs.isEmpty { paragraphs = [NSRange(location: 0, length: 0)] }

        let nonEmpty = paragraphs.filter { $0.length > 0 }
        let allQuoted = !nonEmpty.isEmpty && nonEmpty.allSatisfy {
            originalNS.substring(with: $0).hasPrefix(quotePrefix)
        }

        let quoteStyle: NSMutableParagraphStyle = {
            let s = NSMutableParagraphStyle()
            s.firstLineHeadIndent = 0
            s.headIndent = 16
            return s
        }()

        let prefixNSLen = (quotePrefix as NSString).length
        let result = NSMutableAttributedString()

        for pr in paragraphs {
            let para = (original.attributedSubstring(from: pr).mutableCopy() as! NSMutableAttributedString)

            if para.string.hasPrefix(quotePrefix) {
                para.deleteCharacters(in: NSRange(location: 0, length: prefixNSLen))
                if para.length > 0 {
                    para.addAttribute(.paragraphStyle,
                                      value: NSParagraphStyle.default,
                                      range: NSRange(location: 0, length: para.length))
                }
            }

            if !allQuoted {
                let baseAttrs: [NSAttributedString.Key: Any] = para.length > 0
                    ? para.attributes(at: 0, effectiveRange: nil)
                    : tv.typingAttributes
                var prefixAttrs = baseAttrs
                prefixAttrs[.foregroundColor] = NSColor.tertiaryLabelColor
                prefixAttrs[.paragraphStyle] = quoteStyle
                para.insert(NSAttributedString(string: quotePrefix, attributes: prefixAttrs), at: 0)
                if para.length > prefixNSLen {
                    para.addAttribute(.paragraphStyle,
                                      value: quoteStyle,
                                      range: NSRange(location: prefixNSLen, length: para.length - prefixNSLen))
                }
            }

            result.append(para)
        }

        storage.replaceCharacters(in: paraRange, with: result)
        tv.didChangeText()
    }

    // MARK: Table

    static func insertTable(_ tv: NSTextView, rows: Int, columns: Int) {
        guard rows > 0, columns > 0, let storage = tv.textStorage else { return }

        let table = NSTextTable()
        table.numberOfColumns = columns
        table.layoutAlgorithm = .automaticLayoutAlgorithm
        table.collapsesBorders = true
        table.hidesEmptyCells = false

        let baseFont  = (tv.typingAttributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let baseColor = (tv.typingAttributes[.foregroundColor] as? NSColor) ?? .labelColor

        let body = NSMutableAttributedString()

        for r in 0..<rows {
            for c in 0..<columns {
                let block = NSTextTableBlock(table: table,
                                             startingRow: r, rowSpan: 1,
                                             startingColumn: c, columnSpan: 1)
                block.setBorderColor(.separatorColor)
                block.setWidth(1, type: .absoluteValueType, for: .border)
                block.setWidth(6, type: .absoluteValueType, for: .padding)

                let style = NSMutableParagraphStyle()
                style.textBlocks = [block]

                let cellText = "  \n"
                body.append(NSAttributedString(string: cellText, attributes: [
                    .font: baseFont,
                    .foregroundColor: baseColor,
                    .paragraphStyle: style
                ]))
            }
        }

        // Trailing paragraph in default style so the cursor exits the table cleanly.
        body.append(NSAttributedString(string: "\n", attributes: [
            .font: baseFont,
            .foregroundColor: baseColor,
            .paragraphStyle: NSParagraphStyle.default
        ]))

        let range = tv.selectedRange
        guard tv.shouldChangeText(in: range, replacementString: body.string) else { return }
        storage.replaceCharacters(in: range, with: body)
        tv.didChangeText()

        // Place the cursor inside the first cell.
        tv.setSelectedRange(NSRange(location: range.location, length: 0))
    }

    // MARK: Link

    static func insertLink(_ tv: NSTextView) {
        let range = tv.selectedRange
        let nsString = tv.string as NSString
        let selected = nsString.substring(with: range)

        let alert = NSAlert()
        alert.messageText = "Insert Link"
        alert.informativeText = "Enter a URL"
        alert.addButton(withTitle: "Insert")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = "https://"
        field.placeholderString = "https://example.com"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let urlText = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlText.isEmpty, let url = URL(string: urlText) else { return }

        let display = selected.isEmpty ? urlText : selected
        let attrs: [NSAttributedString.Key: Any] = [
            .link: url,
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .font: (tv.typingAttributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        ]
        let attrString = NSAttributedString(string: display, attributes: attrs)
        guard tv.shouldChangeText(in: range, replacementString: display) else { return }
        tv.textStorage?.replaceCharacters(in: range, with: attrString)
        tv.didChangeText()
    }

    // MARK: Undo / Redo

    static func performUndo(_ tv: NSTextView) {
        tv.undoManager?.undo()
    }

    static func performRedo(_ tv: NSTextView) {
        tv.undoManager?.redo()
    }

    // MARK: Trait/attribute primitives

    private static func toggleTrait(_ tv: NSTextView, trait: NSFontDescriptor.SymbolicTraits) {
        let range = tv.selectedRange

        if range.length == 0 {
            // Update typing attributes only — affects the next keystroke
            var typing = tv.typingAttributes
            let font = (typing[.font] as? NSFont) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            var traits = font.fontDescriptor.symbolicTraits
            if traits.contains(trait) { traits.remove(trait) } else { traits.insert(trait) }
            let desc = font.fontDescriptor.withSymbolicTraits(traits)
            let newFont = NSFont(descriptor: desc, size: font.pointSize) ?? font
            typing[.font] = newFont
            tv.typingAttributes = typing
            return
        }

        guard tv.shouldChangeText(in: range, replacementString: nil) else { return }
        let storage = tv.textStorage!
        storage.beginEditing()

        var allHaveTrait = true
        storage.enumerateAttribute(.font, in: range, options: []) { value, _, stop in
            let f = (value as? NSFont) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            if !f.fontDescriptor.symbolicTraits.contains(trait) {
                allHaveTrait = false; stop.pointee = true
            }
        }
        storage.enumerateAttribute(.font, in: range, options: []) { value, sub, _ in
            let f = (value as? NSFont) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            var traits = f.fontDescriptor.symbolicTraits
            if allHaveTrait { traits.remove(trait) } else { traits.insert(trait) }
            let desc = f.fontDescriptor.withSymbolicTraits(traits)
            let newFont = NSFont(descriptor: desc, size: f.pointSize) ?? f
            storage.addAttribute(.font, value: newFont, range: sub)
        }
        storage.endEditing()
        tv.didChangeText()
    }

    private static func toggleAttribute(_ tv: NSTextView,
                                        key: NSAttributedString.Key,
                                        on onValue: Any,
                                        off offValue: Any) {
        let range = tv.selectedRange
        if range.length == 0 {
            var typing = tv.typingAttributes
            let current = typing[key] as? Int ?? 0
            typing[key] = (current == 0) ? onValue : offValue
            tv.typingAttributes = typing
            return
        }
        guard tv.shouldChangeText(in: range, replacementString: nil) else { return }
        let storage = tv.textStorage!
        storage.beginEditing()
        var allOn = true
        storage.enumerateAttribute(key, in: range, options: []) { value, _, stop in
            let v = value as? Int ?? 0
            if v == 0 { allOn = false; stop.pointee = true }
        }
        if allOn {
            storage.removeAttribute(key, range: range)
        } else {
            storage.addAttribute(key, value: onValue, range: range)
        }
        storage.endEditing()
        tv.didChangeText()
    }
}

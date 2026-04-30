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

    static func toggleCode(_ tv: NSTextView) {
        let range = tv.selectedRange

        if range.length == 0 {
            var typing = tv.typingAttributes
            let f = (typing[.font] as? NSFont) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            typing[.font] = f.isFixedPitch
                ? EditorFont.currentFamily.font(size: f.pointSize)
                : NSFont.monospacedSystemFont(ofSize: f.pointSize, weight: .regular)
            tv.typingAttributes = typing
            return
        }

        guard tv.shouldChangeText(in: range, replacementString: nil) else { return }
        let storage = tv.textStorage!
        storage.beginEditing()

        var allMono = true
        storage.enumerateAttribute(.font, in: range, options: []) { value, _, stop in
            let f = (value as? NSFont) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            if !f.isFixedPitch { allMono = false; stop.pointee = true }
        }
        storage.enumerateAttribute(.font, in: range, options: []) { value, sub, _ in
            let f = (value as? NSFont) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            let newFont: NSFont = allMono
                ? EditorFont.currentFamily.font(size: f.pointSize)
                : NSFont.monospacedSystemFont(ofSize: f.pointSize, weight: .regular)
            storage.addAttribute(.font, value: newFont, range: sub)
            let color: NSColor = allMono ? Theme.EditorColor.body : Theme.EditorColor.code
            storage.addAttribute(.foregroundColor, value: color, range: sub)
        }
        storage.endEditing()
        tv.didChangeText()
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
        let newColor = headingColor(for: level)

        let nsString = tv.string as NSString
        let paraRange = nsString.paragraphRange(for: tv.selectedRange)
        guard tv.shouldChangeText(in: paraRange, replacementString: nil) else { return }
        let storage = tv.textStorage!
        storage.beginEditing()
        storage.addAttribute(.font, value: newFont, range: paraRange)
        storage.addAttribute(.foregroundColor, value: newColor, range: paraRange)
        storage.endEditing()
        tv.didChangeText()

        // Update typing attributes so the next keystroke continues the style
        var typing = tv.typingAttributes
        typing[.font] = newFont
        typing[.foregroundColor] = newColor
        tv.typingAttributes = typing
    }

    static func headingColor(for level: Int) -> NSColor {
        switch level {
        case 1: return Theme.EditorColor.title
        case 2: return Theme.EditorColor.heading
        case 3: return Theme.EditorColor.subheading
        default: return Theme.EditorColor.body
        }
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

    // MARK: List continuation

    enum DetectedList {
        case bullet(prefixLength: Int)
        case numbered(value: Int, prefixLength: Int)
        case todo(prefixLength: Int)

        /// UTF-16 length of the prefix on the source line.
        var prefixLength: Int {
            switch self {
            case .bullet(let l), .todo(let l):    return l
            case .numbered(_, let l):             return l
            }
        }
    }

    /// Detects a list prefix at the start of `line`. Returns `nil` for
    /// non-list paragraphs.
    static func detectList(in line: String) -> DetectedList? {
        let range = NSRange(line.startIndex..., in: line)
        if let m = ListKind.bulletRegex.firstMatch(in: line, range: range),
           m.range.location == 0 {
            return .bullet(prefixLength: m.range.length)
        }
        if let m = ListKind.todoRegex.firstMatch(in: line, range: range),
           m.range.location == 0 {
            return .todo(prefixLength: m.range.length)
        }
        if let m = ListKind.numberRegex.firstMatch(in: line, range: range),
           m.range.location == 0 {
            let prefix = (line as NSString).substring(with: m.range)
            if let dot = prefix.firstIndex(of: "."),
               let n = Int(prefix[..<dot]) {
                return .numbered(value: n, prefixLength: m.range.length)
            }
        }
        return nil
    }

    // MARK: List styling

    /// Width (in points) reserved for the marker + gap. Used both as the
    /// tab stop on the first line and the head indent for wrapped lines,
    /// giving Apple-Notes–style hanging indent.
    private static func listIndent(for baseFont: NSFont) -> CGFloat {
        baseFont.pointSize * 1.6
    }

    private static func markerPrefix(
        marker: String,
        baseAttrs: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        var markerAttrs = baseAttrs
        markerAttrs[.foregroundColor] = Theme.EditorColor.listMarker
        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: marker, attributes: markerAttrs))
        result.append(NSAttributedString(string: "\t", attributes: baseAttrs))
        return result
    }

    static func bulletPrefix(
        baseAttrs: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        markerPrefix(marker: "●", baseAttrs: baseAttrs)
    }

    static func todoPrefix(
        baseAttrs: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        markerPrefix(marker: "☐", baseAttrs: baseAttrs)
    }

    static func numberedPrefix(
        value: Int,
        baseAttrs: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        var markerAttrs = baseAttrs
        markerAttrs[.foregroundColor] = Theme.EditorColor.listMarker
        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: "\(value).", attributes: markerAttrs))
        result.append(NSAttributedString(string: "\t", attributes: baseAttrs))
        return result
    }

    /// Hanging-indent paragraph style shared by all list kinds.
    static func listParagraphStyle(baseFont: NSFont) -> NSParagraphStyle {
        let stop = listIndent(for: baseFont)
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = 0
        style.headIndent = stop
        style.tabStops = [
            NSTextTab(textAlignment: .left, location: stop, options: [:])
        ]
        return style
    }

    private enum ListKind {
        case bullet, numbered, todo
        static let bulletRegex  = try! NSRegularExpression(pattern: #"^●[ \t]+"#)
        static let numberRegex  = try! NSRegularExpression(pattern: #"^\d+\.[ \t]+"#)
        static let todoRegex    = try! NSRegularExpression(pattern: #"^[☐☑][ \t]+"#)

        func matches(_ s: String) -> Bool {
            let range = NSRange(s.startIndex..., in: s)
            switch self {
            case .bullet:   return Self.bulletRegex.firstMatch(in: s, range: range) != nil
            case .numbered: return Self.numberRegex.firstMatch(in: s, range: range) != nil
            case .todo:     return Self.todoRegex.firstMatch(in: s, range: range) != nil
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
                let baseAttrs: [NSAttributedString.Key: Any] = para.length > 0
                    ? para.attributes(at: 0, effectiveRange: nil)
                    : tv.typingAttributes
                let baseFont = (baseAttrs[.font] as? NSFont)
                    ?? NSFont.systemFont(ofSize: Theme.FontSize.body)

                let prefix: NSAttributedString
                switch kind {
                case .bullet:
                    prefix = bulletPrefix(baseAttrs: baseAttrs)
                case .numbered:
                    prefix = numberedPrefix(value: itemNumber, baseAttrs: baseAttrs)
                case .todo:
                    prefix = todoPrefix(baseAttrs: baseAttrs)
                }
                para.insert(prefix, at: 0)

                if para.length > 0 {
                    para.addAttribute(
                        .paragraphStyle,
                        value: listParagraphStyle(baseFont: baseFont),
                        range: NSRange(location: 0, length: para.length)
                    )
                }

                itemNumber += 1
            } else if para.length > 0 {
                // Toggle off: drop any bullet hanging-indent style.
                para.addAttribute(
                    .paragraphStyle,
                    value: NSParagraphStyle.default,
                    range: NSRange(location: 0, length: para.length)
                )
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
                prefixAttrs[.foregroundColor] = Theme.EditorColor.quote
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

        var typing = tv.typingAttributes
        typing[.foregroundColor] = Theme.EditorColor.body
        typing[.paragraphStyle] = allQuoted ? NSParagraphStyle.default : quoteStyle
        tv.typingAttributes = typing
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
            .foregroundColor: Theme.EditorColor.body,
            .font: (tv.typingAttributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        ]
        let attrString = NSAttributedString(string: display, attributes: attrs)
        guard tv.shouldChangeText(in: range, replacementString: display) else { return }
        tv.textStorage?.replaceCharacters(in: range, with: attrString)
        tv.didChangeText()
    }

    // MARK: Font scaling

    static func scaleFonts(in tv: NSTextView, by factor: CGFloat) {
        let clampSize: (CGFloat) -> CGFloat = { max(8, min(96, $0 * factor)) }

        if let storage = tv.textStorage {
            let full = NSRange(location: 0, length: storage.length)
            if full.length > 0, tv.shouldChangeText(in: full, replacementString: nil) {
                storage.beginEditing()
                storage.enumerateAttribute(.font, in: full, options: []) { value, range, _ in
                    let f = (value as? NSFont) ?? NSFont.systemFont(ofSize: Theme.FontSize.body)
                    let newFont = NSFont(descriptor: f.fontDescriptor, size: clampSize(f.pointSize)) ?? f
                    storage.addAttribute(.font, value: newFont, range: range)
                }
                storage.endEditing()
                tv.didChangeText()
            }
        }

        var typing = tv.typingAttributes
        if let f = typing[.font] as? NSFont {
            typing[.font] = NSFont(descriptor: f.fontDescriptor, size: clampSize(f.pointSize)) ?? f
            tv.typingAttributes = typing
        }
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

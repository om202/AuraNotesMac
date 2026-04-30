//
//  RichTextCommand.swift
//  AuraNotes
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
    ///
    /// Walks every `.font` run in the affected paragraph and rebuilds the
    /// font with the heading's size and weight while preserving the run's
    /// own italic/monospace traits. A run that was already bold stays
    /// bold even when targeting a non-bold heading level — so a bold word
    /// inside a subheading still reads bolder than its neighbors.
    static func setHeadingLevel(_ tv: NSTextView, level: Int) {
        let (size, weight): (CGFloat, NSFont.Weight) = {
            switch level {
            case 1: return (Theme.FontSize.title, .bold)
            case 2: return (Theme.FontSize.heading, .bold)
            case 3: return (Theme.FontSize.subheading, .semibold)
            default: return (Theme.FontSize.body, .regular)
            }
        }()
        let newColor = headingColor(for: level)
        let family = EditorFont.currentFamily
        let bodyFallback = family.font(size: Theme.FontSize.body)

        let nsString = tv.string as NSString
        let paraRange = nsString.paragraphRange(for: tv.selectedRange)
        guard paraRange.length >= 0,
              tv.shouldChangeText(in: paraRange, replacementString: nil) else { return }
        let storage = tv.textStorage!
        storage.beginEditing()

        if paraRange.length > 0 {
            storage.enumerateAttribute(.font, in: paraRange, options: []) { value, range, _ in
                let old = (value as? NSFont) ?? bodyFallback
                let mapped = headingMappedFont(
                    old: old, targetSize: size, targetWeight: weight, family: family
                )
                storage.addAttribute(.font, value: mapped, range: range)
            }
            storage.addAttribute(.foregroundColor, value: newColor, range: paraRange)
        }
        storage.endEditing()
        tv.didChangeText()

        // Update typing attributes so the next keystroke continues the style.
        var typing = tv.typingAttributes
        let typingOld = (typing[.font] as? NSFont) ?? bodyFallback
        typing[.font] = headingMappedFont(
            old: typingOld, targetSize: size, targetWeight: weight, family: family
        )
        typing[.foregroundColor] = newColor
        tv.typingAttributes = typing
    }

    /// Build a font at the heading's target size/weight while preserving
    /// the source run's italic + monospace traits and any "bolder than
    /// target" weight.
    private static func headingMappedFont(
        old: NSFont,
        targetSize: CGFloat,
        targetWeight: NSFont.Weight,
        family: EditorFontFamily
    ) -> NSFont {
        let oldTraits = old.fontDescriptor.symbolicTraits
        let italic = oldTraits.contains(.italic)
        let mono = oldTraits.contains(.monoSpace)

        // If the run was already bolder than the target, keep it bold so
        // it remains visually distinguished within the new style.
        let runIsBold = oldTraits.contains(.bold)
            || old.editorWeight.rawValue >= NSFont.Weight.semibold.rawValue
        let effectiveWeight: NSFont.Weight =
            (runIsBold && targetWeight.rawValue < NSFont.Weight.bold.rawValue)
            ? .bold
            : targetWeight

        if mono {
            var f = NSFont.monospacedSystemFont(ofSize: targetSize, weight: effectiveWeight)
            if italic,
               let italicized = NSFont(
                descriptor: f.fontDescriptor.withSymbolicTraits(.italic),
                size: targetSize) {
                f = italicized
            }
            return f
        }
        return family.font(size: targetSize, weight: effectiveWeight, italic: italic)
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

    static func toggleNumberedList(_ tv: NSTextView, startingAt: Int = 1) {
        applyLinePrefix(tv, kind: .numbered, startingAt: max(1, startingAt))
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

    /// Glyph used at each indent level. Levels deeper than the array
    /// length clamp to the last entry. ● filled disc anchors the list,
    /// ○ open circle marks subordination, ▪ small square distinguishes
    /// further nesting from the disc/circle pair.
    static let bulletGlyphs: [String] = ["●", "○", "▪"]

    static func bulletGlyph(forLevel level: Int) -> String {
        let idx = max(0, min(level, bulletGlyphs.count - 1))
        return bulletGlyphs[idx]
    }

    static func bulletPrefix(
        forLevel level: Int = 0,
        baseAttrs: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        markerPrefix(marker: bulletGlyph(forLevel: level), baseAttrs: baseAttrs)
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
        static let bulletRegex  = try! NSRegularExpression(pattern: #"^[●○▪][ \t]+"#)
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

    private static func applyLinePrefix(_ tv: NSTextView, kind: ListKind, startingAt: Int = 1) {
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
        var itemNumber = startingAt

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

        // After applying numbered prefixes, merge with any adjacent numbered
        // run above so the visible sequence is continuous.
        if kind == .numbered {
            renumberAroundLocation(in: tv, location: paraRange.location)
        }
    }

    // MARK: Numbered list renumbering

    /// Walks the contiguous numbered-paragraph run that contains `location`
    /// and rewrites each marker so the sequence is continuous, starting
    /// from whatever number the first surviving item carries. A no-op if
    /// `location` doesn't sit inside a numbered paragraph.
    static func renumberAroundLocation(in tv: NSTextView, location: Int) {
        guard let storage = tv.textStorage else { return }
        renumberRun(in: storage, around: location)
    }

    /// Probes the cursor and the position just before it. Two probes
    /// catches the common "delete joined two paragraphs" case where the
    /// cursor lands on the merged paragraph but the affected run starts
    /// before it.
    static func renumberAroundCursor(in tv: NSTextView) {
        guard let storage = tv.textStorage, storage.length > 0 else { return }
        let cursor = tv.selectedRange.location
        renumberRun(in: storage, around: max(0, min(cursor, storage.length - 1)))
        if cursor > 0 {
            renumberRun(in: storage, around: max(0, cursor - 1))
        }
    }

    private static func renumberRun(in storage: NSTextStorage, around location: Int) {
        let initialNS = storage.string as NSString
        guard initialNS.length > 0,
              location >= 0, location < initialNS.length else { return }

        let here = initialNS.paragraphRange(for: NSRange(location: location, length: 0))
        let hereLine = stripTrailingNewline(initialNS.substring(with: here))
        guard isNumberedLine(hereLine) else { return }

        // Walk up to find the start of the contiguous numbered run.
        var runStart = here.location
        while runStart > 0 {
            let prevPara = initialNS.paragraphRange(
                for: NSRange(location: runStart - 1, length: 0)
            )
            let prevLine = stripTrailingNewline(initialNS.substring(with: prevPara))
            if isNumberedLine(prevLine) {
                runStart = prevPara.location
            } else {
                break
            }
        }

        // The first surviving item's number defines the start of its level.
        let firstPara = initialNS.paragraphRange(
            for: NSRange(location: runStart, length: 0)
        )
        let firstLine = stripTrailingNewline(initialNS.substring(with: firstPara))
        let firstStartNumber = max(1, parseLeadingNumber(firstLine) ?? 1)
        let firstLevel = indentLevel(of: firstPara, in: storage)

        // Walk forward, tracking a counter per indent level. Going deeper
        // resets the deeper level's counter to 1; coming back up clears any
        // deeper counters so a re-entry restarts cleanly. The very first
        // item's level starts from its existing number; everything else
        // restarts at 1 the first time its level is entered.
        var counters: [Int: Int] = [:]
        var isFirst = true
        var loc = runStart
        while loc < storage.length {
            let curNS = storage.string as NSString
            guard loc < curNS.length else { break }
            let pr = curNS.paragraphRange(for: NSRange(location: loc, length: 0))
            let line = stripTrailingNewline(curNS.substring(with: pr))
            guard isNumberedLine(line) else { break }

            let level = indentLevel(of: pr, in: storage)

            // Drop counters for deeper levels — they were nested under a
            // shallower run that just ended.
            for l in counters.keys where l > level { counters[l] = nil }

            let value: Int
            if isFirst {
                value = firstStartNumber
                _ = firstLevel    // explicitly read for clarity; level == firstLevel here
            } else if let existing = counters[level] {
                value = existing + 1
            } else {
                value = 1
            }
            counters[level] = value
            isFirst = false

            let lineNS = line as NSString
            let dotRange = lineNS.range(of: ".")
            if dotRange.location != NSNotFound, dotRange.location > 0 {
                let digitsRange = NSRange(
                    location: pr.location, length: dotRange.location
                )
                let curDigits = curNS.substring(with: digitsRange)
                let newDigits = "\(value)"
                if curDigits != newDigits {
                    let attrs = storage.attributes(
                        at: digitsRange.location, effectiveRange: nil
                    )
                    storage.replaceCharacters(
                        in: digitsRange,
                        with: NSAttributedString(string: newDigits, attributes: attrs)
                    )
                }
            }
            let updatedNS = storage.string as NSString
            guard loc < updatedNS.length else { break }
            let updatedPr = updatedNS.paragraphRange(
                for: NSRange(location: loc, length: 0)
            )
            loc = updatedPr.location + updatedPr.length
        }
    }

    /// Indent level of a paragraph, derived from its `firstLineHeadIndent`
    /// divided by the per-level step (`pointSize * 1.6`). Mirrors the unit
    /// `handleListIndent` uses to shift list paragraphs.
    private static func indentLevel(of paraRange: NSRange,
                                    in storage: NSTextStorage) -> Int {
        guard paraRange.length > 0,
              paraRange.location < storage.length else { return 0 }
        let attrs = storage.attributes(at: paraRange.location, effectiveRange: nil)
        let style = (attrs[.paragraphStyle] as? NSParagraphStyle)
            ?? NSParagraphStyle.default
        let font = (attrs[.font] as? NSFont)
            ?? NSFont.systemFont(ofSize: Theme.FontSize.body)
        let stop = font.pointSize * 1.6
        guard stop > 0 else { return 0 }
        return max(0, Int(round(style.firstLineHeadIndent / stop)))
    }

    private static func stripTrailingNewline(_ s: String) -> String {
        s.hasSuffix("\n") ? String(s.dropLast()) : s
    }

    private static func isNumberedLine(_ s: String) -> Bool {
        let range = NSRange(s.startIndex..., in: s)
        return ListKind.numberRegex.firstMatch(in: s, range: range) != nil
    }

    private static func parseLeadingNumber(_ s: String) -> Int? {
        var digits = ""
        for c in s {
            if c.isNumber { digits.append(c) } else { break }
        }
        return Int(digits)
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

    /// Per-run "what size was this before the user started scaling" memory.
    /// Lets ⌘− then ⌘+ return exactly to the original size instead of
    /// drifting after a clamp at the floor.
    static let editorBaseSize = NSAttributedString.Key("auraEditorBaseSize")
    /// Number of scale steps applied since the base size was captured.
    static let editorScaleSteps = NSAttributedString.Key("auraEditorScaleSteps")

    private static let scaleStepFactor: CGFloat = 1.1
    private static let minFontSize: CGFloat = 8
    private static let maxFontSize: CGFloat = 96

    /// Scale all fonts up (`factor > 1`) or down (`factor < 1`). The actual
    /// magnitude is fixed at `scaleStepFactor` per call; the parameter is
    /// only consulted for direction. Each run remembers the size it had
    /// before the first scale, so ⌘− at the floor followed by ⌘+ recovers
    /// the original size.
    static func scaleFonts(in tv: NSTextView, by factor: CGFloat) {
        let direction: Int = factor > 1 ? 1 : (factor < 1 ? -1 : 0)
        guard direction != 0 else { return }

        if let storage = tv.textStorage {
            let full = NSRange(location: 0, length: storage.length)
            if full.length > 0, tv.shouldChangeText(in: full, replacementString: nil) {
                storage.beginEditing()
                var loc = 0
                while loc < storage.length {
                    var effective = NSRange()
                    let f = (storage.attribute(
                        .font, at: loc, longestEffectiveRange: &effective, in: full
                    ) as? NSFont) ?? NSFont.systemFont(ofSize: Theme.FontSize.body)

                    let prevBase = (storage.attribute(
                        editorBaseSize, at: loc, effectiveRange: nil
                    ) as? NSNumber)?.doubleValue
                    let prevSteps = (storage.attribute(
                        editorScaleSteps, at: loc, effectiveRange: nil
                    ) as? NSNumber)?.intValue

                    let base = prevBase.map { CGFloat($0) } ?? f.pointSize
                    let steps = prevSteps ?? 0
                    let newSteps = clampedScaleSteps(base: base, desired: steps + direction)
                    let newSize = scaledFontSize(base: base, steps: newSteps)
                    let newFont = NSFont(descriptor: f.fontDescriptor, size: newSize) ?? f

                    storage.addAttribute(.font, value: newFont, range: effective)
                    storage.addAttribute(editorBaseSize,
                                         value: NSNumber(value: Double(base)),
                                         range: effective)
                    storage.addAttribute(editorScaleSteps,
                                         value: NSNumber(value: newSteps),
                                         range: effective)
                    loc = NSMaxRange(effective)
                }
                storage.endEditing()
                tv.didChangeText()
            }
        }

        // Typing attributes mirror the run-level bookkeeping.
        var typing = tv.typingAttributes
        if let f = typing[.font] as? NSFont {
            let base = (typing[editorBaseSize] as? NSNumber)
                .map { CGFloat($0.doubleValue) } ?? f.pointSize
            let steps = (typing[editorScaleSteps] as? NSNumber)?.intValue ?? 0
            let newSteps = clampedScaleSteps(base: base, desired: steps + direction)
            let newSize = scaledFontSize(base: base, steps: newSteps)
            typing[.font] = NSFont(descriptor: f.fontDescriptor, size: newSize) ?? f
            typing[editorBaseSize] = NSNumber(value: Double(base))
            typing[editorScaleSteps] = NSNumber(value: newSteps)
            tv.typingAttributes = typing
        }
    }

    private static func scaledFontSize(base: CGFloat, steps: Int) -> CGFloat {
        let raw = base * pow(scaleStepFactor, CGFloat(steps))
        return max(minFontSize, min(maxFontSize, raw))
    }

    /// Clamp `desired` to the range of step counts that actually change
    /// the rendered size — going further in the same direction beyond
    /// these bounds is a visual no-op, so we don't accumulate phantom
    /// steps the user would have to "undo" before the size moves again.
    private static func clampedScaleSteps(base: CGFloat, desired: Int) -> Int {
        let logFactor = log(scaleStepFactor)
        let minSteps = Int(ceil(log(minFontSize / base) / logFactor))
        let maxSteps = Int(floor(log(maxFontSize / base) / logFactor))
        return max(minSteps, min(maxSteps, desired))
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

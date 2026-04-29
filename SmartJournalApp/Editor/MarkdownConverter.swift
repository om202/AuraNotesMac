//
//  MarkdownConverter.swift
//  SmartJournalApp
//

import AppKit

enum MarkdownConverter {

    static func convert(
        _ markdown: String,
        baseAttrs: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let baseFont = (baseAttrs[.font] as? NSFont)
            ?? NSFont.systemFont(ofSize: Theme.FontSize.body)
        let family = EditorFontFamily.family(of: baseFont) ?? EditorFont.currentFamily

        let lines = markdown.components(separatedBy: "\n")
        let result = NSMutableAttributedString()
        var inFence = false
        var numberCounter = 0
        var i = 0

        while i < lines.count {
            let raw = lines[i]

            // Code fences: ``` … ```
            if raw.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inFence.toggle()
                i += 1
                continue
            }
            if inFence {
                let mono = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular)
                var attrs = baseAttrs
                attrs[.font] = mono
                attrs[.foregroundColor] = Theme.EditorColor.code
                result.append(NSAttributedString(string: raw, attributes: attrs))
                appendNewlineIfNotLast(into: result, idx: i, total: lines.count, attrs: baseAttrs)
                i += 1
                continue
            }

            // GFM table: header row "|...|" + separator "|---|---|"
            if i + 1 < lines.count,
               looksLikeTableRow(lines[i]),
               isTableSeparator(lines[i + 1]) {
                let (table, consumed) = parseTable(
                    lines: lines, from: i, baseAttrs: baseAttrs, baseFont: baseFont
                )
                result.append(table)
                i += consumed
                numberCounter = 0
                continue
            }

            // Backslash-escaped block start: "\#" → "#" not heading.
            // Handled by stripping the leading backslash before block matching.
            let line = stripLeadingEscape(raw)

            // Headings
            if let h = matchHeading(line) {
                let (size, weight): (CGFloat, NSFont.Weight) = {
                    switch h.level {
                    case 1: return (Theme.FontSize.title, .bold)
                    case 2: return (Theme.FontSize.heading, .bold)
                    default: return (Theme.FontSize.subheading, .semibold)
                    }
                }()
                var attrs = baseAttrs
                attrs[.font] = family.font(size: size, weight: weight)
                attrs[.foregroundColor] = RichTextCommand.headingColor(for: h.level)
                result.append(parseInline(h.text, baseAttrs: attrs))
                numberCounter = 0
            } else if let (n, text) = matchNumbered(line) {
                let next = numberCounter == 0 ? n : numberCounter + 1
                numberCounter = next
                let para = NSMutableAttributedString()
                para.append(RichTextCommand.numberedPrefix(value: next, baseAttrs: baseAttrs))
                para.append(parseInline(text, baseAttrs: baseAttrs))
                para.addAttribute(
                    .paragraphStyle,
                    value: RichTextCommand.listParagraphStyle(baseFont: baseFont),
                    range: NSRange(location: 0, length: para.length)
                )
                result.append(para)
            } else if let (checked, text) = matchTodo(line) {
                let para = NSMutableAttributedString()
                let marker = String(checked ? JournalTextView.checked : JournalTextView.unchecked) + "\t"
                para.append(NSAttributedString(string: marker, attributes: baseAttrs))
                para.append(parseInline(text, baseAttrs: baseAttrs))
                para.addAttribute(
                    .paragraphStyle,
                    value: RichTextCommand.listParagraphStyle(baseFont: baseFont),
                    range: NSRange(location: 0, length: para.length)
                )
                result.append(para)
                numberCounter = 0
            } else if let text = matchBullet(line) {
                let para = NSMutableAttributedString()
                para.append(RichTextCommand.bulletPrefix(baseAttrs: baseAttrs))
                para.append(parseInline(text, baseAttrs: baseAttrs))
                para.addAttribute(
                    .paragraphStyle,
                    value: RichTextCommand.listParagraphStyle(baseFont: baseFont),
                    range: NSRange(location: 0, length: para.length)
                )
                result.append(para)
                numberCounter = 0
            } else if let text = matchQuote(line) {
                let style = NSMutableParagraphStyle()
                style.firstLineHeadIndent = 0
                style.headIndent = 16
                var prefAttrs = baseAttrs
                prefAttrs[.foregroundColor] = Theme.EditorColor.quote
                let para = NSMutableAttributedString()
                para.append(NSAttributedString(string: "▎ ", attributes: prefAttrs))
                para.append(parseInline(text, baseAttrs: baseAttrs))
                para.addAttribute(
                    .paragraphStyle, value: style,
                    range: NSRange(location: 0, length: para.length)
                )
                result.append(para)
                numberCounter = 0
            } else {
                result.append(parseInline(line, baseAttrs: baseAttrs))
                numberCounter = 0
            }

            appendNewlineIfNotLast(into: result, idx: i, total: lines.count, attrs: baseAttrs)
            i += 1
        }
        return result
    }

    private static func appendNewlineIfNotLast(
        into result: NSMutableAttributedString,
        idx: Int,
        total: Int,
        attrs: [NSAttributedString.Key: Any]
    ) {
        if idx < total - 1 {
            result.append(NSAttributedString(string: "\n", attributes: attrs))
        }
    }

    // MARK: - Block matchers

    private static func stripLeadingEscape(_ line: String) -> String {
        guard line.hasPrefix("\\"), line.count >= 2 else { return line }
        let next = line[line.index(after: line.startIndex)]
        if "#-*+>".contains(next) { return String(line.dropFirst()) }
        // \1.  → 1.
        if next.isNumber { return String(line.dropFirst()) }
        return line
    }

    private static func matchHeading(_ line: String) -> (level: Int, text: String)? {
        let trimmed = line.drop(while: { $0 == " " })
        var hashes = 0
        for ch in trimmed {
            if ch == "#" { hashes += 1 } else { break }
        }
        guard hashes >= 1, hashes <= 6 else { return nil }
        let after = trimmed.dropFirst(hashes)
        guard after.first == " " else { return nil }
        return (hashes, String(after.dropFirst()))
    }

    private static func matchBullet(_ line: String) -> String? {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        guard let first = trimmed.first, "*-+".contains(first) else { return nil }
        let rest = trimmed.dropFirst()
        guard let space = rest.first, space == " " || space == "\t" else { return nil }
        return String(rest.dropFirst())
    }

    private static func matchNumbered(_ line: String) -> (Int, String)? {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        var digits = ""
        for ch in trimmed {
            if ch.isNumber { digits.append(ch) } else { break }
        }
        guard !digits.isEmpty, let n = Int(digits) else { return nil }
        let after = trimmed.dropFirst(digits.count)
        guard after.first == ".", after.dropFirst().first == " " else { return nil }
        return (n, String(after.dropFirst(2)))
    }

    private static func matchTodo(_ line: String) -> (Bool, String)? {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        guard let first = trimmed.first, "*-+".contains(first) else { return nil }
        let rest = trimmed.dropFirst().drop(while: { $0 == " " })
        let chars = Array(rest)
        guard chars.count >= 4, chars[0] == "[", chars[2] == "]", chars[3] == " " else { return nil }
        let inside = chars[1]
        let checked: Bool
        switch inside {
        case " ": checked = false
        case "x", "X": checked = true
        default: return nil
        }
        return (checked, String(chars.dropFirst(4)))
    }

    private static func matchQuote(_ line: String) -> String? {
        let trimmed = line.drop(while: { $0 == " " })
        guard trimmed.first == ">" else { return nil }
        let after = trimmed.dropFirst()
        if after.first == " " { return String(after.dropFirst()) }
        return String(after)
    }

    // MARK: - Tables

    private static func looksLikeTableRow(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.contains("|")
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.contains("-"), t.contains("|") else { return false }
        return t.allSatisfy { "|-: \t".contains($0) }
    }

    private static func parseTable(
        lines: [String],
        from start: Int,
        baseAttrs: [NSAttributedString.Key: Any],
        baseFont: NSFont
    ) -> (NSAttributedString, Int) {
        var rows: [[String]] = [splitRow(lines[start])]
        var consumed = 2 // header + separator
        var idx = start + 2
        while idx < lines.count, looksLikeTableRow(lines[idx]),
              !isTableSeparator(lines[idx]) {
            rows.append(splitRow(lines[idx]))
            consumed += 1
            idx += 1
        }
        let cols = rows.map(\.count).max() ?? 0
        let rowCount = rows.count

        let table = NSTextTable()
        table.numberOfColumns = cols
        table.layoutAlgorithm = .automaticLayoutAlgorithm
        table.collapsesBorders = true
        table.hidesEmptyCells = false

        let body = NSMutableAttributedString()
        for r in 0..<rowCount {
            for c in 0..<cols {
                let block = NSTextTableBlock(table: table,
                                             startingRow: r, rowSpan: 1,
                                             startingColumn: c, columnSpan: 1)
                block.setBorderColor(.separatorColor)
                block.setWidth(1, type: .absoluteValueType, for: .border)
                block.setWidth(6, type: .absoluteValueType, for: .padding)

                let style = NSMutableParagraphStyle()
                style.textBlocks = [block]

                let raw = c < rows[r].count ? rows[r][c] : ""
                let inline = parseInline(raw, baseAttrs: baseAttrs)
                let cell = NSMutableAttributedString(attributedString: inline)
                cell.append(NSAttributedString(string: "\n", attributes: baseAttrs))
                cell.addAttribute(
                    .paragraphStyle, value: style,
                    range: NSRange(location: 0, length: cell.length)
                )
                body.append(cell)
            }
        }
        // trailing exit-paragraph in default style
        body.append(NSAttributedString(string: "\n", attributes: baseAttrs))
        return (body, consumed)
    }

    private static func splitRow(_ line: String) -> [String] {
        var s = line.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") { s.removeLast() }
        // Split on "|" honoring "\|" escapes.
        var cells: [String] = []
        var cur = ""
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "\\", s.index(after: i) < s.endIndex, s[s.index(after: i)] == "|" {
                cur.append("|")
                i = s.index(i, offsetBy: 2)
                continue
            }
            if c == "|" {
                cells.append(cur.trimmingCharacters(in: .whitespaces))
                cur = ""
            } else {
                cur.append(c)
            }
            i = s.index(after: i)
        }
        cells.append(cur.trimmingCharacters(in: .whitespaces))
        return cells
    }

    // MARK: - Inline parser

    private static func parseInline(
        _ text: String,
        baseAttrs: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let chars = Array(text)
        let out = NSMutableAttributedString()
        var i = 0

        while i < chars.count {
            let c = chars[i]

            // Backslash escape: \X → literal X
            if c == "\\", i + 1 < chars.count {
                out.append(NSAttributedString(string: String(chars[i + 1]), attributes: baseAttrs))
                i += 2
                continue
            }

            // Underline: <u>...</u>
            if c == "<", i + 2 < chars.count,
               chars[i + 1] == "u", chars[i + 2] == ">",
               let close = findRun("</u>", in: chars, from: i + 3) {
                let inner = String(chars[(i + 3)..<close])
                var attrs = baseAttrs
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                out.append(parseInline(inner, baseAttrs: attrs))
                i = close + 4
                continue
            }

            // Link: [label](url)
            if c == "[",
               let bClose = findChar("]", in: chars, from: i + 1, skipEscapes: true),
               bClose + 1 < chars.count, chars[bClose + 1] == "(",
               let pClose = findChar(")", in: chars, from: bClose + 2, skipEscapes: true) {
                let label = String(chars[(i + 1)..<bClose])
                let urlStr = String(chars[(bClose + 2)..<pClose])
                if let url = URL(string: urlStr) {
                    var attrs = baseAttrs
                    attrs[.link] = url
                    attrs[.foregroundColor] = Theme.EditorColor.link
                    attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                    out.append(parseInline(label, baseAttrs: attrs))
                    i = pClose + 1
                    continue
                }
            }

            // Inline code: `code`  (also supports multi-backtick fences `` foo `` )
            if c == "`" {
                var run = 1
                while i + run < chars.count, chars[i + run] == "`" { run += 1 }
                let fence = String(repeating: "`", count: run)
                if let close = findRun(fence, in: chars, from: i + run) {
                    var inner = String(chars[(i + run)..<close])
                    // strip one space of GFM padding if present on both sides
                    if inner.hasPrefix(" "), inner.hasSuffix(" "), inner.count >= 2 {
                        inner = String(inner.dropFirst().dropLast())
                    }
                    let f = (baseAttrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
                    let mono = NSFont.monospacedSystemFont(ofSize: f.pointSize, weight: .regular)
                    var attrs = baseAttrs
                    attrs[.font] = mono
                    attrs[.foregroundColor] = Theme.EditorColor.code
                    out.append(NSAttributedString(string: inner, attributes: attrs))
                    i = close + run
                    continue
                }
            }

            // Strikethrough: ~~text~~
            if c == "~", i + 1 < chars.count, chars[i + 1] == "~",
               let close = findRun("~~", in: chars, from: i + 2) {
                let inner = String(chars[(i + 2)..<close])
                var attrs = baseAttrs
                attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                out.append(parseInline(inner, baseAttrs: attrs))
                i = close + 2
                continue
            }

            // Bold + italic: ***text*** or ___text___
            if (c == "*" || c == "_"),
               i + 2 < chars.count, chars[i + 1] == c, chars[i + 2] == c,
               let close = findRun(String(repeating: c, count: 3), in: chars, from: i + 3) {
                let inner = String(chars[(i + 3)..<close])
                let f = (baseAttrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
                var attrs = baseAttrs
                attrs[.font] = applyTraits(f, [.bold, .italic])
                out.append(parseInline(inner, baseAttrs: attrs))
                i = close + 3
                continue
            }

            // Bold: **text** or __text__
            if (c == "*" || c == "_"), i + 1 < chars.count, chars[i + 1] == c,
               let close = findRun(String(c) + String(c), in: chars, from: i + 2) {
                let inner = String(chars[(i + 2)..<close])
                let f = (baseAttrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
                var attrs = baseAttrs
                attrs[.font] = applyTraits(f, [.bold])
                out.append(parseInline(inner, baseAttrs: attrs))
                i = close + 2
                continue
            }

            // Italic: *text* or _text_
            if (c == "*" || c == "_"),
               let close = findChar(c, in: chars, from: i + 1), close > i + 1 {
                let inner = String(chars[(i + 1)..<close])
                let f = (baseAttrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
                var attrs = baseAttrs
                attrs[.font] = applyTraits(f, [.italic])
                out.append(parseInline(inner, baseAttrs: attrs))
                i = close + 1
                continue
            }

            out.append(NSAttributedString(string: String(c), attributes: baseAttrs))
            i += 1
        }

        return out
    }

    private static func applyTraits(
        _ font: NSFont,
        _ added: NSFontDescriptor.SymbolicTraits
    ) -> NSFont {
        var traits = font.fontDescriptor.symbolicTraits
        traits.formUnion(added)
        let desc = font.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: desc, size: font.pointSize) ?? font
    }

    private static func findChar(
        _ ch: Character,
        in chars: [Character],
        from start: Int,
        skipEscapes: Bool = false
    ) -> Int? {
        var i = start
        while i < chars.count {
            if skipEscapes, chars[i] == "\\", i + 1 < chars.count {
                i += 2; continue
            }
            if chars[i] == ch { return i }
            i += 1
        }
        return nil
    }

    private static func findRun(_ marker: String, in chars: [Character], from start: Int) -> Int? {
        let m = Array(marker)
        guard !m.isEmpty else { return nil }
        var i = start
        while i + m.count <= chars.count {
            var ok = true
            for j in 0..<m.count where chars[i + j] != m[j] { ok = false; break }
            if ok { return i }
            i += 1
        }
        return nil
    }
}

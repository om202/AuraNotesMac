//
//  MarkdownSerializer.swift
//  AuraNotes
//
//  Inverse of MarkdownConverter: turns the editor's NSAttributedString into
//  Markdown so OURS → MD → OURS round-trips with no formatting loss for the
//  features the editor actually exposes.
//

import AppKit

enum MarkdownSerializer {

    static func serialize(_ attr: NSAttributedString) -> String {
        let nsString = attr.string as NSString
        var out = ""
        var i = 0

        while i < nsString.length {
            // Table block? Consume the whole table at once.
            if let (md, end) = consumeTable(in: attr, startingAtParagraph: i) {
                out.append(md)
                i = end
                continue
            }

            let pr = nsString.paragraphRange(for: NSRange(location: i, length: 0))
            let para = attr.attributedSubstring(from: pr)
            out.append(serializeParagraph(para))
            i = pr.location + pr.length
            if pr.length == 0 { break }
        }
        return out
    }

    // MARK: - Paragraph

    private static func serializeParagraph(_ paragraph: NSAttributedString) -> String {
        let body = NSMutableAttributedString(attributedString: paragraph)
        let hadTerminator = body.string.hasSuffix("\n")
        if hadTerminator {
            body.deleteCharacters(in: NSRange(location: body.length - 1, length: 1))
        }

        var prefix = ""

        // Quote prefix "▎ "
        if body.string.hasPrefix("▎ ") {
            prefix += "> "
            body.deleteCharacters(in: NSRange(location: 0, length: 2))
        }

        // List prefixes
        if let listPrefixLen = matchListPrefix(body.string) {
            let head = (body.string as NSString).substring(to: listPrefixLen.length)
            body.deleteCharacters(in: NSRange(location: 0, length: listPrefixLen.length))
            prefix += listPrefixLen.toMarkdown(head)
        }

        // Heading (font size at first character)
        var baseline = InlineStyle()
        if body.length > 0,
           let f = body.attributes(at: 0, effectiveRange: nil)[.font] as? NSFont {
            let size = f.pointSize
            if size >= (Theme.FontSize.title + Theme.FontSize.heading) / 2 {
                prefix = "# " + prefix
                baseline.bold = true
            } else if size >= (Theme.FontSize.heading + Theme.FontSize.subheading) / 2 {
                prefix = "## " + prefix
                baseline.bold = true
            } else if size >= (Theme.FontSize.subheading + Theme.FontSize.body) / 2 {
                prefix = "### " + prefix
                baseline.bold = true   // subheading uses semibold; treat as baseline
            }
        }

        let inline = serializeInline(body, baseline: baseline)
        let escapedInline = escapeBlockStart(inline, hasPrefix: !prefix.isEmpty)
        return prefix + escapedInline + (hadTerminator ? "\n" : "")
    }

    // MARK: - List prefix detection

    private enum ListPrefix {
        case bullet(length: Int)
        case todoUnchecked(length: Int)
        case todoChecked(length: Int)
        case numbered(value: Int, length: Int)

        var length: Int {
            switch self {
            case .bullet(let l), .todoUnchecked(let l), .todoChecked(let l): return l
            case .numbered(_, let l): return l
            }
        }

        func toMarkdown(_ head: String) -> String {
            switch self {
            case .bullet:        return "- "
            case .todoUnchecked: return "- [ ] "
            case .todoChecked:   return "- [x] "
            case .numbered(let n, _): return "\(n). "
            }
        }
    }

    private static func matchListPrefix(_ s: String) -> ListPrefix? {
        let ns = s as NSString
        let len = ns.length
        guard len > 0 else { return nil }

        // Bullet: any of the level glyphs (●, ○, ▪) followed by tab.
        for glyph in ["●", "○", "▪"] {
            if ns.hasPrefix("\(glyph) \t") { return .bullet(length: 3) }
            if ns.hasPrefix("\(glyph)\t")  { return .bullet(length: 2) }
        }

        // Todo: "☐\t" / "☑\t"
        if ns.hasPrefix("☐\t") { return .todoUnchecked(length: 2) }
        if ns.hasPrefix("☑\t") { return .todoChecked(length: 2) }

        // Numbered: ^\d+\.\t
        var idx = 0
        while idx < len {
            let c = ns.character(at: idx)
            if c >= 0x30 && c <= 0x39 { idx += 1 } else { break }
        }
        if idx > 0, idx + 1 < len,
           ns.character(at: idx) == 0x2E, // '.'
           ns.character(at: idx + 1) == 0x09 { // '\t'
            let digits = ns.substring(with: NSRange(location: 0, length: idx))
            if let n = Int(digits) { return .numbered(value: n, length: idx + 2) }
        }
        return nil
    }

    // MARK: - Inline

    private struct InlineStyle: Equatable {
        var bold: Bool = false
        var italic: Bool = false
        var strike: Bool = false
        var underline: Bool = false
        var code: Bool = false
        var link: URL? = nil
    }

    private static func style(at index: Int, in attr: NSAttributedString) -> InlineStyle {
        let attrs = attr.attributes(at: index, effectiveRange: nil)
        var s = InlineStyle()
        if let f = attrs[.font] as? NSFont {
            let traits = f.fontDescriptor.symbolicTraits
            s.bold = traits.contains(.bold)
            s.italic = traits.contains(.italic)
            s.code = f.isFixedPitch
        }
        if let v = attrs[.strikethroughStyle] as? Int, v != 0 { s.strike = true }
        if let v = attrs[.underlineStyle] as? Int, v != 0 { s.underline = true }
        if let url = attrs[.link] as? URL { s.link = url }
        else if let str = attrs[.link] as? String, let url = URL(string: str) { s.link = url }
        return s
    }

    private static func serializeInline(
        _ attr: NSAttributedString,
        baseline: InlineStyle
    ) -> String {
        guard attr.length > 0 else { return "" }
        let nsString = attr.string as NSString

        // Build [(NSRange, InlineStyle)] spans
        var spans: [(NSRange, InlineStyle)] = []
        var spanStart = 0
        var current = style(at: 0, in: attr)
        for i in 1..<attr.length {
            let s = style(at: i, in: attr)
            if s != current {
                spans.append((NSRange(location: spanStart, length: i - spanStart), current))
                spanStart = i
                current = s
            }
        }
        spans.append((NSRange(location: spanStart, length: attr.length - spanStart), current))

        var out = ""
        for (range, s) in spans {
            let text = nsString.substring(with: range)
            out.append(emitSpan(text, style: s, baseline: baseline))
        }
        return out
    }

    private static func emitSpan(
        _ text: String,
        style s: InlineStyle,
        baseline: InlineStyle
    ) -> String {
        // Code is opaque; render it standalone (drop other markers — not standard MD).
        if s.code {
            // Choose a fence of n backticks where n is 1 more than the longest backtick run inside.
            let longest = longestBacktickRun(in: text)
            let fence = String(repeating: "`", count: longest + 1)
            // GFM requires a space if the content starts/ends with a backtick.
            let pad = (text.hasPrefix("`") || text.hasSuffix("`")) ? " " : ""
            var s2 = fence + pad + text + pad + fence
            if let url = s.link { s2 = "[" + s2 + "](" + url.absoluteString + ")" }
            return s2
        }

        let bold = s.bold && !baseline.bold
        let italic = s.italic && !baseline.italic
        var prefix = ""
        var suffix = ""
        if let _ = s.link { prefix += "["; suffix = "](" + (s.link!.absoluteString) + ")" + suffix }
        if s.underline { prefix += "<u>"; suffix = "</u>" + suffix }
        if s.strike    { prefix += "~~";  suffix = "~~"    + suffix }
        if bold && italic { prefix += "***"; suffix = "***" + suffix }
        else if bold      { prefix += "**";  suffix = "**"  + suffix }
        else if italic    { prefix += "*";   suffix = "*"   + suffix }

        return prefix + escapeInline(text) + suffix
    }

    private static func longestBacktickRun(in text: String) -> Int {
        var best = 0, run = 0
        for ch in text {
            if ch == "`" { run += 1; if run > best { best = run } } else { run = 0 }
        }
        return best
    }

    // MARK: - Escaping

    /// Escape characters that would otherwise be parsed as inline markdown.
    private static func escapeInline(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for ch in text {
            switch ch {
            case "\\", "*", "_", "`", "~", "[", "]", "<":
                out.append("\\"); out.append(ch)
            default:
                out.append(ch)
            }
        }
        return out
    }

    /// If a paragraph has no markdown prefix and its body begins with a
    /// character that would itself start a block, escape that first char
    /// so the round trip preserves the plain paragraph.
    private static func escapeBlockStart(_ s: String, hasPrefix: Bool) -> String {
        guard !hasPrefix, let first = s.first else { return s }
        if first == "#" || first == ">" {
            return "\\" + s
        }
        // "- ", "* ", "+ "
        if (first == "-" || first == "*" || first == "+"),
           s.count >= 2, s[s.index(after: s.startIndex)] == " " {
            return "\\" + s
        }
        // "\d+\. "
        var idx = s.startIndex
        while idx < s.endIndex, s[idx].isNumber { idx = s.index(after: idx) }
        if idx > s.startIndex, idx < s.endIndex, s[idx] == ".",
           s.index(after: idx) < s.endIndex, s[s.index(after: idx)] == " " {
            return "\\" + s
        }
        return s
    }

    // MARK: - Tables

    /// If the paragraph at `paraStart` belongs to an NSTextTable, serialize the
    /// whole table to GFM and return the markdown plus the index just past the
    /// last paragraph consumed.
    private static func consumeTable(
        in attr: NSAttributedString,
        startingAtParagraph paraStart: Int
    ) -> (String, Int)? {
        let nsString = attr.string as NSString
        guard paraStart < nsString.length else { return nil }
        let firstPR = nsString.paragraphRange(for: NSRange(location: paraStart, length: 0))
        guard let firstTable = tableID(forParagraphAt: firstPR.location, in: attr) else {
            return nil
        }

        // Walk forward across paragraphs that share the same NSTextTable.
        var cells: [(row: Int, col: Int, text: NSAttributedString)] = []
        var maxRow = 0
        var maxCol = 0
        var cursor = firstPR.location
        while cursor < nsString.length {
            let pr = nsString.paragraphRange(for: NSRange(location: cursor, length: 0))
            guard let info = cellInfo(forParagraphAt: pr.location, in: attr),
                  info.table === firstTable else {
                break
            }
            let cellText = attr.attributedSubstring(from: pr)
            // strip trailing "\n" inside the cell representation
            let cleaned: NSAttributedString = {
                if cellText.string.hasSuffix("\n") {
                    let m = NSMutableAttributedString(attributedString: cellText)
                    m.deleteCharacters(in: NSRange(location: m.length - 1, length: 1))
                    return m
                }
                return cellText
            }()
            cells.append((info.row, info.col, cleaned))
            maxRow = max(maxRow, info.row)
            maxCol = max(maxCol, info.col)
            cursor = pr.location + pr.length
            if pr.length == 0 { break }
        }
        guard !cells.isEmpty else { return nil }

        // Build a (row × col) grid of cell text.
        let cols = maxCol + 1
        let rows = maxRow + 1
        var grid: [[String]] = Array(
            repeating: Array(repeating: "", count: cols),
            count: rows
        )
        for c in cells {
            let inline = serializeInline(c.text, baseline: InlineStyle())
                .trimmingCharacters(in: .whitespaces)
            grid[c.row][c.col] = inline.replacingOccurrences(of: "|", with: "\\|")
        }

        var md = ""
        for (r, row) in grid.enumerated() {
            md += "| " + row.joined(separator: " | ") + " |\n"
            if r == 0 {
                md += "|" + Array(repeating: "---", count: cols).joined(separator: "|") + "|\n"
            }
        }
        return (md, cursor)
    }

    private static func tableID(forParagraphAt loc: Int, in attr: NSAttributedString) -> NSTextTable? {
        cellInfo(forParagraphAt: loc, in: attr)?.table
    }

    private static func cellInfo(
        forParagraphAt loc: Int,
        in attr: NSAttributedString
    ) -> (table: NSTextTable, row: Int, col: Int)? {
        guard loc < attr.length else { return nil }
        let attrs = attr.attributes(at: loc, effectiveRange: nil)
        guard let style = attrs[.paragraphStyle] as? NSParagraphStyle else { return nil }
        for block in style.textBlocks {
            if let tb = block as? NSTextTableBlock {
                return (tb.table, tb.startingRow, tb.startingColumn)
            }
        }
        return nil
    }
}

//
//  MarkdownCommand.swift
//  SmartJournalApp
//

import AppKit

enum MarkdownCommand {
    static func toggleWrap(_ tv: NSTextView, marker: String) {
        guard let range = tv.selectedRanges.first?.rangeValue else { return }
        let nsString = tv.string as NSString
        let mlen = (marker as NSString).length

        let selected = nsString.substring(with: range)
        let selectedNS = selected as NSString

        // Already wrapped inside selection?
        if selectedNS.length >= 2 * mlen,
           selectedNS.hasPrefix(marker),
           selectedNS.hasSuffix(marker) {
            let inner = selectedNS.substring(with: NSRange(location: mlen, length: selectedNS.length - 2 * mlen))
            replace(tv, range: range, with: inner,
                    newSelection: NSRange(location: range.location, length: (inner as NSString).length))
            return
        }

        // Wrappers immediately surrounding selection?
        let canCheckBefore = range.location >= mlen
        let canCheckAfter = range.location + range.length + mlen <= nsString.length
        if canCheckBefore, canCheckAfter {
            let before = nsString.substring(with: NSRange(location: range.location - mlen, length: mlen))
            let after = nsString.substring(with: NSRange(location: range.location + range.length, length: mlen))
            if before == marker, after == marker {
                let extended = NSRange(location: range.location - mlen, length: range.length + 2 * mlen)
                replace(tv, range: extended, with: selected,
                        newSelection: NSRange(location: extended.location, length: (selected as NSString).length))
                return
            }
        }

        // Wrap
        let wrapped = "\(marker)\(selected)\(marker)"
        let innerLocation = range.location + mlen
        replace(tv, range: range, with: wrapped,
                newSelection: NSRange(location: innerLocation, length: (selected as NSString).length))
    }

    static func insertLink(_ tv: NSTextView) {
        guard let range = tv.selectedRanges.first?.rangeValue else { return }
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
        let url = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }

        let display = selected.isEmpty ? "link" : selected
        let replacement = "[\(display)](\(url))"
        let displayLen = (display as NSString).length
        let cursor = NSRange(location: range.location + 1, length: displayLen)
        replace(tv, range: range, with: replacement, newSelection: cursor)
    }

    @discardableResult
    static func continueListIfNeeded(_ tv: NSTextView) -> Bool {
        let selection = tv.selectedRange()
        let nsString = tv.string as NSString
        let lineRange = nsString.lineRange(for: NSRange(location: selection.location, length: 0))
        var line = nsString.substring(with: lineRange)
        // Strip trailing newline for matching
        if line.hasSuffix("\n") { line = String(line.dropLast()) }
        let lineNS = line as NSString
        let lineFull = NSRange(location: 0, length: lineNS.length)

        let pattern = "^([ \\t]*)(([-*+])|(\\d+)\\.)(\\s+)(.*)$"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: line, range: lineFull) else {
            return false
        }

        let indent = lineNS.substring(with: m.range(at: 1))
        let trailingSpace = lineNS.substring(with: m.range(at: 5))
        let content = lineNS.substring(with: m.range(at: 6))

        // Empty list item: end the list by clearing the current line and inserting newline
        if content.isEmpty {
            let absLine = NSRange(location: lineRange.location, length: lineNS.length)
            replace(tv, range: absLine, with: "",
                    newSelection: NSRange(location: lineRange.location, length: 0))
            return true
        }

        let nextMarker: String
        if m.range(at: 4).location != NSNotFound {
            let n = Int(lineNS.substring(with: m.range(at: 4))) ?? 1
            nextMarker = "\(n + 1)."
        } else {
            nextMarker = lineNS.substring(with: m.range(at: 3))
        }

        let insertion = "\n\(indent)\(nextMarker)\(trailingSpace)"
        let insertionLen = (insertion as NSString).length
        let cursor = NSRange(location: selection.location + insertionLen, length: 0)
        replace(tv, range: selection, with: insertion, newSelection: cursor)
        return true
    }

    private static func replace(_ tv: NSTextView,
                                range: NSRange,
                                with replacement: String,
                                newSelection: NSRange?) {
        guard tv.shouldChangeText(in: range, replacementString: replacement) else { return }
        tv.textStorage?.replaceCharacters(in: range, with: replacement)
        tv.didChangeText()
        if let sel = newSelection {
            tv.setSelectedRange(sel)
        }
    }
}

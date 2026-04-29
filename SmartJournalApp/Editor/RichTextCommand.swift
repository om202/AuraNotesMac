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
            case 1: return (28, .bold)
            case 2: return (22, .bold)
            case 3: return (18, .semibold)
            default: return (NSFont.systemFontSize, .regular)
            }
        }()
        let newFont = NSFont.systemFont(ofSize: size, weight: weight)

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
        applyList(tv, marker: NSTextList(markerFormat: .disc, options: 0))
    }

    static func toggleNumberedList(_ tv: NSTextView) {
        applyList(tv, marker: NSTextList(markerFormat: .decimal, options: 0))
    }

    private static func applyList(_ tv: NSTextView, marker: NSTextList) {
        let nsString = tv.string as NSString
        let paraRange = nsString.paragraphRange(for: tv.selectedRange)
        guard tv.shouldChangeText(in: paraRange, replacementString: nil) else { return }

        let storage = tv.textStorage!
        storage.beginEditing()

        // Detect: are all paragraphs already in this kind of list? If so, strip.
        var allHaveSameList = true
        storage.enumerateAttribute(.paragraphStyle, in: paraRange, options: []) { value, _, stop in
            let style = value as? NSParagraphStyle
            let lists = style?.textLists ?? []
            if lists.last?.markerFormat != marker.markerFormat {
                allHaveSameList = false
                stop.pointee = true
            }
        }

        let newStyle = NSMutableParagraphStyle()
        if !allHaveSameList {
            newStyle.textLists = [marker]
            newStyle.firstLineHeadIndent = 0
            newStyle.headIndent = 24
        }
        storage.addAttribute(.paragraphStyle, value: newStyle, range: paraRange)
        storage.endEditing()
        tv.didChangeText()
    }

    // MARK: Quote

    static func toggleQuote(_ tv: NSTextView) {
        let nsString = tv.string as NSString
        let paraRange = nsString.paragraphRange(for: tv.selectedRange)
        guard tv.shouldChangeText(in: paraRange, replacementString: nil) else { return }

        let storage = tv.textStorage!
        storage.beginEditing()

        // Detect if current paragraph is already quoted (we mark it via headIndent + italic).
        var allItalic = true
        storage.enumerateAttribute(.font, in: paraRange, options: []) { value, _, stop in
            let f = (value as? NSFont) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            if !f.fontDescriptor.symbolicTraits.contains(.italic) {
                allItalic = false; stop.pointee = true
            }
        }

        if allItalic {
            // Strip italic + reset paragraph style to default
            storage.enumerateAttribute(.font, in: paraRange, options: []) { value, sub, _ in
                let f = (value as? NSFont) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
                var traits = f.fontDescriptor.symbolicTraits
                traits.remove(.italic)
                let desc = f.fontDescriptor.withSymbolicTraits(traits)
                let newFont = NSFont(descriptor: desc, size: f.pointSize) ?? f
                storage.addAttribute(.font, value: newFont, range: sub)
            }
            storage.addAttribute(.paragraphStyle, value: NSParagraphStyle.default, range: paraRange)
            storage.removeAttribute(.foregroundColor, range: paraRange)
            storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: paraRange)
        } else {
            storage.enumerateAttribute(.font, in: paraRange, options: []) { value, sub, _ in
                let f = (value as? NSFont) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
                var traits = f.fontDescriptor.symbolicTraits
                traits.insert(.italic)
                let desc = f.fontDescriptor.withSymbolicTraits(traits)
                let newFont = NSFont(descriptor: desc, size: f.pointSize) ?? f
                storage.addAttribute(.font, value: newFont, range: sub)
            }
            let style = NSMutableParagraphStyle()
            style.firstLineHeadIndent = 16
            style.headIndent = 16
            storage.addAttribute(.paragraphStyle, value: style, range: paraRange)
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: paraRange)
        }

        storage.endEditing()
        tv.didChangeText()
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

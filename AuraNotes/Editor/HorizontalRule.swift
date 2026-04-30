//
//  HorizontalRule.swift
//  AuraNotes
//
//  Horizontal-rule support implemented as a "collapsed table": a 1×1
//  `NSTextTable` whose only visible edge is a 1pt top border. The native
//  AppKit table-rendering path paints the border the same way it paints
//  normal grid lines, so the rule is robust across TextKit 1 and TextKit 2
//  layout passes (no view-recycling, no attachment-image lifecycle issues).
//
//  This piggybacks on the standard RTF table encoding for free
//  persistence — the same mechanism that already round-trips real tables.
//

import AppKit

enum HorizontalRule {

    /// Build a horizontal-rule payload: a 1×1 table-block paragraph plus a
    /// trailing exit paragraph in default style so the cursor lands cleanly
    /// outside the table on the next line.
    static func payload(
        baseAttrs: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let table = NSTextTable()
        table.numberOfColumns = 1
        table.layoutAlgorithm = .automaticLayoutAlgorithm
        table.collapsesBorders = true
        table.hidesEmptyCells = false

        let block = NSTextTableBlock(
            table: table,
            startingRow: 0, rowSpan: 1,
            startingColumn: 0, columnSpan: 1
        )
        // Bottom border only — the line sits at the bottom of the cell, so
        // the cell's body-line-height of empty content reads as breathing
        // room ABOVE the line. (Top-border previously gave the inverse:
        // line snug under the prior paragraph, big gap below.)
        block.setWidth(0, type: .absoluteValueType, for: .border, edge: .minY)
        block.setWidth(1, type: .absoluteValueType, for: .border, edge: .maxY)
        block.setWidth(0, type: .absoluteValueType, for: .border, edge: .minX)
        block.setWidth(0, type: .absoluteValueType, for: .border, edge: .maxX)
        block.setWidth(0, type: .absoluteValueType, for: .padding)
        block.setBorderColor(
            Theme.EditorColor.body.withAlphaComponent(0.35),
            for: .maxY
        )

        let style = NSMutableParagraphStyle()
        style.textBlocks = [block]

        // Treat the rule as a special block with symmetric, modest
        // breathing room on both sides. Cell content sits above the bottom
        // border (gap above the line); exit paragraph sits below (gap
        // below). Both use the same small font so the gaps match.
        let smallFont: NSFont = {
            guard let f = baseAttrs[.font] as? NSFont else {
                return NSFont.systemFont(ofSize: 6)
            }
            return NSFont(
                descriptor: f.fontDescriptor,
                size: max(4, f.pointSize * 0.4)
            ) ?? f
        }()

        var cellAttrs = baseAttrs
        cellAttrs[.paragraphStyle] = style
        cellAttrs[.font] = smallFont

        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: "\n", attributes: cellAttrs))

        // Exit paragraph in default style — required so the cursor lands
        // outside the table and doesn't inherit the cell's block style on
        // subsequent typing. Same small font as the cell so the gap below
        // the line mirrors the gap above. Typed text picks up body font
        // from `typingAttributes` (set after insert), so the new paragraph
        // grows naturally as the user types.
        var trailingAttrs = baseAttrs
        trailingAttrs[.paragraphStyle] = NSParagraphStyle.default
        trailingAttrs[.font] = smallFont
        result.append(NSAttributedString(string: "\n", attributes: trailingAttrs))

        return result
    }

    /// Refresh the bottom-border color on every HR table block in `s`.
    /// RTF flattens dynamic NSColors to fixed RGB at save time, so after
    /// reloading from disk in a different appearance the rule color is
    /// stuck on whatever it was when the user last saved. Mutating the
    /// block in place restores the dynamic color (NSTextBlock is a
    /// reference type, so the change reaches the active text storage).
    static func rehydrateBorderColors(in s: NSMutableAttributedString) {
        let full = NSRange(location: 0, length: s.length)
        guard full.length > 0 else { return }
        let dynamicColor = Theme.EditorColor.body.withAlphaComponent(0.35)

        s.enumerateAttribute(.paragraphStyle, in: full, options: []) { value, _, _ in
            guard let style = value as? NSParagraphStyle else { return }
            for raw in style.textBlocks {
                guard let block = raw as? NSTextTableBlock else { continue }
                let table = block.table
                guard table.numberOfColumns == 1,
                      block.rowSpan == 1, block.columnSpan == 1,
                      block.startingRow == 0, block.startingColumn == 0
                else { continue }
                let top    = block.width(for: .border, edge: .minY)
                let bottom = block.width(for: .border, edge: .maxY)
                let left   = block.width(for: .border, edge: .minX)
                let right  = block.width(for: .border, edge: .maxX)
                if bottom > 0, top == 0, left == 0, right == 0 {
                    block.setBorderColor(dynamicColor, for: .maxY)
                }
            }
        }
    }

    /// Returns true when `paragraph` is exactly our horizontal-rule cell:
    /// belongs to a 1×1 `NSTextTable` and only the top edge has a border.
    static func isHorizontalRule(_ paragraph: NSAttributedString) -> Bool {
        guard paragraph.length > 0 else { return false }
        let attrs = paragraph.attributes(at: 0, effectiveRange: nil)
        guard let style = attrs[.paragraphStyle] as? NSParagraphStyle else {
            return false
        }
        for raw in style.textBlocks {
            guard let block = raw as? NSTextTableBlock else { continue }
            let table = block.table
            guard table.numberOfColumns == 1,
                  block.rowSpan == 1, block.columnSpan == 1,
                  block.startingRow == 0, block.startingColumn == 0
            else { continue }

            let top    = block.width(for: .border, edge: .minY)
            let bottom = block.width(for: .border, edge: .maxY)
            let left   = block.width(for: .border, edge: .minX)
            let right  = block.width(for: .border, edge: .maxX)
            if top > 0, bottom == 0, left == 0, right == 0 {
                return true
            }
        }
        return false
    }
}

extension RichTextCommand {

    static func insertHorizontalRule(_ tv: NSTextView) {
        guard let storage = tv.textStorage else { return }
        let baseAttrs = tv.typingAttributes
        let range = tv.selectedRange

        // Force the rule onto its own paragraph: prepend a newline if the
        // cursor is mid-paragraph. Otherwise the rule's table-block style
        // would attach to the current paragraph's content.
        var leading: NSAttributedString?
        if range.location > 0,
           (storage.string as NSString).character(at: range.location - 1) != 0x0A {
            leading = NSAttributedString(string: "\n", attributes: baseAttrs)
        }

        let payload = NSMutableAttributedString()
        if let leading { payload.append(leading) }
        payload.append(HorizontalRule.payload(baseAttrs: baseAttrs))

        guard tv.shouldChangeText(in: range, replacementString: payload.string) else {
            return
        }
        storage.replaceCharacters(in: range, with: payload)
        tv.didChangeText()

        let end = range.location + payload.length
        tv.setSelectedRange(NSRange(location: end, length: 0))

        // Reset typing attributes to default body so subsequent typing
        // doesn't inherit the rule cell's tiny font / table-block style.
        var resetTyping = baseAttrs
        resetTyping[.paragraphStyle] = NSParagraphStyle.default
        tv.typingAttributes = resetTyping
    }

    /// Used by the Markdown serializer.
    static func isHorizontalRule(paragraph: NSAttributedString) -> Bool {
        HorizontalRule.isHorizontalRule(paragraph)
    }
}

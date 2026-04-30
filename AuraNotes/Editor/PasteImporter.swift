//
//  PasteImporter.swift
//  AuraNotes
//
//  Smart paste pipeline. Inspects the pasteboard, picks the richest
//  representation it understands, and normalizes it to the editor's
//  font/color world before insertion.
//

import AppKit

enum PasteImporter {

    /// Result of choosing what to insert from the pasteboard.
    enum Outcome {
        case attributed(NSAttributedString)
        case plain(String)
        case nothing
    }

    /// Decide what to paste from `pb` given the editor's current typing
    /// attributes. Caller is responsible for the actual insertion.
    static func resolve(
        from pb: NSPasteboard,
        baseAttrs: [NSAttributedString.Key: Any]
    ) -> Outcome {
        // 1. Rich attributed sources first — RTFD, then RTF, then HTML.
        if let data = pb.data(forType: .rtfd),
           let attr = NSAttributedString(rtfd: data, documentAttributes: nil) {
            return .attributed(AttributedNormalizer.normalize(attr, baseAttrs: baseAttrs))
        }
        if let data = pb.data(forType: .rtf),
           let attr = NSAttributedString(rtf: data, documentAttributes: nil) {
            return .attributed(AttributedNormalizer.normalize(attr, baseAttrs: baseAttrs))
        }
        if let data = pb.data(forType: .html),
           let attr = NSAttributedString(
            html: data,
            options: [.characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil) {
            return .attributed(AttributedNormalizer.normalize(attr, baseAttrs: baseAttrs))
        }

        // 2. Plain text — sniff for Markdown. Parse only if it looks like one.
        if let s = pb.string(forType: .string) {
            if MarkdownSniff.looksLikeMarkdown(s) {
                return .attributed(MarkdownConverter.convert(s, baseAttrs: baseAttrs))
            }
            return .plain(s)
        }

        return .nothing
    }
}

// MARK: - Markdown detection

enum MarkdownSniff {
    /// Conservative regex pass. Returns `true` only if at least one
    /// signal that's quite unlikely to appear in arbitrary plain text
    /// is found.
    static func looksLikeMarkdown(_ s: String) -> Bool {
        // Cheap pre-filter: must contain at least one suggestive char.
        let bag: Set<Character> = ["#", "*", "_", "`", "-", ">", "[", "~"]
        guard s.contains(where: { bag.contains($0) }) else { return false }

        let patterns: [String] = [
            #"(?m)^\s{0,3}#{1,6}\s\S"#,            // ATX heading
            #"(?m)^\s{0,3}[-*+]\s\S"#,             // bullet
            #"(?m)^\s{0,3}\d+\.\s\S"#,             // numbered
            #"(?m)^\s{0,3}>\s"#,                   // blockquote
            #"(?m)^\s{0,3}```"#,                   // fence
            #"(?m)^\s{0,3}[-*+]\s\[[ xX]\]\s"#,    // todo
            #"\*\*[^*\n]{1,200}\*\*"#,             // bold
            #"(?<!\*)\*[^*\s][^*\n]{0,200}[^*\s]\*(?!\*)"#, // italic — paired *…*
            #"~~[^~\n]{1,200}~~"#,                 // strike
            #"`[^`\n]{1,200}`"#,                   // inline code
            #"\[[^\]\n]{1,200}\]\([^)\n]{1,500}\)"# // link
        ]
        for p in patterns {
            if s.range(of: p, options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }
}

// MARK: - Attributed string normalization

enum AttributedNormalizer {

    /// Re-maps an imported attributed string to the editor's typography:
    /// every font run becomes a member of the editor's chosen family at a
    /// recognized editor size; foreign foreground/background colors are
    /// stripped (links keep their `.link`, the visual color is supplied
    /// by `linkTextAttributes`); list/quote-like paragraph styles are
    /// flattened (we don't yet trust foreign indents).
    static func normalize(
        _ source: NSAttributedString,
        baseAttrs: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        guard source.length > 0 else { return source }

        let result = NSMutableAttributedString(attributedString: source)
        let full = NSRange(location: 0, length: result.length)

        // Drop attachments (TextKit 2 + foreign attachments are fragile;
        // we'd lose the binary data on re-serialize anyway).
        result.removeAttribute(.attachment, range: full)

        // Foreground: strip foreign colors; let the editor own the palette.
        // Links keep their `.link` and pick up color via linkTextAttributes.
        result.removeAttribute(.foregroundColor, range: full)
        result.removeAttribute(.backgroundColor, range: full)
        result.addAttribute(.foregroundColor, value: Theme.EditorColor.body, range: full)

        // Paragraph styles: flatten everything to default. We don't import
        // foreign list/quote indents — those would clash with our marker
        // glyphs and hanging-indent system.
        result.removeAttribute(.paragraphStyle, range: full)

        // Re-map every font run.
        let family = EditorFont.currentFamily
        result.enumerateAttribute(.font, in: full, options: []) { value, range, _ in
            let original = (value as? NSFont)
                ?? NSFont.systemFont(ofSize: Theme.FontSize.body)
            let mapped = mapFont(original, family: family)
            result.addAttribute(.font, value: mapped, range: range)
        }

        // If the source had no .font runs at all, addAttribute over `full`
        // ensures the result still types correctly. Belt and braces:
        if result.attribute(.font, at: 0, effectiveRange: nil) == nil {
            let body = (baseAttrs[.font] as? NSFont)
                ?? family.font(size: Theme.FontSize.body)
            result.addAttribute(.font, value: body, range: full)
        }

        // Re-color link runs with the body color (linkTextAttributes will
        // re-color them at draw time; this keeps storage neutral).
        result.enumerateAttribute(.link, in: full, options: []) { value, range, _ in
            guard value != nil else { return }
            result.addAttribute(.foregroundColor, value: Theme.EditorColor.body, range: range)
        }

        return result
    }

    /// Map an imported font to the editor's family at a recognized size.
    /// Symbolic traits (bold/italic/monospace) are preserved.
    private static func mapFont(_ source: NSFont, family: EditorFontFamily) -> NSFont {
        let traits = source.fontDescriptor.symbolicTraits
        let size = mappedSize(from: source.pointSize)
        let weight = source.editorWeight

        if traits.contains(.monoSpace) {
            return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        }

        var descriptor = NSFontDescriptor()
            .withFamily(family.familyName)
            .addingAttributes([
                .traits: [NSFontDescriptor.TraitKey.weight: weight.rawValue]
            ])
        let preserved = traits.intersection([.bold, .italic])
        if !preserved.isEmpty {
            descriptor = descriptor.withSymbolicTraits(preserved)
        }
        return NSFont(descriptor: descriptor, size: size)
            ?? family.font(size: size, weight: weight, italic: traits.contains(.italic))
    }

    /// Bucket the source size into one of the editor's design sizes so
    /// pasted content visually matches surrounding text.
    private static func mappedSize(from sourceSize: CGFloat) -> CGFloat {
        switch sourceSize {
        case ..<20:           return Theme.FontSize.body
        case 20..<24:         return Theme.FontSize.subheading
        case 24..<30:         return Theme.FontSize.heading
        default:              return Theme.FontSize.title
        }
    }
}

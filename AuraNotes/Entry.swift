//
//  Entry.swift
//  AuraNotes
//

import Foundation
import SwiftData

@Model
final class Entry {
    /// Plain-text mirror of the entry's content. Used for sidebar previews and (eventually) search.
    var text: String
    /// Rich-text body, archived as RTF. nil for entries created before rich text existed — fall back to `text`.
    var bodyData: Data?
    var createdAt: Date
    var updatedAt: Date

    init(text: String = "", createdAt: Date = .now) {
        self.text = text
        self.bodyData = nil
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    var previewTitle: String {
        // The sidebar only shows ~one line, so walking the whole body on
        // every keystroke is wasted work. Cap the scan at the first chunk;
        // the first non-empty cleaned line will almost always live here.
        let head = text.prefix(500)
        for raw in head.split(whereSeparator: \.isNewline) {
            let cleaned = Self.stripDecorations(String(raw))
            if !cleaned.isEmpty { return cleaned }
        }
        return "New entry"
    }

    /// Removes list markers (●, ☐, ☑), numbered-list prefixes ("1."), quote bars,
    /// and other symbol/format glyphs that appear in the rich-text mirror, so
    /// the sidebar title shows the actual sentence the user wrote.
    private static func stripDecorations(_ line: String) -> String {
        var s = line.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip a leading numbered-list prefix like "1." or "12. ".
        if let match = s.range(of: #"^\d+\.[ \t]+"#, options: .regularExpression) {
            s.removeSubrange(match)
        }

        // Drop characters that aren't letters/numbers/whitespace/standard punctuation.
        // Keeps smart quotes, em-dashes, etc.; removes ●, ☐, ☑, ▢, decorative symbols.
        let kept = s.unicodeScalars.filter { scalar in
            if scalar.properties.isEmoji { return false }
            switch scalar.properties.generalCategory {
            case .otherSymbol, .modifierSymbol, .format, .control,
                 .surrogate, .privateUse, .unassigned:
                return false
            default:
                return true
            }
        }
        return String(String.UnicodeScalarView(kept))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

//
//  Entry.swift
//  SmartJournalApp
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
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "New entry" : trimmed
    }
}

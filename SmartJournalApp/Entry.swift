//
//  Entry.swift
//  SmartJournalApp
//

import Foundation
import SwiftData

@Model
final class Entry {
    var text: String
    var createdAt: Date
    var updatedAt: Date

    init(text: String = "", createdAt: Date = .now) {
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    var previewTitle: String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "New entry" : trimmed
    }
}

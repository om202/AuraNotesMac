//
//  ContentView.swift
//  SmartJournalApp
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Entry.createdAt, order: .reverse) private var entries: [Entry]

    @State private var selectedEntry: Entry?
    @State private var pendingDeletion: Entry?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .confirmationDialog(
            "Delete this entry?",
            isPresented: deletionBinding,
            presenting: pendingDeletion
        ) { entry in
            Button("Delete", role: .destructive) { delete(entry) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This can't be undone.")
        }
    }

    private var deletionBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    @ViewBuilder
    private var sidebar: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(groupedEntries, id: \.title) { group in
                    SectionHeader(title: group.title)

                    ForEach(group.entries) { entry in
                        EntryRow(entry: entry, isSelected: selectedEntry == entry)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedEntry = entry }
                    }
                }
            }
            .padding(.horizontal, Theme.Space.s)
            .padding(.bottom, Theme.Space.m)
        }
        .navigationSplitViewColumnWidth(
            min: Theme.Size.sidebarMin,
            ideal: Theme.Size.sidebarIdeal
        )
        .toolbar {
            ToolbarItem {
                Button(action: addEntry) {
                    Label("New Entry", systemImage: "square.and.pencil")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView {
                    Label("No entries yet", systemImage: "book.closed")
                } description: {
                    Text("Press ⌘N to write your first entry.")
                }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let entry = selectedEntry {
            EntryEditor(entry: entry)
                .id(entry.persistentModelID)
                .toolbar {
                    ToolbarItem {
                        Button(role: .destructive) {
                            pendingDeletion = entry
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
        } else {
            ContentUnavailableView {
                Label("Select an entry", systemImage: "book")
            } description: {
                Text("Or press ⌘N to start a new one.")
            }
        }
    }

    private var groupedEntries: [EntryGroup] {
        EntryGroup.group(entries)
    }

    private func addEntry() {
        let entry = Entry()
        modelContext.insert(entry)
        selectedEntry = entry
    }

    private func delete(_ entry: Entry) {
        if selectedEntry == entry {
            selectedEntry = nil
        }
        modelContext.delete(entry)
        pendingDeletion = nil
    }
}

// MARK: - Sidebar grouping

private struct EntryGroup {
    let title: String
    let entries: [Entry]

    static func group(_ entries: [Entry]) -> [EntryGroup] {
        let cal = Calendar.current
        let now = Date.now
        var buckets: [(String, [Entry])] = [
            ("Today", []),
            ("Yesterday", []),
            ("Previous 7 Days", []),
            ("Previous 30 Days", []),
            ("Older", [])
        ]

        for entry in entries {
            let idx: Int
            if cal.isDateInToday(entry.createdAt) { idx = 0 }
            else if cal.isDateInYesterday(entry.createdAt) { idx = 1 }
            else if let days = cal.dateComponents([.day], from: entry.createdAt, to: now).day {
                if days < 7 { idx = 2 }
                else if days < 30 { idx = 3 }
                else { idx = 4 }
            } else { idx = 4 }
            buckets[idx].1.append(entry)
        }

        return buckets.compactMap { (title, items) in
            items.isEmpty ? nil : EntryGroup(title: title, entries: items)
        }
    }
}

// MARK: - Section header

private struct SectionHeader: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.primary)
                .padding(.top, Theme.Space.l)
                .padding(.bottom, Theme.Space.s)
                .padding(.horizontal, Theme.Space.s)
            Divider()
        }
    }
}

// MARK: - Sidebar row

private struct EntryRow: View {
    let entry: Entry
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.previewTitle)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? Color.white : .primary)

                HStack(spacing: 6) {
                    Text(dateLabel)
                        .foregroundStyle(isSelected ? Color.white : .primary)
                    Text(snippet)
                        .foregroundStyle(isSelected ? Color.white.opacity(0.85) : .secondary)
                        .lineLimit(1)
                }
                .font(.system(size: 12))
            }
            .padding(.vertical, Theme.Space.s)
            .padding(.horizontal, Theme.Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )

            if !isSelected {
                Divider()
            }
        }
    }

    private var dateLabel: String {
        let cal = Calendar.current
        let date = entry.createdAt
        if cal.isDateInToday(date) {
            return date.formatted(.dateTime.hour().minute())
        }
        if cal.isDateInYesterday(date) {
            return "Yesterday"
        }
        if let days = cal.dateComponents([.day], from: date, to: .now).day, days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(.dateTime.month(.defaultDigits).day().year(.twoDigits))
    }

    private var snippet: String {
        let lines = entry.text.split(whereSeparator: \.isNewline)
        let secondLine = lines.dropFirst().first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return secondLine.isEmpty ? "No additional text" : secondLine
    }
}

// MARK: - Editor

private struct EntryEditor: View {
    @Bindable var entry: Entry
    @State private var bridge = EditorBridge()

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(nsColor: .textBackgroundColor)
                .ignoresSafeArea()

            if entry.text.isEmpty {
                Text("What's on your mind?")
                    .font(Font(bridge.fontFamily.font(size: Theme.FontSize.body)))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, Theme.Space.xxl)
                    .padding(.top, Theme.Space.xxl)
                    .allowsHitTesting(false)
            }

            RichTextEditor(data: $entry.bodyData, plainText: $entry.text, bridge: bridge)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: entry.text) { _, _ in
                    entry.updatedAt = .now
                }
        }
        .overlay(alignment: .bottom) {
            EditorToolbar(bridge: bridge)
                .padding(.bottom, Theme.Space.l)
                .padding(.horizontal, Theme.Space.l)
                .zIndex(1000)
        }
        .navigationTitle(titleLine)
        .navigationSubtitle(metadataLine)
    }

    private var titleLine: String {
        entry.createdAt.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }

private var metadataLine: String {
        let words = entry.text
            .split { $0.isWhitespace || $0.isNewline }
            .count
        let wordLabel = words == 1 ? "word" : "words"
        let edited = RelativeDateTimeFormatter()
        edited.unitsStyle = .short
        let editedString = edited.localizedString(for: entry.updatedAt, relativeTo: .now)
        return "\(words) \(wordLabel)  ·  edited \(editedString)"
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Entry.self, inMemory: true)
}

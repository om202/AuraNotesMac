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
        List(selection: $selectedEntry) {
            ForEach(entries) { entry in
                EntryRow(entry: entry).tag(entry)
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 280)
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
                ContentUnavailableView(
                    "No entries yet",
                    systemImage: "book.closed",
                    description: Text("Press ⌘N to write your first entry.")
                )
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
            ContentUnavailableView(
                "Select an entry",
                systemImage: "book",
                description: Text("Or press ⌘N to start a new one.")
            )
        }
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

private struct EntryRow: View {
    let entry: Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.previewTitle)
                .font(.headline)
                .lineLimit(1)
            Text(entry.createdAt, format: .dateTime.month().day().year().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct EntryEditor: View {
    @Bindable var entry: Entry
    @State private var bridge = EditorBridge()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorToolbar(bridge: bridge)
            Divider()
            ZStack(alignment: .topLeading) {
                if entry.text.isEmpty {
                    Text("What's on your mind?")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
                RichTextEditor(data: $entry.bodyData, plainText: $entry.text, bridge: bridge)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                    .onChange(of: entry.text) { _, _ in
                        entry.updatedAt = .now
                    }
            }
        }
        .navigationTitle(
            entry.createdAt.formatted(.dateTime.weekday(.wide).month().day().year())
        )
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Entry.self, inMemory: true)
}

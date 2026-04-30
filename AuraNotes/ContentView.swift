//
//  ContentView.swift
//  AuraNotes
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var systemColorScheme
    @Query(sort: \Entry.createdAt, order: .reverse) private var entries: [Entry]

    @State private var selectedEntry: Entry?
    @State private var pendingDeletion: Entry?
    @AppStorage("themeOverride") private var themeOverrideRaw: String = ""

    private var themeOverride: ColorScheme? {
        switch themeOverrideRaw {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .preferredColorScheme(themeOverride)
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
                Button(action: toggleThemeOverride) {
                    Label(
                        effectiveIsDark ? "Switch to Light" : "Switch to Dark",
                        systemImage: effectiveIsDark ? "sun.max.fill" : "moon.fill"
                    )
                }
                .help(effectiveIsDark
                      ? "Force light appearance"
                      : "Force dark appearance")
            }
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
            EntryEditor(entry: entry, onDelete: { pendingDeletion = entry })
                .id(entry.persistentModelID)
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

    private var effectiveIsDark: Bool {
        if let override = themeOverride { return override == .dark }
        return systemColorScheme == .dark
    }

    private func toggleThemeOverride() {
        themeOverrideRaw = effectiveIsDark ? "light" : "dark"
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
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.previewTitle)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? Color.white : .primary)

                Text(dateLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : .secondary)
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
        let time = date.formatted(.dateTime.hour().minute())
        if cal.isDateInToday(date) {
            return time
        }
        if cal.isDateInYesterday(date) {
            return "Yesterday · \(time)"
        }
        if let days = cal.dateComponents([.day], from: date, to: .now).day, days < 7 {
            return "\(date.formatted(.dateTime.weekday(.wide))) · \(time)"
        }
        return "\(date.formatted(.dateTime.month(.abbreviated).day().year(.twoDigits))) · \(time)"
    }
}

// MARK: - Editor

private struct EntryEditor: View {
    @Bindable var entry: Entry
    var onDelete: () -> Void
    @State private var bridge = EditorBridge()

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(nsColor: bridge.background.color)
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
        .alert(
            "Dictation Unavailable",
            isPresented: Binding(
                get: { bridge.dictation.lastError != nil },
                set: { if !$0 { bridge.dictation.lastError = nil } }
            ),
            presenting: bridge.dictation.lastError
        ) { _ in
            Button("OK", role: .cancel) { bridge.dictation.lastError = nil }
        } message: { message in
            Text(message)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    scaleFonts(by: 1.0 / 1.1)
                } label: {
                    Label("Decrease Font Size", systemImage: "textformat.size.smaller")
                }
                .keyboardShortcut("-", modifiers: .command)
                .help("Decrease font size (⌘−)")

                Button {
                    scaleFonts(by: 1.1)
                } label: {
                    Label("Increase Font Size", systemImage: "textformat.size.larger")
                }
                .keyboardShortcut("+", modifiers: .command)
                .help("Increase font size (⌘+)")

                Menu {
                    ForEach(EditorBackground.allCases) { option in
                        Button {
                            bridge.setBackground(option)
                        } label: {
                            HStack(spacing: 8) {
                                Image(nsImage: option.swatchImage())
                                Text(option.displayName)
                                if option == bridge.background {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Label {
                        Text("Background")
                    } icon: {
                        Image(nsImage: bridge.background.swatchImage(size: 14))
                    }
                }
                .help("Page background")

                Menu {
                    ForEach(EditorSpread.allCases) { option in
                        Button {
                            bridge.setSpread(option)
                        } label: {
                            if option == bridge.spread {
                                Label(option.displayName, systemImage: "checkmark")
                            } else {
                                Text(option.displayName)
                            }
                        }
                    }
                } label: {
                    Label("Reading Width", systemImage: "arrow.left.and.right")
                }
                .help("Reading width")

                Button {
                    bridge.toggleAssists()
                } label: {
                    Label(
                        bridge.assistsEnabled ? "Disable Writing Assists" : "Enable Writing Assists",
                        systemImage: "textformat.characters.dottedunderline"
                    )
                    .foregroundStyle(bridge.assistsEnabled ? Color.orange : Color.primary)
                }
                .help(bridge.assistsEnabled
                      ? "Turn off autocorrect, spell check, and smart substitutions"
                      : "Turn on autocorrect, spell check, and smart substitutions")

                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
                .help("Delete entry")

                Button {
                    bridge.dictation.toggle()
                } label: {
                    Group {
                        if bridge.dictation.isRecording {
                            Image(systemName: "waveform")
                                .symbolEffect(.variableColor.iterative, options: .repeat(.continuous))
                        } else {
                            Image(systemName: "mic")
                        }
                    }
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(Color(red: 255/255, green: 117/255, blue: 31/255))
                    )
                    .overlay {
                        if bridge.dictation.isRecording {
                            RotatingRing()
                        }
                    }
                }
                .buttonStyle(.plain)
                .help(bridge.dictation.isRecording
                      ? "Stop dictating"
                      : "Dictate (on-device)")
            }
        }
    }

    private func scaleFonts(by factor: CGFloat) {
        guard let tv = bridge.textView else { return }
        RichTextCommand.scaleFonts(in: tv, by: factor)
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

/// White arc tracing the circumference of the mic button, rotating
/// continuously. A faint full ring sits underneath so the orange disc
/// always reads as bordered.
private struct RotatingRing: View {
    @State private var rotation: Angle = .degrees(-90)

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(.white.opacity(0.25), lineWidth: 2)

            Circle()
                .trim(from: 0.0, to: 0.28)
                .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(rotation)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                rotation = .degrees(270)
            }
        }
    }
}
